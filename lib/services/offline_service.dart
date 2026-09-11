// =============================================================================
// offline_service.dart — Cola de sincronización offline
// -----------------------------------------------------------------------------
// Guarda operaciones (registros de salida/entrada, liquidaciones, facturas)
// y sus fotos en el celular cuando no hay conexión, y las sube automáticamente
// cuando vuelve el internet (o al abrir la app).
//
// CONSERVADOR: una operación NUNCA se borra de la cola local hasta que el
// servidor confirma que subió. En el peor caso queda "pendiente" (visible),
// nunca se pierde.
// =============================================================================
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'app_logger.dart';

class OfflineService extends ChangeNotifier {
  OfflineService._();
  static final OfflineService instance = OfflineService._();

  static const String _kQueue = 'offline_queue_v1';
  static const String _baseUrl = 'https://grupomecsa.net/ops/api';

  final SupabaseClient _sb = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  List<Map<String, dynamic>> _ops = [];
  bool _initialized = false;
  bool _flushing = false;
  String? _photosDir;

  int get pendingCount => _ops.length;
  bool get isFlushing => _flushing;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _photosDir = '${dir.path}/offline_photos';
      await Directory(_photosDir!).create(recursive: true);
    } catch (e, st) {
      log.e('offline', 'No se pudo crear carpeta de fotos', error: e, stack: st);
    }
    await _load();
    log.i('offline', 'Cola offline cargada', data: {'pendientes': _ops.length});
    Connectivity().onConnectivityChanged.listen((result) {
      final online = _online(result);
      log.i('offline', online ? 'Conectividad: red disponible' : 'Conectividad: sin red',
          data: {'tipos': result.map((r) => r.name).toList()});
      if (online) flush();
    });
    flush(); // intento inicial
  }

  bool _online(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);

  Future<bool> hayConexion() async {
    try {
      final r = await Connectivity().checkConnectivity();
      final online = _online(r);
      log.d('offline', 'hayConexion',
          data: {'online': online, 'tipos': r.map((x) => x.name).toList()});
      return online;
    } catch (e) {
      log.w('offline', 'hayConexion falló; se asume que hay red', error: e);
      return true; // ante la duda, intentar (el upload real dirá si hay o no)
    }
  }

  // ── Persistencia de la cola ──────────────────────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueue);
    if (raw != null) {
      try {
        _ops = (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {
        _ops = [];
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQueue, jsonEncode(_ops));
    notifyListeners();
  }

  // Copia una foto a la carpeta persistente (sobrevive reinicios) y devuelve la ruta.
  Future<String?> _persistPhoto(String localPath) async {
    if (_photosDir == null) return localPath;
    try {
      final ext = localPath.contains('.') ? localPath.split('.').last : 'jpg';
      final dest = '$_photosDir/${_uuid.v4()}.$ext';
      await File(localPath).copy(dest);
      return dest;
    } catch (e) {
      debugPrint('OfflineService: no se pudo persistir foto: $e');
      return null;
    }
  }

  // ── Encolar una operación ────────────────────────────────────────────────
  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> record,
    Map<String, String>? photos,
    List<Map<String, dynamic>>? children,
  }) async {
    final Map<String, String> pPhotos = {};
    if (photos != null) {
      for (final e in photos.entries) {
        final p = await _persistPhoto(e.value);
        if (p != null) pPhotos[e.key] = p;
      }
    }
    final List<Map<String, dynamic>> pChildren = [];
    if (children != null) {
      for (final c in children) {
        final cp = <String, String>{};
        final cph = (c['photos'] as Map?)?.cast<String, String>() ?? {};
        for (final e in cph.entries) {
          final p = await _persistPhoto(e.value);
          if (p != null) cp[e.key] = p;
        }
        pChildren.add({'record': c['record'], 'photos': cp});
      }
    }
    final id = _uuid.v4();
    _ops.add({
      'id': id,
      'type': type,
      'record': record,
      'photos': pPhotos,
      'children': pChildren,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'attempts': 0,
    });
    await _save();
    log.i('offline', 'Operación encolada', data: {
      'id': id,
      'tipo': type,
      'fotos': pPhotos.length,
      'hijos': pChildren.length,
      'pendientes': _ops.length,
      if (record['reserva_id'] != null) 'reserva_id': record['reserva_id'],
      if (record['tipo'] != null) 'registro_tipo': record['tipo'],
    });
    flush(); // por si ya hay conexión
  }

  // ── Sincronizar la cola ──────────────────────────────────────────────────
  Future<void> flush() async {
    if (_flushing || _ops.isEmpty) return;
    if (!await hayConexion()) {
      log.w('offline', 'flush omitido: sin red', data: {'pendientes': _ops.length});
      return;
    }
    _flushing = true;
    notifyListeners();
    log.i('offline', 'flush iniciado', data: {'pendientes': _ops.length});
    try {
      final pendientes = List<Map<String, dynamic>>.from(_ops);
      for (final op in pendientes) {
        final sw = Stopwatch()..start();
        try {
          await _procesar(op);
          _borrarFotos(op);
          _ops.removeWhere((o) => o['id'] == op['id']);
          await _save();
          log.i('offline', 'Operación subida', data: {
            'id': op['id'],
            'tipo': op['type'],
            'intentos_previos': op['attempts'],
            'ms': sw.elapsedMilliseconds,
          });
        } catch (e, st) {
          op['attempts'] = ((op['attempts'] ?? 0) as int) + 1;
          op['lastError'] = e.toString();
          await _save();
          log.e('offline', 'Operación falló (queda pendiente)',
              data: {
                'id': op['id'],
                'tipo': op['type'],
                'intentos': op['attempts'],
                'ms': sw.elapsedMilliseconds,
              },
              error: e,
              stack: st);
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  void _borrarFotos(Map<String, dynamic> op) {
    void del(Map ph) {
      for (final p in ph.values) {
        try {
          File(p.toString()).delete();
        } catch (_) {}
      }
    }
    del((op['photos'] as Map?) ?? {});
    for (final c in (op['children'] as List? ?? [])) {
      del((c['photos'] as Map?) ?? {});
    }
  }

  // ── Handlers por tipo ────────────────────────────────────────────────────
  Future<void> _procesar(Map<String, dynamic> op) async {
    switch (op['type']) {
      case 'registro_vehiculo':
        await _subirRegistro(op);
        break;
      case 'factura':
        await _subirFactura(op);
        break;
      case 'liquidacion':
        await _subirLiquidacion(op);
        break;
      default:
        throw 'Tipo desconocido: ${op['type']}';
    }
  }

  Future<String> _subirRegistroFoto(String localPath) async {
    final name = 'register_offline_${_uuid.v4()}.jpg';
    await _sb.storage
        .from('fotos_registro_vehiculos')
        .upload('registros/$name', File(localPath))
        .timeout(const Duration(seconds: 40));
    return name;
  }

  Future<String> _subirComprobante(String localPath) async {
    final name = 'offline_${_uuid.v4()}.jpg';
    await _sb.storage
        .from('facturas_viaticos')
        .upload(name, File(localPath), fileOptions: const FileOptions(upsert: true))
        .timeout(const Duration(seconds: 40));
    return name;
  }

  Future<void> _subirRegistro(Map<String, dynamic> op) async {
    final record = Map<String, dynamic>.from(op['record']);

    // Idempotencia: si ya existe un registro para esta reserva+tipo (no rechazado),
    // no duplicar. Cubre el caso de que un intento en vivo ya se hubiera insertado.
    try {
      final existing = await _sb
          .schema('flotilla')
          .from('registros_vehiculos')
          .select('id')
          .eq('reserva_id', record['reserva_id'])
          .eq('tipo', record['tipo'])
          .neq('estado', 'Rechazado')
          .limit(1)
          .timeout(const Duration(seconds: 20));
      if (existing.isNotEmpty) return; // ya existe → no duplicar
    } catch (_) {
      // Si la verificación falla (red), seguimos e intentamos insertar igual.
    }

    final photos = (op['photos'] as Map?)?.cast<String, String>() ?? {};
    for (final e in photos.entries) {
      final name = await _subirRegistroFoto(e.value); // e.key = 'frente','lateral_der'...
      record['foto_${e.key}'] = name;
    }
    await _sb
        .schema('flotilla')
        .from('registros_vehiculos')
        .insert(record)
        .timeout(const Duration(seconds: 40));
  }

  Future<void> _subirFactura(Map<String, dynamic> op) async {
    final record = Map<String, dynamic>.from(op['record']);
    final photos = (op['photos'] as Map?)?.cast<String, String>() ?? {};
    if (photos['documento'] != null) {
      record['documento'] = await _subirComprobante(photos['documento']!);
    }
    await _sb
        .schema('viaticos')
        .from('facturas')
        .insert(record)
        .timeout(const Duration(seconds: 40));
  }

  Future<void> _subirLiquidacion(Map<String, dynamic> op) async {
    final record = Map<String, dynamic>.from(op['record']);
    // Crear liquidación vía endpoint (dispara notificaciones, igual que online)
    final resp = await http
        .post(Uri.parse('$_baseUrl/create_liquidacion.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(record))
        .timeout(const Duration(seconds: 45));
    final body = jsonDecode(resp.body);
    if (body['success'] != true) {
      throw (body['error'] ?? 'Error al crear liquidación').toString();
    }
    final liqId = body['data']?['id']?.toString();
    if (liqId == null || liqId.isEmpty) throw 'La liquidación no devolvió id';

    for (final c in (op['children'] as List? ?? [])) {
      final fr = Map<String, dynamic>.from(c['record']);
      fr['liquidacion_id'] = liqId;
      final ph = (c['photos'] as Map?)?.cast<String, String>() ?? {};
      if (ph['documento'] != null) {
        fr['documento'] = await _subirComprobante(ph['documento']!);
      }
      await _sb.schema('viaticos').from('facturas').insert(fr);
    }
  }
}
