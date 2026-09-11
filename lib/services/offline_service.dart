// =============================================================================
// offline_service.dart — Cola de sincronización offline (SQLite)
// -----------------------------------------------------------------------------
// Guarda operaciones (registros de salida/entrada, liquidaciones, facturas,
// visitas) y sus fotos en el teléfono cuando no hay conexión, y las sube
// automáticamente cuando vuelve el internet (o al abrir la app).
//
// La cola vive en la tabla `offline_queue` de SQLite (ver local_db.dart). Las
// versiones anteriores la guardaban en SharedPreferences; al iniciar se migra
// lo que hubiera ahí y se borra la clave vieja.
//
// CONSERVADOR: una operación NUNCA se borra de la cola local hasta que el
// servidor confirma que subió. En el peor caso queda "pendiente" (visible),
// nunca se pierde.
//
// Ids locales: una visita creada sin conexión recibe un id `local-<uuid>`.
// Las operaciones posteriores sobre esa visita (waypoints, finalizar) guardan
// ese id local; al sincronizar, `id_map` lo traduce al id real del servidor.
// Como la cola se procesa en orden de creación, la visita siempre se sube
// antes que sus operaciones hijas.
//
// Reintentos automáticos: se sincroniza al cambiar la red, al recuperar
// internet real (ConnectivityService) y cada [retryInterval] mientras haya
// pendientes.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'app_logger.dart';
import 'connectivity_service.dart';
import 'liquidaciones_local.dart';
import 'local_db.dart';

/// Prefijo de los ids generados en el teléfono para registros creados offline.
const String kLocalIdPrefix = 'local-';

bool esIdLocal(Object? id) => id != null && id.toString().startsWith(kLocalIdPrefix);

class OfflineService extends ChangeNotifier {
  OfflineService._();
  static final OfflineService instance = OfflineService._();

  static const String _kQueueLegacy = 'offline_queue_v1';
  static const String _baseUrl = 'https://grupomecsa.net/ops/api';
  static const Duration retryInterval = Duration(seconds: 45);

  final SupabaseClient _sb = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  List<Map<String, dynamic>> _ops = [];
  bool _initialized = false;
  bool _flushing = false;
  String? _photosDir;
  Timer? _retryTimer;
  bool _wasOnline = true;

  /// Se invoca (fuera del ciclo de flush) cada vez que una operación se subió
  /// con éxito. AppProvider lo usa para refrescar la lista correspondiente.
  void Function(String type, Map<String, dynamic> op)? onOperacionSubida;

  int get pendingCount => _ops.length;
  bool get isFlushing => _flushing;

  /// Copia de solo lectura de la cola (para mostrar pendientes en la UI).
  List<Map<String, dynamic>> get pendientes => List.unmodifiable(_ops);

  bool tienePendientes(String type) => _ops.any((o) => o['type'] == type);

  String nuevoIdLocal() => '$kLocalIdPrefix${_uuid.v4()}';

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
    await _migrarDesdePrefs();
    await _load();
    log.i('offline', 'Cola offline cargada', data: {'pendientes': _ops.length});

    // 1) Cambio de interfaz de red (Wi-Fi/datos aparece).
    Connectivity().onConnectivityChanged.listen((result) {
      final online = _online(result);
      log.i('offline', online ? 'Conectividad: red disponible' : 'Conectividad: sin red',
          data: {'tipos': result.map((r) => r.name).toList()});
      if (online) flush();
    });
    // 2) Internet REAL recuperado (sondeo del backend): dispara sincronización.
    _wasOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.addListener(_onConnectivityChanged);
    // 3) Reintento periódico mientras haya pendientes.
    _retryTimer = Timer.periodic(retryInterval, (_) {
      if (_ops.isNotEmpty && !_flushing) flush();
    });
    flush(); // intento inicial
  }

  void _onConnectivityChanged() {
    final online = ConnectivityService.instance.isOnline;
    if (online && !_wasOnline) {
      log.i('offline', 'Internet recuperado: sincronizando', data: {'pendientes': _ops.length});
      flush();
    }
    _wasOnline = online;
  }

  bool _online(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);

  /// Internet REAL (no solo "hay una red"): delega en ConnectivityService,
  /// que sondea el backend con timeout corto. Así, en Wi-Fi sin salida se
  /// encola de inmediato en vez de agotar los timeouts de subida.
  Future<bool> hayConexion() async {
    try {
      final online = await ConnectivityService.instance.checkInternet();
      log.d('offline', 'hayConexion', data: {'online': online});
      return online;
    } catch (e) {
      log.w('offline', 'hayConexion falló; se asume que hay red', error: e);
      return true; // ante la duda, intentar (el upload real dirá si hay o no)
    }
  }

  // ── Persistencia de la cola (SQLite) ─────────────────────────────────────
  Future<void> _migrarDesdePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kQueueLegacy);
      if (raw == null) return;
      final viejas = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final db = await LocalDb.instance.db;
      for (final op in viejas) {
        await db.insert('offline_queue', _toRow(op),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await prefs.remove(_kQueueLegacy);
      log.i('offline', 'Cola migrada de SharedPreferences a SQLite',
          data: {'operaciones': viejas.length});
    } catch (e, st) {
      log.w('offline', 'No se pudo migrar la cola vieja', error: e);
      debugPrint('$st');
    }
  }

  Map<String, dynamic> _toRow(Map<String, dynamic> op) => {
        'id': op['id'],
        'type': op['type'],
        'payload': jsonEncode(op),
        'created_ms': DateTime.tryParse(op['createdAt']?.toString() ?? '')
                ?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        'attempts': op['attempts'] ?? 0,
        'last_error': op['lastError'],
        'usuario': op['usuario'],
        'estado': op['estado'] ?? 'pendiente',
        'synced_ms': op['syncedMs'],
        'remote_id': op['remoteId'],
      };

  Map<String, dynamic> _fromRow(Map<String, Object?> r) {
    final op = Map<String, dynamic>.from(jsonDecode(r['payload'] as String));
    op['attempts'] = r['attempts'];
    op['lastError'] = r['last_error'];
    op['estado'] = r['estado'];
    op['syncedMs'] = r['synced_ms'];
    op['remoteId'] = r['remote_id'];
    return op;
  }

  /// Carga SOLO las pendientes (las subidas quedan como historial en la tabla).
  Future<void> _load() async {
    try {
      final db = await LocalDb.instance.db;
      // Purgar historial viejo (subidas hace más de 30 días).
      final corte = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      await db.delete('offline_queue',
          where: "estado = 'subido' AND synced_ms < ?", whereArgs: [corte]);
      final rows = await db.query('offline_queue',
          where: "estado = 'pendiente'", orderBy: 'created_ms ASC');
      _ops = rows.map(_fromRow).toList();
    } catch (e, st) {
      log.e('offline', 'No se pudo leer la cola', error: e, stack: st);
      _ops = [];
    }
    notifyListeners();
  }

  /// Marca la operación como subida (no se borra: queda como historial con
  /// fecha de subida e id remoto) y la saca de la lista de pendientes.
  Future<void> _marcarSubida(Map<String, dynamic> op) async {
    op['estado'] = 'subido';
    op['syncedMs'] = DateTime.now().millisecondsSinceEpoch;
    op['lastError'] = null;
    try {
      final db = await LocalDb.instance.db;
      await db.insert('offline_queue', _toRow(op),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      log.e('offline', 'No se pudo marcar como subida', error: e, stack: st);
    }
    _ops.removeWhere((o) => o['id'] == op['id']);
    notifyListeners();
  }

  /// Historial de operaciones ya subidas (más recientes primero).
  Future<List<Map<String, dynamic>>> historial({int limit = 50}) async {
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.query('offline_queue',
          where: "estado = 'subido'", orderBy: 'synced_ms DESC', limit: limit);
      return rows.map(_fromRow).toList();
    } catch (_) {
      return [];
    }
  }

  /// Pendientes cuyo `record[campo] == valor` (p.ej. registros de una reserva).
  List<Map<String, dynamic>> pendientesDonde(String campo, Object? valor) => _ops
      .where((o) => (o['record'] as Map?)?[campo]?.toString() == valor?.toString())
      .toList();

  Future<void> _upsert(Map<String, dynamic> op) async {
    try {
      final db = await LocalDb.instance.db;
      await db.insert('offline_queue', _toRow(op),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      log.e('offline', 'No se pudo guardar la operación', error: e, stack: st);
    }
    notifyListeners();
  }

  // ── Mapa de ids locales → servidor ───────────────────────────────────────
  Future<void> _mapearId(String localId, String remoteId) async {
    final db = await LocalDb.instance.db;
    await db.insert(
      'id_map',
      {
        'local_id': localId,
        'remote_id': remoteId,
        'created_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Devuelve el id del servidor para un id local ya sincronizado, o el
  /// mismo id si no es local. `null` si es local y aún no se subió.
  Future<String?> resolverId(Object? id) async {
    if (id == null) return null;
    final s = id.toString();
    if (!esIdLocal(s)) return s;
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.query('id_map',
          columns: ['remote_id'], where: 'local_id = ?', whereArgs: [s], limit: 1);
      return rows.isEmpty ? null : rows.first['remote_id'] as String;
    } catch (_) {
      return null;
    }
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
  /// Devuelve el id de la operación encolada.
  Future<String> enqueue({
    required String type,
    required Map<String, dynamic> record,
    Map<String, String>? photos,
    List<Map<String, dynamic>>? children,
    String? localId,
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
    final op = <String, dynamic>{
      'id': id,
      'type': type,
      'record': record,
      'photos': pPhotos,
      'children': pChildren,
      if (localId != null) 'localId': localId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'attempts': 0,
      'usuario': _sb.auth.currentUser?.email,
    };
    _ops.add(op);
    await _upsert(op);
    log.i('offline', 'Operación encolada', data: {
      'id': id,
      'tipo': type,
      'fotos': pPhotos.length,
      'hijos': pChildren.length,
      'pendientes': _ops.length,
      if (localId != null) 'localId': localId,
      if (record['reserva_id'] != null) 'reserva_id': record['reserva_id'],
      if (record['tipo'] != null) 'registro_tipo': record['tipo'],
    });
    flush(); // por si ya hay conexión
    return id;
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
    final subidas = <Map<String, dynamic>>[];
    try {
      final pendientes = List<Map<String, dynamic>>.from(_ops);
      for (final op in pendientes) {
        final sw = Stopwatch()..start();
        try {
          await _procesar(op);
          _borrarFotos(op);
          await _marcarSubida(op);
          subidas.add(op);
          log.i('offline', 'Operación subida', data: {
            'id': op['id'],
            'tipo': op['type'],
            'intentos_previos': op['attempts'],
            'ms': sw.elapsedMilliseconds,
          });
        } catch (e, st) {
          op['attempts'] = ((op['attempts'] ?? 0) as int) + 1;
          op['lastError'] = e.toString();
          await _upsert(op);
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
    for (final op in subidas) {
      try {
        onOperacionSubida?.call(op['type'] as String, op);
      } catch (e) {
        log.w('offline', 'onOperacionSubida falló', error: e);
      }
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
      case 'visita_crear':
        await _subirVisitaCrear(op);
        break;
      case 'visita_inicio':
        await _subirVisitaInicio(op);
        break;
      case 'visita_waypoints':
        await _subirVisitaWaypoints(op);
        break;
      case 'visita_fin':
        await _subirVisitaFin(op);
        break;
      case 'auditoria':
        await _subirAuditoria(op);
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

  /// Sube una foto de visita al bucket `visitas_fotos` y devuelve la URL pública
  /// (mismo formato que AppProvider.uploadVisitaFoto).
  Future<String> _subirFotoVisita(String localPath) async {
    final path = 'visitas/visita_offline_${_uuid.v4()}.jpg';
    await _sb.storage
        .from('visitas_fotos')
        .upload(path, File(localPath),
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true))
        .timeout(const Duration(seconds: 40));
    return _sb.storage.from('visitas_fotos').getPublicUrl(path);
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
    // La liquidación pudo haberse creado offline: traducir su id.
    final liqId = await resolverId(record['liquidacion_id']);
    if (liqId == null) throw 'La liquidación de esta factura aún no se ha subido';
    record['liquidacion_id'] = liqId;
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

    op['remoteId'] = liqId;
    final localId = op['localId']?.toString();
    if (localId != null) await _mapearId(localId, liqId);

    for (final c in (op['children'] as List? ?? [])) {
      final fr = Map<String, dynamic>.from(c['record']);
      fr['liquidacion_id'] = liqId;
      final ph = (c['photos'] as Map?)?.cast<String, String>() ?? {};
      if (ph['documento'] != null) {
        fr['documento'] = await _subirComprobante(ph['documento']!);
      }
      await _sb.schema('viaticos').from('facturas').insert(fr);
    }

    // Ya está en el servidor: quitar la copia local "pendiente".
    if (localId != null) {
      await LiquidacionesLocal.instance.eliminar(localId);
    }
  }

  // ── Visitas ──────────────────────────────────────────────────────────────
  /// Visita registrada desde el formulario (no la de "en ruta"). Las fotos
  /// van en `photos` con claves foto_0, foto_1...
  Future<void> _subirVisitaCrear(Map<String, dynamic> op) async {
    final record = Map<String, dynamic>.from(op['record']);
    final photos = (op['photos'] as Map?)?.cast<String, String>() ?? {};
    final fotos = List<dynamic>.from(record['fotos'] as List? ?? []);
    final keys = photos.keys.toList()..sort();
    for (final k in keys) {
      fotos.add(await _subirFotoVisita(photos[k]!));
    }
    record['fotos'] = fotos;
    final res = await _sb
        .schema('visitas')
        .from('visitas')
        .insert(record)
        .select('id')
        .single()
        .timeout(const Duration(seconds: 40));
    op['remoteId'] = res['id'].toString();
    final localId = op['localId']?.toString();
    if (localId != null) await _mapearId(localId, res['id'].toString());
  }

  /// Inicio de visita "en ruta" (startVisitaV2 sin conexión).
  Future<void> _subirVisitaInicio(Map<String, dynamic> op) async {
    final record = Map<String, dynamic>.from(op['record']);
    final localId = op['localId']?.toString();

    // Idempotencia: si ya se subió (falló justo después del insert), no duplicar.
    if (localId != null) {
      final ya = await resolverId(localId);
      if (ya != null) return;
    }

    final photos = (op['photos'] as Map?)?.cast<String, String>() ?? {};
    if (photos['odometro_inicio'] != null) {
      record['foto_odometro_inicio'] =
          await _subirFotoVisita(photos['odometro_inicio']!);
    }
    final res = await _sb
        .schema('visitas')
        .from('visitas')
        .insert(record)
        .select('id')
        .single()
        .timeout(const Duration(seconds: 40));
    op['remoteId'] = res['id'].toString();
    if (localId != null) await _mapearId(localId, res['id'].toString());
  }

  Future<void> _subirVisitaWaypoints(Map<String, dynamic> op) async {
    final record = Map<String, dynamic>.from(op['record']);
    final id = await resolverId(record['visita_id']);
    if (id == null) throw 'La visita aún no se ha subido';
    await _sb
        .schema('visitas')
        .from('visitas')
        .update({'waypoints': record['waypoints']})
        .eq('id', id)
        .timeout(const Duration(seconds: 40));
  }

  /// Cierre de visita: usa el endpoint PHP (calcula km y monto con el tarifario).
  Future<void> _subirVisitaFin(Map<String, dynamic> op) async {
    final record = Map<String, dynamic>.from(op['record']);
    final id = await resolverId(record['id']);
    if (id == null) throw 'La visita aún no se ha subido';
    record['id'] = id;

    final photos = (op['photos'] as Map?)?.cast<String, String>() ?? {};
    if (photos['odometro_fin'] != null) {
      record['foto_odometro_url'] = await _subirFotoVisita(photos['odometro_fin']!);
    }
    final resp = await http
        .post(Uri.parse('$_baseUrl/finish_visita.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(record))
        .timeout(const Duration(seconds: 45));
    if (resp.statusCode != 200) {
      throw 'finish_visita respondió ${resp.statusCode}';
    }
    final body = jsonDecode(resp.body);
    if (body['success'] != true) {
      throw (body['error'] ?? 'Error al finalizar visita').toString();
    }
  }

  // ── Auditorías ───────────────────────────────────────────────────────────
  /// Auditoría de vehículo creada sin conexión. `record` trae `cabecera`
  /// (insert de flotilla.auditorias sin fotos), `items` (inserts de
  /// auditoria_items sin auditoria_id) y `detalle_notas`. Las fotos van en
  /// `photos` con claves `general_N`, `item_<slug>_N` y `detalle_N`.
  Future<void> _subirAuditoria(Map<String, dynamic> op) async {
    final record = Map<String, dynamic>.from(op['record']);
    final photos = (op['photos'] as Map?)?.cast<String, String>() ?? {};

    Future<String> subir(String localPath) async {
      final ext = localPath.contains('.') ? localPath.split('.').last : 'jpg';
      final path = 'auditorias/offline_${_uuid.v4()}.$ext';
      await _sb.storage
          .from('fotos_registro_vehiculos')
          .upload(path, File(localPath), fileOptions: const FileOptions(upsert: true))
          .timeout(const Duration(seconds: 40));
      return _sb.storage.from('fotos_registro_vehiculos').getPublicUrl(path);
    }

    final keys = photos.keys.toList()..sort();
    final cabecera = Map<String, dynamic>.from(record['cabecera'] as Map);
    final items = (record['items'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final notas = (record['detalle_notas'] as List? ?? []).map((e) => e?.toString()).toList();

    // Fotos generales
    final generales = <String>[...(cabecera['fotos'] as List? ?? []).map((e) => e.toString())];
    for (final k in keys.where((k) => k.startsWith('general_'))) {
      generales.add(await subir(photos[k]!));
    }
    cabecera['fotos'] = generales;

    // Fotos de detalle con nota
    final detalle = <Map<String, dynamic>>[
      ...(cabecera['fotos_detalle'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    ];
    final detKeys = keys.where((k) => k.startsWith('detalle_')).toList();
    for (int i = 0; i < detKeys.length; i++) {
      final url = await subir(photos[detKeys[i]]!);
      final idx = int.tryParse(detKeys[i].substring('detalle_'.length)) ?? i;
      final nota = idx < notas.length ? notas[idx] : null;
      detalle.add({'url': url, if (nota != null && nota.isNotEmpty) 'nota': nota});
    }
    cabecera['fotos_detalle'] = detalle;

    // Fotos por ítem
    for (final it in items) {
      final slug = it['item_slug'].toString();
      final fotos = <String>[...(it['fotos'] as List? ?? []).map((e) => e.toString())];
      for (final k in keys.where((k) => k.startsWith('item_${slug}_'))) {
        fotos.add(await subir(photos[k]!));
      }
      it['fotos'] = fotos;
    }

    // Idempotencia: si ya subió (falló tras el insert), no duplicar.
    final localId = op['localId']?.toString();
    if (localId != null && await resolverId(localId) != null) return;

    final inserted = await _sb
        .schema('flotilla')
        .from('auditorias')
        .insert(cabecera)
        .select('id')
        .single()
        .timeout(const Duration(seconds: 40));
    final auditoriaId = inserted['id'].toString();
    op['remoteId'] = auditoriaId;
    if (localId != null) await _mapearId(localId, auditoriaId);

    if (items.isNotEmpty) {
      for (final it in items) {
        it['auditoria_id'] = auditoriaId;
      }
      await _sb.schema('flotilla').from('auditoria_items').insert(items).timeout(const Duration(seconds: 40));
    }
    await _sb
        .schema('flotilla')
        .rpc('recompute_auditoria', params: {'p_auditoria_id': auditoriaId})
        .timeout(const Duration(seconds: 30));
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    ConnectivityService.instance.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
