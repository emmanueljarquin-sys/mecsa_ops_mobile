// =============================================================================
// app_log_screen.dart — Visor del registro de actividad
// -----------------------------------------------------------------------------
// Lista las entradas del log local con filtros por nivel, módulo y texto.
// Permite ver el detalle de cada entrada, copiar todo al portapapeles y
// compartirlo como PDF (menú del sistema: WhatsApp, correo, guardar...).
// Se llega desde Perfil > Registro de actividad > Ver registro.
// =============================================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/mensajes_error.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_logger.dart';
import 'log_settings_screen.dart';

enum _ExportFormat { pdf, csv, json }

class AppLogScreen extends StatefulWidget {
  const AppLogScreen({super.key});

  @override
  State<AppLogScreen> createState() => _AppLogScreenState();
}

class _AppLogScreenState extends State<AppLogScreen> {
  static const int _pageSize = 200;

  final Set<LogLevel> _levels = LogLevel.values.toSet();
  String? _module;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<LogEntry> _entries = [];
  List<String> _modules = [];
  bool _loading = true;
  bool _hasMore = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (!append) setState(() => _loading = true);
    final logger = AppLogger.instance;
    final offset = append ? _entries.length : 0;
    final results = await Future.wait([
      logger.query(
        levels: _levels,
        module: _module,
        search: _search.text,
        limit: _pageSize,
        offset: offset,
      ),
      if (!append) logger.modules(),
    ]);
    if (!mounted) return;
    final page = results[0] as List<LogEntry>;
    setState(() {
      _entries = append ? [..._entries, ...page] : page;
      _hasMore = page.length == _pageSize;
      if (!append) _modules = results[1] as List<String>;
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
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

  String _fmtTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  // ── Acciones ─────────────────────────────────────────────────────────────
  Future<void> _copyAll() async {
    final text = await AppLogger.instance.exportText(
      levels: _levels,
      module: _module,
      search: _search.text,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro copiado al portapapeles')),
      );
    }
  }

  String _stamp() =>
      DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');

  Future<void> _share(_ExportFormat fmt) async {
    switch (fmt) {
      case _ExportFormat.pdf:
        return _sharePdf();
      case _ExportFormat.csv:
        return _shareTextFile(
          ext: 'csv',
          mime: 'text/csv',
          build: () => AppLogger.instance.exportCsv(
            levels: _levels, module: _module, search: _search.text),
        );
      case _ExportFormat.json:
        return _shareTextFile(
          ext: 'json',
          mime: 'application/json',
          build: () => AppLogger.instance.exportJson(
            levels: _levels, module: _module, search: _search.text),
        );
    }
  }

  /// Genera el contenido, lo escribe en un archivo temporal y abre el menú
  /// de compartir del sistema (WhatsApp, correo, Drive...).
  Future<void> _shareTextFile({
    required String ext,
    required String mime,
    required Future<String> Function() build,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final content = await build();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mecsaops_log_${_stamp()}.$ext');
      await file.writeAsString(content, flush: true);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        subject: 'Registro de actividad MecsaOPS (${ext.toUpperCase()})',
        text: 'Registro de actividad de MecsaOPS Mobile '
            'v${AppLogger.instance.appVersion ?? '?'}',
      ));
      AppLogger.instance.i('log', 'Registro exportado a ${ext.toUpperCase()}',
          data: {'bytes': content.length, 'resultado': result.status.name});
    } catch (e, st) {
      AppLogger.instance.e('log', 'No se pudo exportar a ${ext.toUpperCase()}',
          error: e, stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeError(e, accion: 'exportar el log'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _sharePdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final entries = await AppLogger.instance.query(
        levels: _levels,
        module: _module,
        search: _search.text,
        limit: 1500,
      );
      final logger = AppLogger.instance;
      final doc = pw.Document();
      // Fuentes estándar embebidas: funcionan sin internet.
      final mono = pw.Font.courier();
      final monoBold = pw.Font.courierBold();
      final header = 'MecsaOPS Mobile - Registro de actividad | '
          'v${logger.appVersion ?? '?'} | ${entries.length} entradas | '
          'exportado ${DateTime.now().toIso8601String().substring(0, 19)}';

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (ctx) => pw.Text(header,
              style: pw.TextStyle(font: monoBold, fontSize: 8)),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Página ${ctx.pageNumber}/${ctx.pagesCount}',
                style: pw.TextStyle(font: mono, fontSize: 7)),
          ),
          build: (ctx) => [
            for (final e in entries.reversed)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(
                  e.toText(),
                  style: pw.TextStyle(
                    font: mono,
                    fontSize: 7,
                    color: e.level == LogLevel.error
                        ? PdfColors.red800
                        : e.level == LogLevel.warning
                            ? PdfColors.orange800
                            : PdfColors.black,
                  ),
                ),
              ),
          ],
        ),
      );
      final bytes = await doc.save();
      await Printing.sharePdf(
          bytes: bytes, filename: 'mecsaops_log_${_stamp()}.pdf');
      AppLogger.instance.i('log', 'Registro exportado a PDF',
          data: {'entradas': entries.length});
    } catch (e, st) {
      AppLogger.instance.e('log', 'No se pudo exportar el registro',
          error: e, stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeError(e, accion: 'exportar el log'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showDetail(LogEntry e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Icon(_iconFor(e.level), color: _colorFor(e.level)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${e.level.tag} · ${e.module}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: 'Copiar entrada',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: e.toText()));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Entrada copiada')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${e.ts.toIso8601String().substring(0, 19).replaceFirst('T', ' ')}'
              '${e.usuario != null ? ' · ${e.usuario}' : ''}'
              '${e.appVersion != null ? ' · v${e.appVersion}' : ''}',
              style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 12),
            ),
            const Divider(height: 24),
            _DetailBlock(title: 'Mensaje', text: e.message),
            if (e.data != null && e.data!.isNotEmpty)
              _DetailBlock(
                title: 'Datos',
                text: e.data!.entries.map((kv) => '${kv.key}: ${kv.value}').join('\n'),
              ),
            if (e.error != null && e.error!.isNotEmpty)
              _DetailBlock(title: 'Error', text: e.error!, color: Colors.red[50]),
            if (e.stack != null && e.stack!.isNotEmpty)
              _DetailBlock(title: 'Stack trace', text: e.stack!, mono: true),
          ],
        ),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de actividad'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copiar todo',
            onPressed: _entries.isEmpty ? null : _copyAll,
          ),
          PopupMenuButton<_ExportFormat>(
            icon: _exporting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share_outlined),
            tooltip: 'Compartir',
            enabled: _entries.isNotEmpty && !_exporting,
            onSelected: _share,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ExportFormat.pdf,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('PDF'),
                  subtitle: Text('Para leer'),
                ),
              ),
              PopupMenuItem(
                value: _ExportFormat.csv,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('CSV'),
                  subtitle: Text('Para Excel'),
                ),
              ),
              PopupMenuItem(
                value: _ExportFormat.json,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.data_object),
                  title: Text('JSON'),
                  subtitle: Text('Para análisis'),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurar',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogSettingsScreen()),
              );
              _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Buscar en mensaje, datos o error',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              _load();
                            },
                          ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final l in LogLevel.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(l.tag),
                            avatar: Icon(_iconFor(l),
                                size: 16, color: _colorFor(l)),
                            selected: _levels.contains(l),
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _levels.add(l);
                                } else if (_levels.length > 1) {
                                  _levels.remove(l);
                                }
                              });
                              _load();
                            },
                          ),
                        ),
                      const SizedBox(width: 6),
                      DropdownButton<String?>(
                        value: _module,
                        hint: const Text('Módulo'),
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('Todos los módulos')),
                          for (final m in _modules)
                            DropdownMenuItem<String?>(value: m, child: Text(m)),
                        ],
                        onChanged: (m) {
                          setState(() => _module = m);
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          // Lista
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 48, color: AppColors.of(context).textMuted),
                            const SizedBox(height: 8),
                            Text(
                              'No hay entradas con estos filtros',
                              style: TextStyle(color: AppColors.of(context).textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _entries.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            if (i >= _entries.length) {
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Center(
                                  child: TextButton(
                                    onPressed: () => _load(append: true),
                                    child: const Text('Cargar más'),
                                  ),
                                ),
                              );
                            }
                            final e = _entries[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(_iconFor(e.level),
                                  color: _colorFor(e.level), size: 22),
                              title: Text(
                                e.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: e.level == LogLevel.error
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                '${_fmtTime(e.ts)} · ${e.module}'
                                '${e.error != null ? ' · ${e.error}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onTap: () => _showDetail(e),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String title;
  final String text;
  final Color? color;
  final bool mono;

  const _DetailBlock({
    required this.title,
    required this.text,
    this.color,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: AppColors.of(context).textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color ?? AppColors.of(context).surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              text,
              style: TextStyle(
                fontSize: mono ? 11 : 13,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
