// =============================================================================
// foto_viewer.dart — Visor de fotos a pantalla completa
// -----------------------------------------------------------------------------
// Modal negro con zoom, desliza entre fotos, y botones para descargar a la
// galería (álbum MecsaOPS) y compartir. Las fotos se resuelven con
// ImagenesCache, así que funciona sin conexión para las que ya están en caché
// o son archivos locales.
//
//   FotoViewer.abrir(context, fotos: [url1, url2], inicial: 0,
//                    titulos: ['Foto 1', 'Odómetro inicial']);
// =============================================================================
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../services/imagenes_cache.dart';

class FotoViewer extends StatefulWidget {
  final List<String> fotos;
  final int inicial;
  final List<String>? titulos;

  const FotoViewer({
    super.key,
    required this.fotos,
    this.inicial = 0,
    this.titulos,
  });

  static Future<void> abrir(
    BuildContext context, {
    required List<String> fotos,
    int inicial = 0,
    List<String>? titulos,
  }) {
    final limpias = fotos.where((f) => f.trim().isNotEmpty).toList();
    if (limpias.isEmpty) return Future.value();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => FotoViewer(
          fotos: limpias,
          inicial: inicial.clamp(0, limpias.length - 1),
          titulos: titulos,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<FotoViewer> createState() => _FotoViewerState();
}

class _FotoViewerState extends State<FotoViewer> {
  late final PageController _page = PageController(initialPage: widget.inicial);
  late int _actual = widget.inicial;
  bool _ocupado = false;

  String get _titulo {
    final t = widget.titulos;
    if (t != null && _actual < t.length && t[_actual].isNotEmpty) return t[_actual];
    return 'Foto ${_actual + 1} de ${widget.fotos.length}';
  }

  Future<File?> _archivoActual() =>
      ImagenesCache.instance.obtener(widget.fotos[_actual]);

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  Future<void> _descargar() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final f = await _archivoActual();
      if (f == null) {
        _aviso('La foto no está disponible sin conexión.', error: true);
        return;
      }
      try {
        if (!await Gal.hasAccess()) {
          if (!await Gal.requestAccess()) {
            _aviso('Se necesita permiso para guardar en la galería.', error: true);
            return;
          }
        }
      } catch (_) {}
      await Gal.putImage(f.path, album: 'MecsaOPS');
      _aviso('Foto guardada en la galería (álbum MecsaOPS).');
    } catch (e) {
      _aviso('No se pudo guardar la foto.', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _compartir() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final f = await _archivoActual();
      if (f == null) {
        _aviso('La foto no está disponible sin conexión.', error: true);
        return;
      }
      await Share.shareXFiles([XFile(f.path)], text: _titulo);
    } catch (_) {
      _aviso('No se pudo compartir la foto.', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_titulo, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.share),
            onPressed: _ocupado ? null : _compartir,
          ),
          IconButton(
            tooltip: 'Descargar a la galería',
            icon: _ocupado
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download),
            onPressed: _ocupado ? null : _descargar,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.fotos.length,
        onPageChanged: (i) => setState(() => _actual = i),
        itemBuilder: (context, i) => _Foto(path: widget.fotos[i]),
      ),
      bottomNavigationBar: widget.fotos.length > 1
          ? Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.fotos.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _actual ? Colors.white : Colors.white30,
                      ),
                    ),
                ],
              ),
            )
          : null,
    );
  }
}

class _Foto extends StatelessWidget {
  final String path;
  const _Foto({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: ImagenesCache.instance.obtener(path),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        final f = snap.data;
        if (f == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, color: Colors.white54, size: 64),
                  SizedBox(height: 12),
                  Text(
                    'Foto no disponible sin conexión.\nSe verá cuando la app la haya descargado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(
            child: Image.file(
              f,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text(
                'El archivo no es una imagen válida.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        );
      },
    );
  }
}
