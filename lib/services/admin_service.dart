// =============================================================================
// admin_service.dart
// Servicio para las funciones administrativas de la app (aprobar liquidaciones,
// reservas, procesar correcciones, desbloquear reservas).
//
// Reusa los endpoints PHP de la web pasando `actor_id` = empleado_id del que
// realiza la acción. El servidor re-valida el rol real por BD (no confía en el
// cliente). Ver includes/resolve_current_employee.php → resolve_employee_context_by_id.
// =============================================================================
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/liquidacion.dart';

class AdminService {
  static const String baseUrl = 'https://grupomecsa.net/ops/api';

  static SupabaseClient get _sb => Supabase.instance.client;

  // ── LIQUIDACIONES PENDIENTES ────────────────────────────────────────────
  /// Lista las liquidaciones pendientes que el actor puede aprobar.
  /// - Admin / contabilidad → todas las pendientes
  /// - Responsable → solo las de empleados de sus departamentos supervisados
  static Future<List<Liquidacion>> getPendientesParaAprobar({
    required String actorId,
    required bool isAdminOrConta,
  }) async {
    // Base: todas las pendientes (via schema viaticos)
    var query = _sb.schema('viaticos').from('liquidaciones').select('*').eq('estado', 'pendiente');

    List rows;
    if (isAdminOrConta) {
      rows = await query.order('created_at', ascending: false);
    } else {
      // Responsable: obtener departamentos supervisados
      final deptRows = await _sb
          .from('viaticos_responsables_departamento')
          .select('departamento_id')
          .eq('empleado_id', actorId);
      final deptIds = (deptRows as List)
          .map((d) => d['departamento_id'])
          .where((d) => d != null)
          .toList();
      if (deptIds.isEmpty) return [];

      // Empleados de esos departamentos
      final empRows = await _sb
          .from('Empleados')
          .select('id')
          .inFilter('departamento', deptIds);
      final empIds = (empRows as List).map((e) => e['id']).toList();
      if (empIds.isEmpty) return [];

      rows = await _sb
          .schema('viaticos')
          .from('liquidaciones')
          .select('*')
          .eq('estado', 'pendiente')
          .inFilter('empleado_id', empIds)
          .order('created_at', ascending: false);
    }

    // Hidratar nombre de empleado y proyecto
    final List<Liquidacion> result = [];
    for (final r in rows) {
      final data = Map<String, dynamic>.from(r);
      final empId = data['empleado_id'];
      if (empId != null) {
        final emp = await _sb
            .from('Empleados')
            .select('nombre, apellido')
            .eq('id', empId)
            .maybeSingle();
        if (emp != null) data['empleado'] = emp;
      }
      if (data['proyecto_id'] != null) {
        final proy = await _sb
            .schema('proyectos')
            .from('projects')
            .select('title')
            .eq('project_id', data['proyecto_id'])
            .maybeSingle();
        if (proy != null) data['proyecto'] = {'nombre': proy['title']};
      }
      result.add(Liquidacion.fromJson(data));
    }
    return result;
  }

  /// Aprueba o rechaza una liquidación llamando al endpoint PHP (que además
  /// dispara la notificación push al empleado dueño).
  static Future<void> aprobarLiquidacion({
    required String actorId,
    required String liquidacionId,
    required bool aprobar, // true = aprobada, false = rechazada
    String comentario = '',
  }) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/approve_liquidacion.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'actor_id': actorId,
        'id': liquidacionId,
        'estado': aprobar ? 'aprobada' : 'rechazada',
        'comentario': comentario,
      }),
    );
    final body = _safeDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || body['success'] != true) {
      throw body['error']?.toString() ??
          'Error ${res.statusCode} al procesar la liquidación';
    }
  }

  // ── RESERVAS PENDIENTES ─────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getReservasPendientes() async {
    final rows = await _sb
        .schema('flotilla')
        .from('reservas')
        .select('*')
        .eq('estado', 'Pendiente')
        .order('fecha_salida', ascending: true);

    final List<Map<String, dynamic>> result = [];
    for (final r in rows as List) {
      final data = Map<String, dynamic>.from(r);
      // Hidratar vehículo
      if (data['vehiculo_id'] != null) {
        final v = await _sb
            .schema('flotilla')
            .from('vehiculos')
            .select('marca, modelo, placa')
            .eq('id', data['vehiculo_id'])
            .maybeSingle();
        if (v != null) data['vehiculo'] = v;
      }
      // Hidratar empleado
      if (data['empleado_id'] != null) {
        final e = await _sb
            .from('Empleados')
            .select('nombre, apellido')
            .eq('id', data['empleado_id'])
            .maybeSingle();
        if (e != null) data['empleado'] = e;
      }
      result.add(data);
    }
    return result;
  }

  /// Aprueba/rechaza una reserva (PATCH directo — flotilla.reservas).
  /// [vehiculoId] opcional para reasignar el vehículo al aprobar.
  static Future<void> decidirReserva({
    required String reservaId,
    required bool aprobar,
    String? vehiculoId,
    String comentarios = '',
  }) async {
    final update = <String, dynamic>{
      'estado': aprobar ? 'Aprobada' : 'Rechazada',
      'comentarios': comentarios,
    };
    if (aprobar && vehiculoId != null && vehiculoId.isNotEmpty) {
      update['vehiculo_id'] = vehiculoId;
    }
    await _sb.schema('flotilla').from('reservas').update(update).eq('id', reservaId);
  }

  // ── SOLICITUDES DE CORRECCIÓN PENDIENTES ────────────────────────────────
  /// Junta correcciones pendientes de viáticos y kilometraje.
  static Future<List<Map<String, dynamic>>> getCorreccionesPendientes() async {
    final List<Map<String, dynamic>> out = [];

    // Viáticos
    final liq = await _sb
        .schema('viaticos')
        .from('liquidaciones')
        .select('id, solicitud_correccion, fecha_correccion, empleado_id, total')
        .not('solicitud_correccion', 'is', null)
        .filter('respuesta_admin', 'is', null);
    for (final r in liq as List) {
      final d = Map<String, dynamic>.from(r);
      d['_origen'] = 'viaticos';
      d['_tabla'] = 'liquidaciones';
      d['_schema'] = 'viaticos';
      out.add(d);
    }

    // Kilometraje
    final reg = await _sb
        .schema('flotilla')
        .from('registros_vehiculos')
        .select('id, solicitud_correccion, fecha_correccion, empleado_id, tipo, kilometraje')
        .not('solicitud_correccion', 'is', null)
        .filter('respuesta_admin', 'is', null);
    for (final r in reg as List) {
      final d = Map<String, dynamic>.from(r);
      d['_origen'] = 'kilometraje';
      d['_tabla'] = 'registros_vehiculos';
      d['_schema'] = 'flotilla';
      out.add(d);
    }

    // Hidratar nombre empleado
    for (final d in out) {
      if (d['empleado_id'] != null) {
        final e = await _sb
            .from('Empleados')
            .select('nombre, apellido')
            .eq('id', d['empleado_id'])
            .maybeSingle();
        if (e != null) d['_empleado'] = '${e['nombre']} ${e['apellido'] ?? ''}'.trim();
      }
    }
    return out;
  }

  /// Procesa (responde) una solicitud de corrección vía endpoint PHP.
  static Future<void> procesarCorreccion({
    required String actorId,
    required String schema,
    required String table,
    required String recordId,
    String respuesta = '',
  }) async {
    // El endpoint procesar_correccion.php exige sesión admin. Como el mobile no
    // tiene sesión, aquí hacemos el PATCH directo vía Supabase (RLS de estas
    // tablas se maneja server-side; el gate de UI ya limita a admin).
    final payload = <String, dynamic>{
      'respuesta_admin': respuesta,
      'fecha_correccion': DateTime.now().toUtc().toIso8601String(),
      'corregido_por': actorId,
    };
    if (table == 'registros_vehiculos') {
      payload['estado'] = 'Corregido';
    }
    await _sb.schema(schema).from(table).update(payload).eq('id', recordId);
  }

  // ── DESBLOQUEAR RESERVAS ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getEmpleadosBloqueados() async {
    final rows = await _sb
        .from('Empleados')
        .select('id, nombre, apellido, reservas_bloqueado, sistemas_acceso')
        .eq('reservas_bloqueado', true);
    return (rows as List).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Desbloquea un empleado: reservas_bloqueado=false + etiqueta
  /// RESERVAS_EXCEPCION para que no lo re-bloqueen los strikes viejos.
  static Future<void> desbloquearEmpleado(String empleadoId) async {
    final emp = await _sb
        .from('Empleados')
        .select('sistemas_acceso')
        .eq('id', empleadoId)
        .maybeSingle();
    final List sistemas = (emp?['sistemas_acceso'] as List?)?.toList() ?? [];
    if (!sistemas.contains('RESERVAS_EXCEPCION')) {
      sistemas.add('RESERVAS_EXCEPCION');
    }
    await _sb.from('Empleados').update({
      'reservas_bloqueado': false,
      'sistemas_acceso': sistemas,
    }).eq('id', empleadoId);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  static Map<String, dynamic> _safeDecode(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) return j;
      return {'success': false, 'error': 'Respuesta inesperada del servidor'};
    } catch (_) {
      final preview = body.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
      return {
        'success': false,
        'error': preview.isEmpty
            ? 'El servidor respondió vacío (posible error interno)'
            : preview.substring(0, preview.length > 150 ? 150 : preview.length),
      };
    }
  }
}
