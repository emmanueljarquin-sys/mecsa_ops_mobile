// =============================================================================
// cached_image.dart — Imagen remota que se ve también sin conexión
// -----------------------------------------------------------------------------
// Sustituye a Image.network. Resuelve la imagen con ImagenesCache: primero
// caché local (o archivo local si es una foto tomada sin conexión), si no
// descarga y guarda. Mientras carga muestra un placeholder gris; si no se
// pudo obtener (sin red y no estaba en caché) muestra un icono.
//
//   CachedImage(url, width: 120, height: 120, fit: BoxFit.cover,
//               fallbackIcon: Icons.directions_car)
// =============================================================================
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/imagenes_cache.dart';

class CachedImage extends StatefulWidget {
  final String? url;
  /// Bucket de Storage cuando `url` es solo un nombre de archivo.
  final String? bucket;
  final double? width;
  final double? height;
  final BoxFit fit;
  final IconData fallbackIcon;
  final double fallbackSize;
  final Color? backgroundColor;

  const CachedImage(
    this.url, {
    super.key,
    this.bucket,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.image_not_supported_outlined,
    this.fallbackSize = 32,
    this.backgroundColor,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  Future<File?>? _future;
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant CachedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.bucket != widget.bucket) _prepare();
  }

  void _prepare() {
    final raw = widget.url?.trim() ?? '';
    _resolved = raw.isEmpty ? null : ImagenesCache.instance.urlDe(raw, bucket: widget.bucket);
    _future = _resolved == null ? null : ImagenesCache.instance.obtener(_resolved!);
  }

  Widget _box(Widget child) => Container(
        width: widget.width,
        height: widget.height,
        color: widget.backgroundColor ?? Colors.grey[200],
        alignment: Alignment.center,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return _box(Icon(widget.fallbackIcon, size: widget.fallbackSize, color: Colors.grey));
    }
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _box(const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }
        final f = snap.data;
        if (f == null) {
          return _box(Tooltip(
            message: 'Foto no disponible sin conexión',
            child: Icon(widget.fallbackIcon, size: widget.fallbackSize, color: Colors.grey),
          ));
        }
        return Image.file(
          f,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) =>
              _box(Icon(widget.fallbackIcon, size: widget.fallbackSize, color: Colors.grey)),
        );
      },
    );
  }
}
