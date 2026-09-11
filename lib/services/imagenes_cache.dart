// =============================================================================
// imagenes_cache.dart — Caché local de imágenes remotas (fotos de vehículos,
// visitas, auditorías, comprobantes de pago…)
// -----------------------------------------------------------------------------
// Toda imagen que la app muestra desde una URL pasa por aquí:
//   - Si la ruta es un archivo local (foto tomada sin conexión) se usa tal cual.
//   - Si ya está en <documentos de la app>/imagenes/ se devuelve el archivo.
//   - Si no está y hay red, se descarga y se guarda para la próxima vez.
// Así las fotos ya vistas (o precargadas al sincronizar) se ven sin conexión.
// Nunca lanza: devuelve null si no se pudo obtener.
// =============================================================================
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_logger.dart';

class ImagenesCache {
  ImagenesCache._();
  static final ImagenesCache instance = ImagenesCache._();

  String? _dir;
  final Set<String> _descargando = {};

  bool esRutaLocal(String p) =>
      p.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(p);

  /// Normaliza lo que guardan las tablas: URL completa, o nombre de archivo
  /// dentro de un bucket (p.ej. fotos de vehículos en `flotilla`).
  String urlDe(String raw, {String? bucket}) {
    final s = raw.trim();
    if (s.isEmpty || s.startsWith('http') || esRutaLocal(s)) return s;
    if (bucket == null) return s;
    return Supabase.instance.client.storage.from(bucket).getPublicUrl(s);
  }

  Future<String> _carpeta() async {
    if (_dir != null) return _dir!;
    final d = await getApplicationDocumentsDirectory();
    _dir = '${d.path}/imagenes';
    await Directory(_dir!).create(recursive: true);
    return _dir!;
  }

  String _nombre(String url) {
    // Nombre estable por URL: hash + cola legible (extensión incluida).
    final cola = url.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final corta = cola.length > 60 ? cola.substring(cola.length - 60) : cola;
    return '${url.hashCode.toUnsigned(32).toRadixString(16)}_$corta';
  }

  Future<File?> enCache(String url) async {
    if (esRutaLocal(url)) {
      final f = File(url);
      return f.existsSync() ? f : null;
    }
    final f = File('${await _carpeta()}/${_nombre(url)}');
    return (f.existsSync() && f.lengthSync() > 0) ? f : null;
  }

  /// Archivo de la imagen: local, en caché o descargada. Null si no hay.
  Future<File?> obtener(String url, {bool descargar = true}) async {
    if (url.trim().isEmpty) return null;
    try {
      final hit = await enCache(url);
      if (hit != null) return hit;
      if (!descargar || esRutaLocal(url) || !url.startsWith('http')) return null;
      if (_descargando.contains(url)) {
        // Otra descarga en curso: esperar un poco y reintentar la caché.
        await Future.delayed(const Duration(milliseconds: 400));
        return enCache(url);
      }
      _descargando.add(url);
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
        final f = File('${await _carpeta()}/${_nombre(url)}');
        await f.writeAsBytes(r.bodyBytes, flush: true);
        return f;
      } finally {
        _descargando.remove(url);
      }
    } catch (e) {
      log.d('imagenes', 'No se pudo obtener', data: {'url': url, 'error': e.toString()});
      return null;
    }
  }

  Future<Uint8List?> bytes(String url) async {
    final f = await obtener(url);
    if (f == null) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Descarga en segundo plano (sin bloquear) las que falten. Se llama al
  /// sincronizar para dejar las fotos listas sin conexión.
  Future<int> precargar(Iterable<String> urls) async {
    int ok = 0;
    for (final u in urls.toSet()) {
      if (u.trim().isEmpty || !u.startsWith('http')) continue;
      if (await enCache(u) != null) continue;
      if (await obtener(u) != null) ok++;
    }
    if (ok > 0) log.i('imagenes', 'Fotos precargadas', data: {'nuevas': ok});
    return ok;
  }

  /// Borra la caché de imágenes (no toca fotos pendientes de subir).
  Future<void> limpiar() async {
    try {
      final d = Directory(await _carpeta());
      if (await d.exists()) await d.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}
