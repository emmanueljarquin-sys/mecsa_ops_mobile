import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Registro de actividad EN EL TELÉFONO. Escribe a un archivo persistente y
/// rotativo para que, cuando un colaborador reporte una falla, podamos ver
/// exactamente qué hizo y qué falló (abrir app, cargar reservas/vehículos,
/// guardar salida/entrada, red, sesión).
///
/// - Escrituras serializadas (cola) para que llamadas concurrentes no se pisen.
/// - Rotación: al pasar ~512 KB, el actual pasa a `.1` (se conserva 1 histórico
///   ~1 MB total). Nunca crece sin control.
/// - `read()` devuelve histórico + actual; `exportForShare()` arma un archivo
///   temporal para compartir por WhatsApp/correo.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _maxBytes = 512 * 1024; // rota a ~512 KB
  static const String _fileName = 'mecsaops_log.txt';

  File? _file;
  bool _ready = false;
  Future<void> _queue = Future.value(); // serializa las escrituras

  Future<void> _ensure() async {
    if (_ready) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/$_fileName');
      _ready = true;
    } catch (_) {
      // Si no hay carpeta, el logger queda inerte pero nunca revienta la app.
    }
  }

  /// Registra una línea. Fire-and-forget: los llamadores NO necesitan await.
  Future<void> log(String tag, String msg, {Object? error}) {
    _queue = _queue.then((_) => _write(tag, msg, error));
    return _queue;
  }

  // Atajos por nivel.
  Future<void> i(String tag, String msg) => log(tag, msg);
  Future<void> w(String tag, String msg) => log('WARN/$tag', msg);
  Future<void> e(String tag, String msg, [Object? error]) =>
      log('ERROR/$tag', msg, error: error);

  Future<void> _write(String tag, String msg, Object? error) async {
    await _ensure();
    final f = _file;
    if (f == null) return;
    final ts = DateTime.now().toIso8601String();
    final line =
        '$ts [$tag] $msg${error != null ? ' | ${_short(error)}' : ''}\n';
    try {
      if (await f.exists() && await f.length() > _maxBytes) {
        final old = File('${f.path}.1');
        if (await old.exists()) await old.delete();
        await f.rename(old.path);
        _file = File(f.path); // recrea el actual en el próximo append
      }
      await _file!.writeAsString(line, mode: FileMode.append, flush: false);
    } catch (_) {}
    if (kDebugMode) debugPrint(line.trim());
  }

  static String _short(Object error) {
    var s = error.toString().replaceAll('\n', ' ');
    if (s.length > 300) s = '${s.substring(0, 300)}…';
    return 'ERROR: $s';
  }

  /// Contenido completo (histórico `.1` + actual), más viejo primero.
  Future<String> read() async {
    await _ensure();
    final buf = StringBuffer();
    try {
      final old = File('${_file!.path}.1');
      if (await old.exists()) buf.write(await old.readAsString());
      if (await _file!.exists()) buf.write(await _file!.readAsString());
    } catch (_) {}
    final s = buf.toString();
    return s.isEmpty ? 'Sin registros todavía.' : s;
  }

  /// Arma un archivo temporal con todo el log para compartir. Devuelve la ruta.
  Future<String?> exportForShare({String? encabezado}) async {
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .substring(0, 15);
      final out = File('${dir.path}/mecsaops_log_$stamp.txt');
      final head = encabezado != null ? '$encabezado\n\n' : '';
      await out.writeAsString(head + await read());
      return out.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _ensure();
    try {
      if (await _file!.exists()) await _file!.writeAsString('');
      final old = File('${_file!.path}.1');
      if (await old.exists()) await old.delete();
    } catch (_) {}
  }
}
