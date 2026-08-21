// =============================================================================
// auditoria_service.dart
// Auditorías de vehículos: carga la rúbrica (catálogo editable), lista/crea
// auditorías con sus ítems y fotos, y recalcula el puntaje en BD.
//
// Todo vía Supabase directo (schema flotilla), igual que admin_service.dart.
// El puntaje lo calcula la función flotilla.recompute_auditoria(uuid).
// =============================================================================
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/auditoria.dart';

class AuditoriaService {
  static SupabaseClient get _sb => Supabase.instance.client;
  static const String _bucket = 'fotos_registro_vehiculos';

  // ── Catálogo de rúbrica (ítems activos, ordenados) ──────────────────────
  static Future<List<RubricaItem>> getRubrica() async {
    final rows = await _sb
        .schema('flotilla')
        .from('auditoria_rubrica')
        .select('*')
        .eq('activo', true)
        .order('orden', ascending: true);
    return (rows as List)
        .map((r) => RubricaItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ── Vehículos (para elegir cuál auditar) ────────────────────────────────
  static Future<List<Map<String, dynamic>>> getVehiculos() async {
    final rows = await _sb
        .schema('flotilla')
        .from('vehiculos')
        .select('id, marca, modelo, placa, type, km_actual')
        .order('marca', ascending: true);
    return (rows as List).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ── Subir fotos de la auditoría ─────────────────────────────────────────
  static Future<List<String>> subirFotos(List<File> files) async {
    final List<String> urls = [];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final ext = f.path.split('.').last;
      final ts = DateTime.now().microsecondsSinceEpoch;
      final path = 'auditorias/${ts}_$i.$ext';
      await _sb.storage.from(_bucket).upload(path, f,
          fileOptions: const FileOptions(upsert: true));
      urls.add(_sb.storage.from(_bucket).getPublicUrl(path));
    }
    return urls;
  }

  // ── Crear auditoría completa (cabecera + ítems + recompute) ─────────────
  /// Devuelve el id de la auditoría creada.
  static Future<String> crearAuditoria({
    required Auditoria cabecera,
    required List<AuditoriaItem> items,
  }) async {
    // 1) Insertar cabecera y recuperar el id
    final inserted = await _sb
        .schema('flotilla')
        .from('auditorias')
        .insert(cabecera.toInsert())
        .select('id')
        .single();
    final auditoriaId = inserted['id'].toString();

    // 2) Insertar ítems en lote
    if (items.isNotEmpty) {
      final payload = items.map((it) => it.toInsert(auditoriaId)).toList();
      await _sb.schema('flotilla').from('auditoria_items').insert(payload);
    }

    // 3) Recalcular puntaje (% ítems buenos, N/A excluido)
    await _sb
        .schema('flotilla')
        .rpc('recompute_auditoria', params: {'p_auditoria_id': auditoriaId});

    return auditoriaId;
  }

  // ── Historial de auditorías del auditor (o todas si admin) ──────────────
  static Future<List<Auditoria>> getMisAuditorias({
    required String auditorId,
    bool verTodas = false,
  }) async {
    var q = _sb.schema('flotilla').from('auditorias').select('*');
    if (!verTodas) q = q.eq('auditor_id', auditorId);
    final rows = await q.order('fecha_auditoria', ascending: false).limit(100);

    final list = (rows as List)
        .map((r) => Auditoria.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    if (list.isEmpty) return list;

    // Hidratar vehículo (marca/placa) en lote
    final vehIds =
        list.map((a) => a.vehiculoId).where((v) => v != null).toSet().toList();
    if (vehIds.isNotEmpty) {
      final vs = await _sb
          .schema('flotilla')
          .from('vehiculos')
          .select('id, marca, modelo, placa')
          .inFilter('id', vehIds);
      _vehCache
          .addEntries((vs as List).map((v) => MapEntry(v['id'].toString(), Map<String, dynamic>.from(v))));
    }
    return list;
  }

  // Cache simple de vehículos para pintar en la lista/detalle
  static final Map<String, Map<String, dynamic>> _vehCache = {};
  static Map<String, dynamic>? vehiculoInfo(String? id) =>
      id == null ? null : _vehCache[id];

  // ── Detalle: cabecera + ítems ───────────────────────────────────────────
  static Future<List<AuditoriaItem>> getItems(String auditoriaId) async {
    final rows = await _sb
        .schema('flotilla')
        .from('auditoria_items')
        .select('*')
        .eq('auditoria_id', auditoriaId);
    return (rows as List)
        .map((r) => AuditoriaItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }
}
