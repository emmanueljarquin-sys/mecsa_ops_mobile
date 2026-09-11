import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_logger.dart';

/// Visor del registro de actividad del teléfono. Sirve para que, cuando un
/// colaborador reporte una falla, pueda COMPARTIR el log con TI y así ver
/// exactamente qué pasó en su teléfono (carga de datos, guardado, red).
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  static const _navy = Color(0xFF013483);
  String _contenido = 'Cargando…';
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final txt = await AppLogger.instance.read();
    if (!mounted) return;
    setState(() {
      _contenido = txt;
      _cargando = false;
    });
  }

  Future<void> _compartir() async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await AppLogger.instance.exportForShare(
      encabezado:
          'Registro de actividad MecsaOPS — generado ${DateTime.now()}',
    );
    if (path == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo preparar el archivo.')),
      );
      return;
    }
    try {
      await Share.shareXFiles([XFile(path)], text: 'Log de MecsaOPS para TI');
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el menú de compartir.')),
      );
    }
  }

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: _contenido));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copiado al portapapeles.')),
    );
  }

  Future<void> _limpiar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar registro'),
        content: const Text(
            '¿Borrar el log del teléfono? Esto no afecta tus datos ni tus registros.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await AppLogger.instance.clear();
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de actividad'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Compartir con TI',
            onPressed: _cargando ? null : _compartir,
            icon: const Icon(Icons.share),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFEFF6FF),
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Si tenés una falla, tocá "Compartir" (arriba) y enviá este registro '
              'a TI por el grupo de WhatsApp. Ayuda a encontrar la causa exacta.',
              style: TextStyle(fontSize: 12.5, color: _navy),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _contenido,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copiar,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _limpiar,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Limpiar'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
