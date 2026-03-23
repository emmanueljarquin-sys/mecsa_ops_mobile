import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/liquidacion.dart';

class LiquidacionesService {
  // Cambiar esta URL por la URL de tu servidor
  // Actualizado: usar ruta 'ops' en lugar de 'MecsaOPS'
  static const String baseUrl = 'https://grupomecsa.net/ops/api';

  // Obtener lista de liquidaciones con filtros
  static Future<Map<String, dynamic>> getLiquidaciones({
    String? empleadoId,
    int? proyectoId,
    String? estado,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final offset = (page - 1) * limit;

      var query = supabase
          .schema('viaticos')
          .from('liquidaciones')
          .select('*');

      // Filtros
      if (empleadoId != null && empleadoId != 'null' && empleadoId.isNotEmpty) {
        query = query.eq('empleado_id', empleadoId);
      }
      if (proyectoId != null) {
        query = query.eq('proyecto_id', proyectoId);
      }
      if (estado != null) {
        query = query.eq('estado', estado);
      }
      if (fechaDesde != null) {
        query = query.gte('fecha', fechaDesde.toIso8601String().split('T')[0]);
      }
      if (fechaHasta != null) {
        query = query.lte('fecha', fechaHasta.toIso8601String().split('T')[0]);
      }

      final res = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .count(CountOption.exact);

      final List<dynamic> data = res.data;
      final int count = res.count;

      if (data.isEmpty) {
        return {
          'liquidaciones': <Liquidacion>[],
          'pagination': { 'page': page, 'limit': limit, 'total': count },
        };
      }

      // 1. Recolectar IDs únicos con casteo explícito
      final empIds = data.map((l) => l['empleado_id']?.toString()).where((id) => id != null && id.isNotEmpty).toSet().toList();
      final proyIds = data.map((l) => l['proyecto_id']).where((id) => id != null).toSet().toList();

      // 2. Fetch en bloque de Empleados
      final Map<String, dynamic> empMap = {};
      if (empIds.isNotEmpty) {
        try {
          final empsRes = await supabase
              .from('Empleados')
              .select('id, nombre, apellido')
              .inFilter('id', empIds);
          for (var e in empsRes) {
            empMap[e['id'].toString()] = e;
          }
        } catch (e) {
          print('DEBUG: RLS o Error en batch Empleados: $e');
        }
      }

      // 3. Fetch en bloque de Proyectos
      final Map<String, String> proyMap = {};
      if (proyIds.isNotEmpty) {
        try {
          final proysRes = await supabase
              .schema('proyectos')
              .from('projects')
              .select('project_id, title')
              .inFilter('project_id', proyIds);
          for (var p in proysRes) {
            proyMap[p['project_id'].toString()] = p['title'] ?? 'Sin título';
          }
        } catch (e) {
          print('DEBUG: RLS o Error en batch Proyectos: $e');
        }
      }

      // 4. Mapear resultados
      final List<Liquidacion> liquidaciones = data.map((item) {
        final Map<String, dynamic> itemMap = Map<String, dynamic>.from(item);
        final String? eid = itemMap['empleado_id']?.toString();
        final String? pid = itemMap['proyecto_id']?.toString();

        if (eid != null && empMap.containsKey(eid)) {
          itemMap['empleado'] = empMap[eid];
        }
        if (pid != null && proyMap.containsKey(pid)) {
          itemMap['proyecto'] = {'nombre': proyMap[pid]};
        }

        return Liquidacion.fromJson(itemMap);
      }).toList();

      return {
        'liquidaciones': liquidaciones,
        'pagination': {
          'page': page,
          'limit': limit,
          'total': count,
        },
      };
    } catch (e) {
      print('DEBUG: ERROR en getLiquidaciones vía Supabase: $e');
      rethrow;
    }
  }

  // Obtener detalle de una liquidación
  static Future<Liquidacion> getLiquidacionDetail(String id) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Obtener liquidación base
      final res = await supabase
          .schema('viaticos')
          .from('liquidaciones')
          .select('*')
          .eq('id', id)
          .single();
      
      // Obtener facturas relacionadas
      final facturasRes = await supabase
          .schema('viaticos')
          .from('facturas')
          .select('*')
          .eq('liquidacion_id', id);
      
      final Map<String, dynamic> data = Map<String, dynamic>.from(res);
      data['facturas'] = facturasRes;
      
      // Hidratar con datos de empleado (public)
      final empRes = await supabase
          .from('Empleados')
          .select('nombre, apellido')
          .eq('id', data['empleado_id'])
          .maybeSingle();
      if (empRes != null) data['empleado'] = empRes;

      // Hidratar con datos de proyecto (proyectos)
      if (data['proyecto_id'] != null) {
        final proyRes = await supabase
            .schema('proyectos')
            .from('projects')
            .select('title')
            .eq('project_id', data['proyecto_id'])
            .maybeSingle();
        if (proyRes != null) {
          data['proyecto'] = {'nombre': proyRes['title']};
        }
      }

      return Liquidacion.fromJson(data);
    } catch (e) {
      print('DEBUG: ERROR en getLiquidacionDetail vía Supabase: $e');
      rethrow;
    }
  }

  // Crear nueva liquidación vía API PHP (para disparar notificaciones)
  static Future<Liquidacion> createLiquidacion(Liquidacion liquidacion) async {
    try {
      final url = Uri.parse('$baseUrl/create_liquidacion.php');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(liquidacion.toJson()),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> result = jsonDecode(response.body);
        if (result['success'] == true) {
          return Liquidacion.fromJson(result['data']);
        } else {
          throw Exception(result['error'] ?? 'Error desconocido en el servidor');
        }
      } else {
        throw Exception('Error al conectar con el servidor: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: ERROR en createLiquidacion vía API PHP: $e');
      rethrow;
    }
  }

  // Actualizar liquidación
  static Future<Liquidacion> updateLiquidacion(
    String id,
    Liquidacion liquidacion,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      final data = liquidacion.toJson();
      
      final res = await supabase
          .schema('viaticos')
          .from('liquidaciones')
          .update(data)
          .eq('id', id)
          .select()
          .single();
          
      return Liquidacion.fromJson(res);
    } catch (e) {
      print('DEBUG: ERROR en updateLiquidacion vía Supabase: $e');
      rethrow;
    }
  }

  // Eliminar liquidación
  static Future<void> deleteLiquidacion(String id) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .schema('viaticos')
          .from('liquidaciones')
          .delete()
          .eq('id', id);
    } catch (e) {
      print('DEBUG: ERROR en deleteLiquidacion vía Supabase: $e');
      rethrow;
    }
  }

  // Crear factura
  static Future<Factura> createFactura(Factura factura) async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .schema('viaticos')
          .from('facturas')
          .insert(factura.toJson())
          .select()
          .single();
          
      return Factura.fromJson(res);
    } catch (e) {
      print('DEBUG: ERROR en createFactura vía Supabase: $e');
      rethrow;
    }
  }

  // Eliminar factura
  static Future<void> deleteFactura(String id) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .schema('viaticos')
          .from('facturas')
          .delete()
          .eq('id', id);
    } catch (e) {
      print('DEBUG: ERROR en deleteFactura vía Supabase: $e');
      rethrow;
    }
  }

  // Aprobar/Rechazar liquidación
  static Future<Liquidacion> approveLiquidacion(
    String id,
    String estado, {
    String? comentario,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final updateData = {'estado': estado};
      // Aquí se podría guardar el comentario en una tabla de auditoría o columna si existiera
      
      final res = await supabase
          .schema('viaticos')
          .from('liquidaciones')
          .update(updateData)
          .eq('id', id)
          .select()
          .single();
          
      return Liquidacion.fromJson(res);
    } catch (e) {
      print('DEBUG: ERROR en approveLiquidacion vía Supabase: $e');
      rethrow;
    }
  }

  // Obtener empleados
  static Future<List<Empleado>> getEmpleados() async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('Empleados')
          .select('id, nombre, apellido')
          .order('nombre');
      
      return (res as List).map((e) => Empleado.fromJson(e)).toList();
    } catch (e) {
      print('DEBUG: ERROR cargando empleados en LiquidacionesService: $e');
      return [];
    }
  }

  // Obtener proyectos
  static Future<List<Proyecto>> getProyectos() async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .schema('proyectos')
          .from('projects')
          .select('project_id, title')
          .order('title');
      
      return (res as List).map((p) {
        // Mapear 'project_id' a 'id' y 'title' a 'nombre' para el modelo Proyecto
        return Proyecto(
          id: p['project_id'],
          nombre: p['title'] ?? 'Sin nombre',
        );
      }).toList();
    } catch (e) {
      print('DEBUG: ERROR cargando proyectos vía Supabase: $e');
      return [];
    }
  }

  // Subir documento
  static Future<String> uploadDocumento(String filePath) async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      
      if (session == null) {
        throw "No hay una sesión activa. Por favor, vuelve a iniciar sesión.";
      }

      final file = File(filePath);
      if (!await file.exists()) {
        throw "El archivo no existe en la ruta: $filePath";
      }

      final fileName = "${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}";
      
      print('DEBUG: Intento de subida a bucket: facturas_viaticos');
      print('DEBUG: File: $fileName | User: ${session.user.id}');

      await supabase.storage
          .from('facturas_viaticos')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));
          
      return fileName;
    } catch (e) {
      print('DEBUG: Error CRITICO en uploadDocumento: $e');
      if (e is StorageException) {
        print('DEBUG: Storage Error Body: ${e.message} | Code: ${e.statusCode}');
      }
      rethrow;
    }
  }
}
