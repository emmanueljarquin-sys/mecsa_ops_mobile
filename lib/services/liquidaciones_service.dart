import 'dart:convert';
import 'package:http/http.dart' as http;
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
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (empleadoId != null) queryParams['empleado_id'] = empleadoId;
    if (proyectoId != null) queryParams['proyecto_id'] = proyectoId.toString();
    if (estado != null) queryParams['estado'] = estado;
    if (fechaDesde != null) {
      queryParams['fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
    }
    if (fechaHasta != null) {
      queryParams['fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
    }

    final uri = Uri.parse(
      '$baseUrl/get_liquidaciones.php',
    ).replace(queryParameters: queryParams);

    print('DEBUG: Cargando liquidaciones desde $uri');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      print('DEBUG: Respuesta recibida: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          print(
            'DEBUG: Datos obtenidos con éxito. Cantidad: ${(data['data'] as List).length}',
          );
          return {
            'liquidaciones': (data['data'] as List)
                .map((l) => Liquidacion.fromJson(l))
                .toList(),
            'pagination': data['pagination'],
          };
        } else {
          print('DEBUG: Error en la respuesta del API: ${data['error']}');
          throw Exception(data['error'] ?? 'Error desconocido');
        }
      } else {
        print('DEBUG: Error de servidor o conexión: ${response.statusCode}');
        throw Exception('Error de conexión: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Excepción capturada en getLiquidaciones: $e');
      rethrow;
    }
  }

  // Obtener detalle de una liquidación
  static Future<Liquidacion> getLiquidacionDetail(String id) async {
    final uri = Uri.parse('$baseUrl/get_liquidacion_detail.php?id=$id');

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return Liquidacion.fromJson(data['data']);
      } else {
        throw Exception(data['error'] ?? 'Error desconocido');
      }
    } else {
      throw Exception('Error de conexión: ${response.statusCode}');
    }
  }

  // Crear nueva liquidación
  static Future<Liquidacion> createLiquidacion(Liquidacion liquidacion) async {
    final uri = Uri.parse('$baseUrl/create_liquidacion.php');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(liquidacion.toJson()),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return Liquidacion.fromJson(data['data']);
      } else {
        throw Exception(data['error'] ?? 'Error desconocido');
      }
    } else {
      throw Exception('Error de conexión: ${response.statusCode}');
    }
  }

  // Actualizar liquidación
  static Future<Liquidacion> updateLiquidacion(
    String id,
    Liquidacion liquidacion,
  ) async {
    final uri = Uri.parse('$baseUrl/update_liquidacion.php');

    final body = liquidacion.toJson();
    body['id'] = id;

    final response = await http.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return Liquidacion.fromJson(data['data']);
      } else {
        throw Exception(data['error'] ?? 'Error desconocido');
      }
    } else {
      throw Exception('Error de conexión: ${response.statusCode}');
    }
  }

  // Eliminar liquidación
  static Future<void> deleteLiquidacion(String id) async {
    final uri = Uri.parse('$baseUrl/delete_liquidacion.php');

    final request = http.Request('DELETE', uri);
    request.headers['Content-Type'] = 'application/json';
    request.body = json.encode({'id': id});

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (!data['success']) {
        throw Exception(data['error'] ?? 'Error desconocido');
      }
    } else {
      throw Exception('Error de conexión: ${response.statusCode}');
    }
  }

  // Crear factura
  static Future<Factura> createFactura(Factura factura) async {
    final uri = Uri.parse('$baseUrl/create_factura.php');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(factura.toJson()),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return Factura.fromJson(data['data']);
      } else {
        throw Exception(data['error'] ?? 'Error desconocido');
      }
    } else {
      throw Exception('Error de conexión: ${response.statusCode}');
    }
  }

  // Eliminar factura
  static Future<void> deleteFactura(String id) async {
    final uri = Uri.parse('$baseUrl/delete_factura.php');

    final request = http.Request('DELETE', uri);
    request.headers['Content-Type'] = 'application/json';
    request.body = json.encode({'id': id});

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (!data['success']) {
        throw Exception(data['error'] ?? 'Error desconocido');
      }
    } else {
      throw Exception('Error de conexión: ${response.statusCode}');
    }
  }

  // Aprobar/Rechazar liquidación
  static Future<Liquidacion> approveLiquidacion(
    String id,
    String estado, {
    String? comentario,
  }) async {
    final uri = Uri.parse('$baseUrl/approve_liquidacion.php');

    final body = {'id': id, 'estado': estado};
    if (comentario != null && comentario.isNotEmpty) {
      body['comentario'] = comentario;
    }

    final response = await http.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return Liquidacion.fromJson(data['data']);
      } else {
        throw Exception(data['error'] ?? 'Error desconocido');
      }
    } else {
      throw Exception('Error de conexión: ${response.statusCode}');
    }
  }

  // Obtener empleados
  static Future<List<Empleado>> getEmpleados() async {
    final uri = Uri.parse('$baseUrl/get_empleados_list.php');
    print('DEBUG: Cargando empleados desde $uri');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      print('DEBUG: Empleados respuesta: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          print('DEBUG: Empleados cargados: ${(data['data'] as List).length}');
          return (data['data'] as List)
              .map((e) => Empleado.fromJson(e))
              .toList();
        }
      }
    } catch (e) {
      print('DEBUG: ERROR cargando empleados: $e');
    }
    return [];
  }

  // Obtener proyectos
  static Future<List<Proyecto>> getProyectos() async {
    final uri = Uri.parse('$baseUrl/get_proyectos_list.php');
    print('DEBUG: Cargando proyectos desde $uri');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      print('DEBUG: Proyectos respuesta: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          print('DEBUG: Proyectos cargados: ${(data['data'] as List).length}');
          return (data['data'] as List)
              .map((p) => Proyecto.fromJson(p))
              .toList();
        } else {
          print('DEBUG: API Error proyectos: ${response.body}');
          throw Exception(data['error'] ?? 'Error desconocido');
        }
      } else {
        print(
          'DEBUG: Server Error proyectos (${response.statusCode}): ${response.body}',
        );
        throw Exception('Error de conexión: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: ERROR crítico cargando proyectos: $e');
      rethrow;
    }
    return [];
  }

  // Subir documento
  static Future<String> uploadDocumento(String filePath) async {
    // URL base siempre con HTTPS para evitar redirecciones 301
    const uploadUrl = 'https://grupomecsa.net/ops/api/upload_factura_documento.php';
    final uri = Uri.parse(uploadUrl);

    try {
      var request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('documento', filePath),
      );

      // Enviar sin seguir redirecciones para atrapar el 301
      final streamedResponse = await request.send();
      
      // Si hay una redirección, seguirla manualmente con la nueva URL
      if (streamedResponse.statusCode == 301 || streamedResponse.statusCode == 302) {
        final location = streamedResponse.headers['location'];
        if (location != null) {
          print('DEBUG: Redirigiendo subida a: $location');
          final redirectUri = Uri.parse(location);
          var redirectRequest = http.MultipartRequest('POST', redirectUri);
          redirectRequest.files.add(
            await http.MultipartFile.fromPath('documento', filePath),
          );
          final redirectedResponse = await redirectRequest.send();
          final response = await http.Response.fromStream(redirectedResponse);
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success']) return data['path'];
            throw Exception(data['error'] ?? 'Error al subir archivo');
          }
          throw Exception('Error de conexión tras redirección: ${response.statusCode}');
        }
      }

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['path'];
        } else {
          throw Exception(data['error'] ?? 'Error al subir archivo');
        }
      } else {
        throw Exception('Error de conexión: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Error in uploadDocumento: $e');
      rethrow;
    }
  }
}
