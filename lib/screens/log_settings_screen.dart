// =============================================================================
// log_settings_screen.dart — Configuración del registro de actividad
// -----------------------------------------------------------------------------
// Permite elegir qué niveles se guardan (debug, info, warning, error), por
// cuántos días se conservan, ver cuánto ocupa y borrar el registro.
// Se llega desde Perfil > Registro de actividad > Configurar.
// =============================================================================
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../services/app_logger.dart';
import '../services/local_db.dart';

class LogSettingsScreen extends StatefulWidget {
  const LogSettingsScreen({super.key});

  @override
  State<LogSettingsScreen> createState() => _LogSettingsScreenState();
}

class _LogSettingsScreenState extends State<LogSettingsScreen> {
  Map<LogLevel, int> _counts = {};
  int _sizeBytes = 0;
  bool _loading = true;

  static const List<int> _retentionOptions = [3, 7, 14, 30, 60];

  @override
  void initState() {
    super.initState();
    AppLogger.instance.addListener(_onLoggerChanged);
    _refresh();
  }

  @override
  void dispose() {
    AppLogger.instance.removeListener(_onLoggerChanged);
    super.dispose();
  }

  void _onLoggerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final counts = await AppLogger.instance.countByLevel();
    final size = await LocalDb.instance.sizeBytes();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _sizeBytes = size;
      _loading = false;
    });
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  IconData _iconFor(LogLevel l) {
    switch (l) {
      case LogLevel.debug:
        return Icons.bug_report_outlined;
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warning:
        return Icons.warning_amber_outlined;
      case LogLevel.error:
        return Icons.error_outline;
    }
  }

  Color _colorFor(LogLevel l) {
    switch (l) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  String _descFor(LogLevel l) {
    switch (l) {
      case LogLevel.debug:
        return 'Detalle técnico paso a paso. Genera muchas entradas; activar solo para diagnosticar un problema.';
      case LogLevel.info:
        return 'Eventos normales: arranque, carga de datos, registros guardados, sincronización.';
      case LogLevel.warning:
        return 'Situaciones anormales que no detienen la app: sin internet, reintentos, datos faltantes.';
      case LogLevel.error:
        return 'Fallas: consultas que no respondieron, errores al guardar, problemas de sesión.';
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar registro'),
        content: const Text(
            'Se eliminarán todas las entradas guardadas en este teléfono. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('BORRAR'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppLogger.instance.clear();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Registro borrado')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final logger = AppLogger.instance;
    final total = _counts.values.fold<int>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurar registro')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'NIVELES A REGISTRAR',
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.of(context).surfaceVariant),
                    ),
                    child: Column(
                      children: [
                        for (final l in LogLevel.values)
                          SwitchListTile(
                            secondary: Icon(_iconFor(l), color: _colorFor(l)),
                            title: Text(l.label),
                            subtitle: Text(
                              '${_descFor(l)}\n${_counts[l] ?? 0} entradas guardadas',
                              style: const TextStyle(fontSize: 12),
                            ),
                            isThreeLine: true,
                            value: logger.isEnabled(l),
                            onChanged: (v) async {
                              await logger.setLevelEnabled(l, v);
                              _refresh();
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'RETENCIÓN',
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.of(context).surfaceVariant),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.history, color: Colors.blue),
                      title: const Text('Conservar entradas por'),
                      subtitle: Text(
                          'Máximo ${AppLogger.maxRows} entradas. Las más viejas se borran solas.'),
                      trailing: DropdownButton<int>(
                        value: _retentionOptions.contains(logger.retentionDays)
                            ? logger.retentionDays
                            : _retentionOptions.first,
                        underline: const SizedBox.shrink(),
                        items: _retentionOptions
                            .map((d) => DropdownMenuItem(
                                value: d, child: Text('$d días')))
                            .toList(),
                        onChanged: (d) async {
                          if (d == null) return;
                          await logger.setRetentionDays(d);
                          _refresh();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'ALMACENAMIENTO',
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.of(context).surfaceVariant),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading:
                              const Icon(Icons.storage_outlined, color: Colors.blue),
                          title: Text('$total entradas'),
                          subtitle: Text(
                              'Base local: ${_fmtBytes(_sizeBytes)} · ${LocalDb.dbName}'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.delete_outline, color: Colors.red),
                          title: const Text('Borrar registro',
                              style: TextStyle(color: Colors.red)),
                          onTap: total == 0 ? null : _confirmClear,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'El registro se guarda solo en este teléfono. No se envía a ningún servidor. '
                    'Para compartirlo con TI, usá "Ver registro" y el botón de compartir.',
                    style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}
