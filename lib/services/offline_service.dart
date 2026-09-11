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
    } catch (e) {
      debugPrint('OfflineService: no se pudo crear carpeta de fotos: $e');
    }
    await _load();
    Connectivity().onConnectivityChanged.listen((result) {
      if (_online(result)) flush();
    });
    flush(); // intento inicial
  }

  bool _online(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);

  Future<bool> hayConexion() async {
    try {
      return _online(await Connectivity().checkConnectivity());
    } catch (_) {
      return true; // ante la duda, intentar (el upload real dirá si hay o no)
    }
  }

  /// ¿Hay internet REAL? No basta con estar conectado a una red: el Wi-Fi de
  /// Mecsa puede estar conectado pero SIN salida a internet, y ahí la app se
  /// colgaba "intentando". Verificamos que de verdad se alcance el backend.
  Future<bool> tieneInternetReal(
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (!await hayConexion()) {
      AppLogger.instance.i('red', 'sin red (connectivity)');
      return false;
    }
    // 1) ¿Llega al backend propio? (es lo que de verdad importa para operar)
    try {
      final r = await http
          .get(Uri.parse(
              'https://awhuzekjpoapamijlvua.supabase.co/auth/v1/health'))
          .timeout(timeout);
      if (r.statusCode >= 200 && r.statusCode < 500) return true;
    } catch (_) {}
    // 2) Segundo intento contra un host neutral (por si el backend está caído).
    try {
      final r = await http
          .get(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(timeout);
      final ok = r.statusCode == 204 || r.statusCode == 200;
      if (!ok) {
        AppLogger.instance.w('red', 'red conectada pero SIN salida a internet');
      }
      return ok;
    } catch (_) {
      AppLogger.instance.w('red', 'red conectada pero SIN salida a internet');
      return false;
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
    _ops.add({
      'id': _uuid.v4(),
      'type': type,
      'record': record,
      'photos': pPhotos,
      'children': pChildren,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'attempts': 0,
    });
    await _save();
    flush(); // por si ya hay conexión
  }

  // ── Sincronizar la cola ──────────────────────────────────────────────────
  Future<void> flush() async {
    if (_flushing || _ops.isEmpty) return;
    if (!await hayConexion()) return;
    _flushing = true;
    notifyListeners();
    try {
      final pendientes = List<Map<String, dynamic>>.from(_ops);
      for (final op in pendientes) {
        try {
          await _procesar(op);
          _borrarFotos(op);
          _ops.removeWhere((o) => o['id'] == op['id']);
          await _save();
          AppLogger.instance
              .i('cola', 'subido ${op['type']} (quedan ${_ops.length})');
        } catch (e) {
          op['attempts'] = ((op['attempts'] ?? 0) as int) + 1;
          op['lastError'] = e.toString();
          await _save();
          AppLogger.instance.w('cola',
              'op ${op['type']} queda pendiente (intentos ${op['attempts']}): $e');
          debugPrint('OfflineService: op ${op['type']} falló (queda pendiente): $e');
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
    try {
      await _sb
          .schema('flotilla')
          .from('registros_vehiculos')
          .insert(record)
          .timeout(const Duration(seconds: 40));
    } on PostgrestException catch (e) {
      // 23505 = choque con el índice único (reserva+tipo ya existe). Es ÉXITO:
      // el registro ya está; sacamos la op de la cola en vez de reintentar en loop.
      if (e.code == '23505') {
        AppLogger.instance.i('cola', 'registro ya existía (23505) → éxito');
        return;
      }
      rethrow;
    }
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
