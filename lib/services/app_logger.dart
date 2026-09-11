// =============================================================================
// app_logger.dart — Registro de actividad (log) local de la app
// -----------------------------------------------------------------------------
// Guarda en SQLite (tabla app_log, ver local_db.dart) lo que la app hace y lo
// que falla, para poder diagnosticar reportes de campo sin adivinar.
//
// Uso:
//   AppLogger.instance.i('fetchData', 'Carga completa', data: {'ms': 812});
//   AppLogger.instance.w('offline', 'Sin internet real');
//   AppLogger.instance.e('registro', 'Falló insert', error: e, stack: st);
//   final r = await AppLogger.instance.time('fetchData', 'vehiculos', () => ...);
//
// Niveles habilitados: configurables por el usuario (pantalla de configuración
// en Perfil), persistidos en SharedPreferences. Un nivel deshabilitado no se
// escribe. Por defecto: info, warning y error activos; debug apagado.
//
// Retención: se borran entradas más viejas que `retentionDays` y se limita el
// total a `maxRows` (se poda al iniciar y periódicamente).
//
// Robustez: nunca lanza. Si la base no está lista, las entradas se acumulan en
// memoria y se vuelcan al abrir. Si escribir falla, se descarta en silencio.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';

enum LogLevel {
  debug(0, 'DEBUG', 'Depuración'),
  info(1, 'INFO', 'Información'),
  warning(2, 'WARN', 'Advertencias'),
  error(3, 'ERROR', 'Errores');

  const LogLevel(this.value, this.tag, this.label);
  final int value;
  final String tag;
  final String label;

  static LogLevel fromValue(int v) =>
      LogLevel.values.firstWhere((l) => l.value == v, orElse: () => LogLevel.info);
}

class LogEntry {
  final int id;
  final DateTime ts;
  final LogLevel level;
  final String module;
  final String message;
  final Map<String, dynamic>? data;
  final String? error;
  final String? stack;
  final String? usuario;
  final String? appVersion;

  const LogEntry({
    required this.id,
    required this.ts,
    required this.level,
    required this.module,
    required this.message,
    this.data,
    this.error,
    this.stack,
    this.usuario,
    this.appVersion,
  });

  factory LogEntry.fromRow(Map<String, Object?> r) {
    Map<String, dynamic>? data;
    final rawData = r['data'] as String?;
    if (rawData != null && rawData.isNotEmpty) {
      try {
        data = Map<String, dynamic>.from(jsonDecode(rawData) as Map);
      } catch (_) {
        data = {'raw': rawData};
      }
    }
    return LogEntry(
      id: r['id'] as int,
      ts: DateTime.fromMillisecondsSinceEpoch(r['ts_ms'] as int),
      level: LogLevel.fromValue(r['level'] as int),
      module: r['module'] as String,
      message: r['message'] as String,
      data: data,
      error: r['error'] as String?,
      stack: r['stack'] as String?,
      usuario: r['usuario'] as String?,
      appVersion: r['app_version'] as String?,
    );
  }

  String toText() {
    final b = StringBuffer();
    b.write('${_fmt(ts)} [${level.tag}] $module: $message');
    if (data != null && data!.isNotEmpty) b.write('  ${jsonEncode(data)}');
    if (error != null && error!.isNotEmpty) b.write('\n    error: $error');
    if (stack != null && stack!.isNotEmpty) {
      b.write('\n    ${stack!.split('\n').take(6).join('\n    ')}');
    }
    return b.toString();
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}

class AppLogger extends ChangeNotifier {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const String _kLevels = 'log_levels_enabled_v1';
  static const String _kRetention = 'log_retention_days_v1';
  static const int maxRows = 5000;
  static const int _maxStackChars = 4000;
  static const int _maxErrorChars = 2000;

  Set<LogLevel> _enabled = {LogLevel.info, LogLevel.warning, LogLevel.error};
  int _retentionDays = 14;
  bool _initialized = false;
  String? _usuario;
  String? _appVersion;

  final List<Map<String, Object?>> _pending = [];
  int _writesSincePrune = 0;

  Set<LogLevel> get enabledLevels => Set.unmodifiable(_enabled);
  int get retentionDays => _retentionDays;
  bool get isInitialized => _initialized;
  String? get appVersion => _appVersion;

  bool isEnabled(LogLevel l) => _enabled.contains(l);

  // ── Inicialización y configuración ───────────────────────────────────────
  Future<void> init({String? appVersion}) async {
    if (_initialized) return;
    _appVersion = appVersion ?? _appVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kLevels);
      if (saved != null) {
        _enabled = saved
            .map((n) => LogLevel.values.where((l) => l.name == n))
            .expand((x) => x)
            .toSet();
      }
      _retentionDays = prefs.getInt(_kRetention) ?? _retentionDays;
    } catch (e) {
      debugPrint('AppLogger: no se pudo leer configuración: $e');
    }
    try {
      await LocalDb.instance.db; // abre la base
      _initialized = true;
      await _flushPending();
      unawaited(prune());
    } catch (e) {
      debugPrint('AppLogger: no se pudo abrir la base local: $e');
    }
    notifyListeners();
  }

  void setUser(String? email) => _usuario = email;
  void setAppVersion(String? v) => _appVersion = v;

  Future<void> setLevelEnabled(LogLevel level, bool enabled) async {
    if (enabled) {
      _enabled.add(level);
    } else {
      _enabled.remove(level);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kLevels, _enabled.map((l) => l.name).toList());
    } catch (_) {}
    // Registrar el cambio de configuración (siempre como info si está activo).
    i('log', 'Nivel ${level.tag} ${enabled ? 'activado' : 'desactivado'}');
  }

  Future<void> setRetentionDays(int days) async {
    _retentionDays = days.clamp(1, 90);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kRetention, _retentionDays);
    } catch (_) {}
    i('log', 'Retención cambiada a $_retentionDays días');
    unawaited(prune());
  }

  // ── API de escritura ─────────────────────────────────────────────────────
  void d(String module, String message, {Map<String, dynamic>? data}) =>
      _log(LogLevel.debug, module, message, data: data);

  void i(String module, String message, {Map<String, dynamic>? data}) =>
      _log(LogLevel.info, module, message, data: data);

  void w(String module, String message,
          {Map<String, dynamic>? data, Object? error}) =>
      _log(LogLevel.warning, module, message, data: data, error: error);

  void e(String module, String message,
          {Map<String, dynamic>? data, Object? error, StackTrace? stack}) =>
      _log(LogLevel.error, module, message,
          data: data, error: error, stack: stack);

  /// Ejecuta [action] midiendo su duración. Registra info al terminar (con ms)
  /// y error si lanza (re-lanzando la excepción para no alterar el flujo).
  Future<T> time<T>(
    String module,
    String action,
    Future<T> Function() body, {
    Map<String, dynamic>? data,
    LogLevel okLevel = LogLevel.debug,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final r = await body();
      sw.stop();
      _log(okLevel, module, '$action OK',
          data: {...?data, 'ms': sw.elapsedMilliseconds});
      return r;
    } catch (err, st) {
      sw.stop();
      _log(LogLevel.error, module, '$action FALLÓ',
          data: {...?data, 'ms': sw.elapsedMilliseconds}, error: err, stack: st);
      rethrow;
    }
  }

  void _log(
    LogLevel level,
    String module,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stack,
  }) {
    if (!_enabled.contains(level)) return;
    final now = DateTime.now();
    final row = <String, Object?>{
      'ts_ms': now.millisecondsSinceEpoch,
      'ts': now.toIso8601String(),
      'level': level.value,
      'level_name': level.tag,
      'module': module,
      'message': message,
      'data': data == null ? null : _safeJson(data),
      'error': error == null ? null : _trim(error.toString(), _maxErrorChars),
      'stack': stack == null ? null : _trim(stack.toString(), _maxStackChars),
      'usuario': _usuario,
      'app_version': _appVersion,
    };
    if (kDebugMode) {
      debugPrint('[${level.tag}] $module: $message'
          '${data != null ? ' ${row['data']}' : ''}'
          '${error != null ? ' | $error' : ''}');
    }
    unawaited(_write(row));
  }

  Future<void> _write(Map<String, Object?> row) async {
    if (!_initialized) {
      _pending.add(row);
      if (_pending.length > 500) _pending.removeAt(0);
      return;
    }
    try {
      final db = await LocalDb.instance.db;
      await db.insert('app_log', row);
      if (++_writesSincePrune >= 200) {
        _writesSincePrune = 0;
        unawaited(prune());
      }
    } catch (e) {
      debugPrint('AppLogger: no se pudo escribir: $e');
    }
  }

  Future<void> _flushPending() async {
    if (_pending.isEmpty) return;
    final copy = List<Map<String, Object?>>.from(_pending);
    _pending.clear();
    try {
      final db = await LocalDb.instance.db;
      final batch = db.batch();
      for (final r in copy) {
        batch.insert('app_log', r);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('AppLogger: no se pudo volcar pendientes: $e');
    }
  }

  // ── Mantenimiento ────────────────────────────────────────────────────────
  Future<void> prune() async {
    if (!_initialized) return;
    try {
      final db = await LocalDb.instance.db;
      final cutoff = DateTime.now()
          .subtract(Duration(days: _retentionDays))
          .millisecondsSinceEpoch;
      await db.delete('app_log', where: 'ts_ms < ?', whereArgs: [cutoff]);
      await db.rawDelete('''
        DELETE FROM app_log WHERE id NOT IN (
          SELECT id FROM app_log ORDER BY ts_ms DESC LIMIT ?
        )
      ''', [maxRows]);
    } catch (e) {
      debugPrint('AppLogger.prune: $e');
    }
  }

  Future<void> clear() async {
    try {
      final db = await LocalDb.instance.db;
      await db.delete('app_log');
      notifyListeners();
      i('log', 'Registro borrado por el usuario');
    } catch (e) {
      debugPrint('AppLogger.clear: $e');
    }
  }

  // ── Consulta ─────────────────────────────────────────────────────────────
  Future<List<LogEntry>> query({
    Set<LogLevel>? levels,
    String? module,
    String? search,
    int limit = 300,
    int offset = 0,
  }) async {
    try {
      final db = await LocalDb.instance.db;
      final where = <String>[];
      final args = <Object?>[];
      if (levels != null && levels.isNotEmpty && levels.length < LogLevel.values.length) {
        where.add('level IN (${List.filled(levels.length, '?').join(',')})');
        args.addAll(levels.map((l) => l.value));
      }
      if (module != null && module.isNotEmpty) {
        where.add('module = ?');
        args.add(module);
      }
      if (search != null && search.trim().isNotEmpty) {
        where.add('(message LIKE ? OR data LIKE ? OR error LIKE ?)');
        final s = '%${search.trim()}%';
        args.addAll([s, s, s]);
      }
      final rows = await db.query(
        'app_log',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'ts_ms DESC, id DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map(LogEntry.fromRow).toList();
    } catch (e) {
      debugPrint('AppLogger.query: $e');
      return [];
    }
  }

  Future<int> count() async {
    try {
      final db = await LocalDb.instance.db;
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM app_log');
      return (r.first['c'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<LogLevel, int>> countByLevel() async {
    final out = {for (final l in LogLevel.values) l: 0};
    try {
      final db = await LocalDb.instance.db;
      final rows =
          await db.rawQuery('SELECT level, COUNT(*) AS c FROM app_log GROUP BY level');
      for (final r in rows) {
        out[LogLevel.fromValue(r['level'] as int)] = (r['c'] as int?) ?? 0;
      }
    } catch (_) {}
    return out;
  }

  Future<List<String>> modules() async {
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.rawQuery(
          'SELECT DISTINCT module FROM app_log ORDER BY module ASC');
      return rows.map((r) => r['module'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// Exporta como texto plano (para copiar / compartir).
  Future<String> exportText({
    Set<LogLevel>? levels,
    String? module,
    String? search,
    int limit = 1000,
  }) async {
    final entries =
        await query(levels: levels, module: module, search: search, limit: limit);
    final b = StringBuffer()
      ..writeln('MecsaOPS Mobile - Registro de actividad')
      ..writeln('Versión: ${_appVersion ?? '?'}  Usuario: ${_usuario ?? '?'}')
      ..writeln('Exportado: ${DateTime.now().toIso8601String()}')
      ..writeln('Entradas: ${entries.length}')
      ..writeln('-' * 60);
    // Más antiguo primero para leer en orden cronológico.
    for (final e in entries.reversed) {
      b.writeln(e.toText());
    }
    return b.toString();
  }

  // ── Utilidades ───────────────────────────────────────────────────────────
  static String _safeJson(Map<String, dynamic> m) {
    try {
      return jsonEncode(m, toEncodable: (o) => o.toString());
    } catch (_) {
      return m.toString();
    }
  }

  static String _trim(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...';
}

/// Acceso corto: `log.i('modulo', 'mensaje')`.
final AppLogger log = AppLogger.instance;
