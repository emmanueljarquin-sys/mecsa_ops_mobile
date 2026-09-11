import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'cache_service.dart';
import 'connectivity_service.dart';
import 'liquidaciones_local.dart';
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

      // Fail-closed: nunca consultar liquidaciones sin un empleadoId válido.
      // Si el filtro se omitiera, Supabase devolvería liquidaciones de otros usuarios.
      final bool empleadoIdValido = empleadoId != null && empleadoId != 'null' && empleadoId.isNotEmpty;
      print('DEBUG getLiquidaciones: empleadoId=[$empleadoId] valido=$empleadoIdValido');
      if (!empleadoIdValido) {
        throw Exception('empleadoId requerido para consultar liquidaciones (recibido: "$empleadoId")');
      }

      var query = supabase
          .schema('viaticos')
          .from('liquidaciones')
          .select('*')
          .eq('empleado_id', empleadoId);

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
  /// Detalle desde SQLite (último mes o creada sin conexión). Recalcula los
  /// totales por tipo a partir de sus facturas.
  static Future<Liquidacion?> _detalleDeSqlite(String id) async {
    final l = await LiquidacionesLocal.instance.obtener(id);
    if (l == null) return null;
    final Map<String, double> totales = {};
    for (final f in l.facturas ?? <Factura>[]) {
      totales[f.tipo] = (totales[f.tipo] ?? 0) + f.monto;
    }
    totales['TOTAL'] = totales.values.fold(0.0, (a, b) => a + b);
    final j = <String, dynamic>{
      'id': l.id,
      'empleado_id': l.empleadoId,
      'fecha': l.fecha.toIso8601String().split('T')[0],
      'tarjeta_ult4': l.tarjetaUlt4,
      'proyecto_id': l.proyectoId,
      'tipo': l.tipo,
      'personal_incluido': l.personalIncluido,
      'estado': l.estado,
      'total': l.total,
      'created_at': l.createdAt.toIso8601String(),
      'descripcion': l.descripcion,
      'solicitud_correccion': l.solicitudCorreccion,
      'respuesta_admin': l.respuestaAdmin,
      'facturas': (l.facturas ?? [])
          .map((f) => {...f.toJson(), 'id': f.id, 'documento_local': f.localDocPath})
          .toList(),
      'totales': totales,
    };
    final r = Liquidacion.fromJson(j);
    r.esLocal = l.esLocal;
    return r;
  }

  /// Detalle de una liquidación. Con conexión consulta el servidor y guarda
  /// la fila en SQLite; sin conexión (o si falla) la lee de SQLite.
  static Future<Liquidacion> getLiquidacionDetail(String id) async {
    if (id.startsWith('local-') || !await connectivity.checkInternet()) {
      final local = await _detalleDeSqlite(id);
      if (local != null) return local;
      throw 'Sin conexión y esta liquidación no está guardada en el teléfono.';
    }
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

      // Calcular resumen de totales agrupando facturas por tipo.
      // Antes lo calculaba el endpoint PHP get_liquidacion_detail.php;
      // al migrar a Supabase directo se perdió y el detalle mostraba ₡0.
      final Map<String, double> totales = {};
      for (final f in (facturasRes as List)) {
        final tipo = (f['tipo'] ?? 'OTROS').toString();
        final monto = (f['monto'] as num?)?.toDouble() ?? 0.0;
        totales[tipo] = (totales[tipo] ?? 0) + monto;
      }
      data['totales'] = totales;

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

      // Mantener la copia local al día para verla luego sin red.
      await LiquidacionesLocal.instance.guardarUna(data);
      return Liquidacion.fromJson(data);
    } catch (e) {
      print('DEBUG: ERROR en getLiquidacionDetail vía Supabase: $e');
      final local = await _detalleDeSqlite(id);
      if (local != null) return local;
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
        // El servidor devuelve el motivo real en el body (ej. "descripción
        // obligatoria sin proyecto"). Mostrarlo en vez del código pelado.
        String msg = 'Error al conectar con el servidor: ${response.statusCode}';
        try {
          final err = jsonDecode(response.body);
          if (err is Map && err['error'] != null) {
            msg = err['error'].toString();
          }
        } catch (_) {}
        throw Exception(msg);
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

  // Actualizar factura (solo si la liquidación sigue pendiente — lo valida
  // el trigger viaticos._guard_factura_editable en la BD).
  static Future<Factura> updateFactura(String id, Factura factura) async {
    try {
      final supabase = Supabase.instance.client;
      final data = factura.toJson()..remove('liquidacion_id');
      final res = await supabase
          .schema('viaticos')
          .from('facturas')
          .update(data)
          .eq('id', id)
          .select()
          .single();
      return Factura.fromJson(res);
    } catch (e) {
      print('DEBUG: ERROR en updateFactura vía Supabase: $e');
      rethrow;
    }
  }

  // ── Comentarios (hilo/bitácora de una liquidación) ─────────────────────
  static Future<List<Map<String, dynamic>>> getComentarios(String liquidacionId) async {
    final supabase = Supabase.instance.client;
    final rows = await supabase
        .schema('viaticos')
        .from('liquidacion_comentarios')
        .select('*')
        .eq('liquidacion_id', liquidacionId)
        .order('created_at', ascending: true);
    return (rows as List).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<void> addComentario({
    required String liquidacionId,
    String? autorId,
    String? autorNombre,
    required String comentario,
  }) async {
    final supabase = Supabase.instance.client;
    await supabase.schema('viaticos').from('liquidacion_comentarios').insert({
      'liquidacion_id': liquidacionId,
      'autor_id': autorId,
      'autor_nombre': autorNombre,
      'comentario': comentario,
    });
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
  // Claves de caché (SQLite, tabla `cache`, separadas por usuario).
  static const String _kCacheEmpleados = 'liq_empleados';
  static const String _kCacheProyectos = 'liq_proyectos';
  /// Cuántos proyectos (los más recientes) se guardan para uso sin conexión.
  static const int proyectosEnCache = 100;

  static Future<List<Empleado>> _empleadosDeCache() async {
    final hit = await cache.get(_kCacheEmpleados);
    return (hit?.asList() ?? []).map((e) => Empleado.fromJson(e)).toList();
  }

  static Future<List<Proyecto>> _proyectosDeCache() async {
    final hit = await cache.get(_kCacheProyectos);
    return (hit?.asList() ?? []).map((e) => Proyecto.fromJson(e)).toList();
  }

  /// Personal para "personal incluido". Con conexión consulta y guarda en
  /// caché; sin conexión (o si falla) devuelve la última lista guardada.
  static Future<List<Empleado>> getEmpleados() async {
    if (!await connectivity.checkInternet()) return _empleadosDeCache();
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('Empleados')
          .select('id, nombre, apellido')
          .order('nombre')
          .timeout(const Duration(seconds: 20));
      final rows = List<Map<String, dynamic>>.from(res as List);
      await cache.put(_kCacheEmpleados, rows);
      return rows.map((e) => Empleado.fromJson(e)).toList();
    } catch (e) {
      print('DEBUG: ERROR cargando empleados en LiquidacionesService: $e');
      return _empleadosDeCache();
    }
  }

  // Obtener proyectos
  /// Proyectos. Con conexión trae todos (paginado) y guarda en caché los
  /// [proyectosEnCache] más recientes; sin conexión devuelve esa caché.
  static Future<List<Proyecto>> getProyectos() async {
    if (!await connectivity.checkInternet()) return _proyectosDeCache();
    try {
      final supabase = Supabase.instance.client;
      // PostgREST limita cada request a 1000 filas. Con 2600+ proyectos,
      // una sola consulta dejaba fuera a los más nuevos (ej. 2648).
      // Paginamos con range() hasta traerlos todos.
      const pageSize = 1000;
      final List<Proyecto> all = [];
      int from = 0;
      while (true) {
        final res = await supabase
            .schema('proyectos')
            .from('projects')
            .select('project_id, title')
            .order('project_id', ascending: false) // más recientes primero
            .range(from, from + pageSize - 1);
        final list = res as List;
        all.addAll(list.map((p) => Proyecto(
              id: p['project_id'],
              nombre: p['title'] ?? 'Sin nombre',
            )));
        if (list.length < pageSize) break;
        from += pageSize;
      }
      // Los más recientes ya vienen primero (order project_id desc).
      await cache.put(
        _kCacheProyectos,
        all.take(proyectosEnCache).map((p) => {'id': p.id, 'nombre': p.nombre, 'zona': p.zona}).toList(),
      );
      return all;
    } catch (e) {
      print('DEBUG: ERROR cargando proyectos vía Supabase: $e');
      return _proyectosDeCache();
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
