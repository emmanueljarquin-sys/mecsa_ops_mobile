// =============================================================================
// comprobantes_service.dart — Comprobantes de facturas (imágenes) con caché
// -----------------------------------------------------------------------------
// Resuelve el archivo de un comprobante para verlo en la app o meterlo en un
// PDF:
//
//   - Ruta LOCAL absoluta (factura agregada sin conexión, aún no subida):
//     se usa directamente.
//   - Nombre en el bucket `facturas_viaticos`: se busca en la caché local
//     (<documentos de la app>/comprobantes/). Si no está y hay red, se
//     descarga y se guarda; así la próxima vez (o sin conexión) ya está.
//
// Nunca lanza: devuelve null si no se pudo obtener.
// =============================================================================
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';

class ComprobantesService {
  ComprobantesService._();
  static final ComprobantesService instance = ComprobantesService._();

  static const String _bucketUrl =
      'https://awhuzekjpoapamijlvua.supabase.co/storage/v1/object/public/facturas_viaticos';

  String? _dir;

  /// URL pública del comprobante en Storage.
  String urlDe(String path) => '$_bucketUrl/${Uri.encodeComponent(path)}';

  bool esPdf(String path) => path.toLowerCase().endsWith('.pdf');

  bool _esRutaLocal(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

  Future<String> _carpeta() async {
    if (_dir != null) return _dir!;
    final d = await getApplicationDocumentsDirectory();
    _dir = '${d.path}/comprobantes';
    await Directory(_dir!).create(recursive: true);
    return _dir!;
  }

  String _nombreCache(String path) =>
      path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// ¿Ya está disponible sin red?
  Future<bool> estaEnCache(String path) async {
    if (_esRutaLocal(path)) return File(path).existsSync();
    final f = File('${await _carpeta()}/${_nombreCache(path)}');
    return f.existsSync();
  }

  /// Archivo del comprobante (local, en caché o descargado). Null si no hay.
  Future<File?> obtener(String path, {bool descargar = true}) async {
    try {
      if (_esRutaLocal(path)) {
        final f = File(path);
        return f.existsSync() ? f : null;
      }
      final f = File('${await _carpeta()}/${_nombreCache(path)}');
      if (f.existsSync() && f.lengthSync() > 0) return f;
      if (!descargar) return null;
      final r = await http
          .get(Uri.parse(urlDe(path)))
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        log.w('comprobantes', 'Descarga falló',
            data: {'path': path, 'status': r.statusCode});
        return null;
      }
      await f.writeAsBytes(r.bodyBytes, flush: true);
      return f;
    } catch (e) {
      log.w('comprobantes', 'No se pudo obtener el comprobante',
          data: {'path': path}, error: e);
      return null;
    }
  }

  Future<Uint8List?> bytes(String path, {bool descargar = true}) async {
    final f = await obtener(path, descargar: descargar);
    if (f == null) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Descarga (si hace falta) todos los comprobantes de una lista de rutas.
  /// Se usa al abrir el detalle con red para dejarlos listos sin conexión.
  Future<void> precargar(Iterable<String> paths) async {
    for (final p in paths) {
      if (p.isEmpty || esPdf(p)) continue;
      await obtener(p);
    }
  }
}
