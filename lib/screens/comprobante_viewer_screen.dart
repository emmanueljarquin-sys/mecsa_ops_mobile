// =============================================================================
// comprobante_viewer_screen.dart — Visor de comprobante dentro de la app
// -----------------------------------------------------------------------------
// Muestra la imagen del comprobante a pantalla completa con zoom. Usa
// ComprobantesService: si ya está en caché (o es una foto local pendiente de
// subir) se ve sin conexión. Los PDF se abren con la app externa.
// =============================================================================
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/comprobantes_service.dart';

class ComprobanteViewerScreen extends StatefulWidget {
  final String path;
  final String titulo;
  const ComprobanteViewerScreen({super.key, required this.path, this.titulo = 'Comprobante'});

  /// Abre el visor (o la app externa si es PDF).
  static Future<void> abrir(BuildContext context, String path, {String? titulo}) async {
    final svc = ComprobantesService.instance;
    if (svc.esPdf(path)) {
      final f = await svc.obtener(path);
      final uri = f != null ? Uri.file(f.path) : Uri.parse(svc.urlDe(path));
      try {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw 'sin app';
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo abrir el PDF. Instala un visor de PDF o revisa tu conexión.'),
            backgroundColor: Colors.red,
          ));
        }
      }
      return;
    }
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComprobanteViewerScreen(path: path, titulo: titulo ?? 'Comprobante'),
      ),
    );
  }

  @override
  State<ComprobanteViewerScreen> createState() => _ComprobanteViewerScreenState();
}

class _ComprobanteViewerScreenState extends State<ComprobanteViewerScreen> {
  File? _file;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final f = await ComprobantesService.instance.obtener(widget.path);
    if (!mounted) return;
    setState(() {
      _file = f;
      _cargando = false;
      _error = f == null
          ? 'No se pudo cargar el comprobante. Sin conexión solo se ven los que ya se abrieron antes.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.titulo),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _cargar,
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      _file!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text(
                        'El archivo no es una imagen válida.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
    );
  }
}
