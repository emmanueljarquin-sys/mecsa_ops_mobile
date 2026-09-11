import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/mensajes_error.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/liquidacion.dart';
import '../services/liquidaciones_service.dart';
import '../services/offline_service.dart';
import '../services/comprobantes_service.dart';
import '../services/liquidacion_pdf_service.dart';
import 'comprobante_viewer_screen.dart';
import '../providers/app_provider.dart';
import '../widgets/correccion_widgets.dart';
import '../utils/num_parse.dart';

class LiquidacionDetailScreen extends StatefulWidget {
  final String liquidacionId;

  const LiquidacionDetailScreen({super.key, required this.liquidacionId});

  @override
  State<LiquidacionDetailScreen> createState() =>
      _LiquidacionDetailScreenState();
}

class _LiquidacionDetailScreenState extends State<LiquidacionDetailScreen> {
  Liquidacion? liquidacion;
  bool isLoading = true;
  String? error;

  // Comentarios (hilo)
  List<Map<String, dynamic>> _comentarios = [];
  final _comentarioCtrl = TextEditingController();
  bool _sendingComentario = false;

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final result = await LiquidacionesService.getLiquidacionDetail(
        widget.liquidacionId,
      );
      setState(() {
        liquidacion = result;
        isLoading = false;
      });
      _loadComentarios();
      // Dejar los comprobantes en caché para verlos / exportarlos sin red.
      final paths = (liquidacion?.facturas ?? [])
          .map((f) => f.comprobantePath ?? '')
          .where((p) => p.isNotEmpty);
      ComprobantesService.instance.precargar(paths);
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _loadComentarios() async {
    try {
      final c = await LiquidacionesService.getComentarios(widget.liquidacionId);
      if (mounted) setState(() => _comentarios = c);
    } catch (_) {
      // silencioso: si falla, solo no muestra comentarios
    }
  }

  Future<void> _addComentario() async {
    final texto = _comentarioCtrl.text.trim();
    if (texto.isEmpty) return;
    setState(() => _sendingComentario = true);
    try {
      final p = Provider.of<AppProvider>(context, listen: false);
      final data = p.currentEmployeeData;
      final nombre = data == null
          ? null
          : '${data['nombre'] ?? ''} ${data['apellido'] ?? ''}'.trim();
      await LiquidacionesService.addComentario(
        liquidacionId: widget.liquidacionId,
        autorId: p.currentEmployeeId,
        autorNombre: (nombre == null || nombre.isEmpty) ? 'Yo' : nombre,
        comentario: texto,
      );
      _comentarioCtrl.clear();
      await _loadComentarios();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeError(e, accion: 'enviar el comentario')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingComentario = false);
    }
  }

  Future<void> _deleteLiquidacion() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Liquidación'),
        content: const Text(
          '¿Estás seguro de eliminar esta liquidación? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await LiquidacionesService.deleteLiquidacion(widget.liquidacionId);
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Liquidación eliminada')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(mensajeError(e)), backgroundColor: Colors.red));
        }
      }
    }
  }

  bool get _editable => liquidacion?.estado == 'pendiente';

  Future<void> _abrirFormFactura({Factura? existente}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FacturaFormSheet(
        liquidacionId: widget.liquidacionId,
        existente: existente,
      ),
    );
    if (guardado == true && mounted) _loadDetail();
  }

  Future<void> _eliminarFactura(Factura f) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar factura'),
        content: Text('¿Eliminar la factura de ${f.proveedor} por ₡${f.monto.toStringAsFixed(2)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await LiquidacionesService.deleteFactura(f.id!);
      if (mounted) {
        _loadDetail();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Factura eliminada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeError(e, accion: 'guardar la factura')), backgroundColor: Colors.red),
        );
      }
    }
  }

  static String _msg(Object e) =>
      e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException(message: ', '').split(',').first;

  /// Genera el PDF (datos + facturas + comprobantes) y abre el diálogo de
  /// compartir del sistema (WhatsApp, correo, Drive, guardar…).
  Future<void> _exportarPdf() async {
    final l = liquidacion;
    if (l == null) return;
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Generando PDF con comprobantes…')),
        ]),
      ),
    );
    try {
      final bytes = await LiquidacionPdfService.construir(l);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await Printing.sharePdf(
        bytes: bytes,
        filename: LiquidacionPdfService.nombreArchivo(l),
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(mensajeError(e, accion: 'generar el PDF')),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: const Text('Detalle de Liquidación'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: liquidacion == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf),
                  tooltip: 'Exportar PDF',
                  onPressed: _exportarPdf,
                ),
                if (liquidacion!.estado == 'pendiente')
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Eliminar',
                    onPressed: _deleteLiquidacion,
                  ),
                // Botón "Solicitar corrección" solo si NO está pendiente
                // (aún editable) y NO tiene ya una solicitud abierta
                if (liquidacion!.estado != 'pendiente' &&
                    (liquidacion!.solicitudCorreccion == null ||
                        liquidacion!.solicitudCorreccion!.isEmpty))
                  IconButton(
                    icon: const Icon(Icons.edit_note),
                    tooltip: 'Solicitar corrección',
                    onPressed: () async {
                      final ok = await showSolicitarCorreccionDialog(
                        context,
                        schema: 'viaticos',
                        table: 'liquidaciones',
                        recordId: liquidacion!.id,
                        titulo: 'Solicitar corrección de liquidación',
                      );
                      if (ok && mounted) _loadDetail();
                    },
                  ),
              ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(mensajeError(error, accion: 'cargar la liquidación')),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadDetail,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Banner de corrección (si aplica)
                  if (liquidacion != null &&
                      liquidacion!.solicitudCorreccion != null &&
                      liquidacion!.solicitudCorreccion!.isNotEmpty)
                    CorreccionBanner(
                      motivo: liquidacion!.solicitudCorreccion!,
                      fecha: liquidacion!.fechaCorreccion
                          ?.toLocal()
                          .toString()
                          .split('.')
                          .first,
                      respuestaAdmin: liquidacion!.respuestaAdmin,
                    ),
                  // Información General
                  _SectionCard(
                    title: 'Información General',
                    icon: Icons.info_outline,
                    child: Column(
                      children: [
                        _InfoRow('Empleado', liquidacion!.empleadoCompleto),
                        _InfoRow(
                          'Proyecto',
                          liquidacion!.proyectoNombre ?? 'N/A',
                        ),
                        _InfoRow(
                          'Fecha',
                          '${liquidacion!.fecha.day}/${liquidacion!.fecha.month}/${liquidacion!.fecha.year}',
                        ),
                        _InfoRow(
                          'Tarjeta (últimos 4)',
                          liquidacion!.tarjetaUlt4 ?? 'N/A',
                        ),
                        _InfoRow('Tipo', liquidacion!.tipo),
                        _InfoRow(
                          'Estado',
                          liquidacion!.estadoLabel,
                          valueWidget: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              liquidacion!.estadoLabel.toUpperCase(),
                              style: TextStyle(
                                color: _getStatusTextColor(),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Resumen de Totales
                  _SectionCard(
                    title: 'Resumen de Totales',
                    icon: Icons.calculate,
                    child: Column(
                      children: [
                        _TotalRow('Desayunos', liquidacion!.totales?['D'] ?? 0),
                        _TotalRow('Almuerzos', liquidacion!.totales?['A'] ?? 0),
                        _TotalRow('Cenas', liquidacion!.totales?['C'] ?? 0),
                        _TotalRow('Hospedaje', liquidacion!.totales?['H'] ?? 0),
                        _TotalRow(
                          'Combustible',
                          liquidacion!.totales?['COMBUSTIBLE'] ?? 0,
                        ),
                        _TotalRow('Otros', liquidacion!.totales?['OTROS'] ?? 0),
                        const Divider(height: 24, thickness: 2),
                        _TotalRow(
                          'TOTAL',
                          liquidacion!.totalGeneral,
                          isTotal: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Personal Incluido
                  if (liquidacion!.personalIncluido != null &&
                      liquidacion!.personalIncluido!.isNotEmpty)
                    _SectionCard(
                      title: 'Personal Incluido',
                      icon: Icons.people,
                      child: Text(
                        liquidacion!.personalIncluido!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Facturas
                  _SectionCard(
                    title: 'Facturas (${liquidacion!.facturas?.length ?? 0})',
                    icon: Icons.receipt,
                    trailing: _editable
                        ? TextButton.icon(
                            onPressed: () => _abrirFormFactura(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Agregar'),
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).primaryColor,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          )
                        : null,
                    child:
                        liquidacion!.facturas == null ||
                            liquidacion!.facturas!.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                _editable
                                    ? 'Sin facturas. Tocá "Agregar" para añadir una.'
                                    : 'No hay facturas registradas',
                                style: const TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : Column(
                            children: liquidacion!.facturas!
                                .map(
                                  (factura) => _FacturaItem(
                                    factura: factura,
                                    editable: _editable,
                                    onEdit: () => _abrirFormFactura(existente: factura),
                                    onDelete: () => _eliminarFactura(factura),
                                  ),
                                )
                                .toList(),
                          ),
                  ),

                  const SizedBox(height: 16),

                  // Comentarios (hilo)
                  _buildComentariosSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildComentariosSection() {
    final primary = Theme.of(context).primaryColor;
    return _SectionCard(
      title: 'Comentarios (${_comentarios.length})',
      icon: Icons.forum_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_comentarios.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aún no hay comentarios.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ..._comentarios.map(_buildComentarioItem),
          const SizedBox(height: 8),
          // Caja para agregar comentario (disponible en cualquier estado)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _comentarioCtrl,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Escribí un comentario…',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _sendingComentario ? null : _addComentario,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _sendingComentario
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComentarioItem(Map<String, dynamic> c) {
    final autor = (c['autor_nombre'] ?? 'Alguien').toString();
    final texto = (c['comentario'] ?? '').toString();
    String fecha = '';
    final rawFecha = c['created_at'];
    if (rawFecha != null) {
      final dt = DateTime.tryParse(rawFecha.toString())?.toLocal();
      if (dt != null) fecha = DateFormat('dd/MM/yyyy HH:mm').format(dt);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(autor,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).primaryColor)),
              Text(fecha, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          Text(texto, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (liquidacion!.estado) {
      case 'pendiente':
        return const Color(0xFFFFF3CD);
      case 'aprobada':
        return const Color(0xFFD1E7DD);
      case 'rechazada':
        return const Color(0xFFF8D7DA);
      default:
        return const Color(0xFFE2E3E5);
    }
  }

  Color _getStatusTextColor() {
    switch (liquidacion!.estado) {
      case 'pendiente':
        return const Color(0xFF856404);
      case 'aprobada':
        return const Color(0xFF0F5132);
      case 'rechazada':
        return const Color(0xFF842029);
      default:
        return const Color(0xFF383D41);
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.of(context).shadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              if (trailing != null) ...[const Spacer(), trailing!],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? valueWidget;

  const _InfoRow(this.label, this.value, {this.valueWidget});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          valueWidget ??
              Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isTotal;

  const _TotalRow(this.label, this.amount, {this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              fontSize: isTotal ? 16 : 14,
            ),
          ),
          Text(
            '₡${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isTotal ? 18 : 14,
              color: isTotal ? Theme.of(context).primaryColor : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _FacturaItem extends StatelessWidget {
  final Factura factura;
  final bool editable;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _FacturaItem({
    required this.factura,
    this.editable = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.of(context).surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  factura.tipoLabel,
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    '₡${factura.monto.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (editable) ...[
                    IconButton(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 18),
                      color: Colors.blueGrey,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Editar',
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: Colors.red,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Eliminar',
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            factura.proveedor,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${factura.fecha.day}/${factura.fecha.month}/${factura.fecha.year}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(width: 12),
              Text(
                '#${factura.numeroFactura}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          if (factura.comprobantePath != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.attach_file,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            factura.documento == null || factura.documento!.isEmpty
                                ? 'Comprobante (pendiente de subir)'
                                : 'Comprobante adjunto',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => ComprobanteViewerScreen.abrir(
                              context,
                              factura.comprobantePath!,
                              titulo: '${factura.tipoLabel} · ${factura.proveedor}',
                            ),
                            icon: const Icon(Icons.visibility, size: 18),
                            label: const Text(
                              'VER',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Bottom sheet para agregar / editar una factura (solo si la liquidación
// está pendiente; el trigger de BD garantiza la regla server-side).
// =============================================================================
class _FacturaFormSheet extends StatefulWidget {
  final String liquidacionId;
  final Factura? existente;

  const _FacturaFormSheet({required this.liquidacionId, this.existente});

  @override
  State<_FacturaFormSheet> createState() => _FacturaFormSheetState();
}

class _FacturaFormSheetState extends State<_FacturaFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _proveedor;
  late final TextEditingController _numero;
  late final TextEditingController _monto;
  late String _tipo;
  late DateTime _fecha;
  String? _documentoPath; // path ya subido (edición)
  File? _nuevoDoc; // archivo local nuevo
  bool _saving = false;

  static const _tipos = {
    'D': 'Desayuno',
    'A': 'Almuerzo',
    'C': 'Cena',
    'H': 'Hospedaje',
    'COMBUSTIBLE': 'Combustible',
    'OTROS': 'Otros',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _proveedor = TextEditingController(text: e?.proveedor ?? '');
    _numero = TextEditingController(text: e?.numeroFactura ?? '');
    _monto = TextEditingController(text: e != null ? e.monto.toStringAsFixed(2) : '');
    _tipo = e?.tipo != null && _tipos.containsKey(e!.tipo) ? e.tipo : 'OTROS';
    _fecha = e?.fecha ?? DateTime.now();
    _documentoPath = e?.documento;
  }

  @override
  void dispose() {
    _proveedor.dispose();
    _numero.dispose();
    _monto.dispose();
    super.dispose();
  }

  Future<void> _pickDoc(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (x != null) setState(() => _nuevoDoc = File(x.path));
  }

  void _elegirOrigen() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tomar foto'),
              onTap: () { Navigator.pop(context); _pickDoc(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de galería'),
              onTap: () { Navigator.pop(context); _pickDoc(ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // ── SIN CONEXIÓN: encolar (solo facturas nuevas; editar requiere internet) ──
    if (widget.existente == null && !await OfflineService.instance.hayConexion()) {
      await OfflineService.instance.enqueue(
        type: 'factura',
        record: {
          'liquidacion_id': widget.liquidacionId,
          'proveedor': _proveedor.text.trim(),
          'numero_factura': _numero.text.trim(),
          'tipo': _tipo,
          'monto': parseNum(_monto.text),
          'fecha': _fecha.toIso8601String().split('T').first,
        },
        photos: _nuevoDoc != null ? {'documento': _nuevoDoc!.path} : null,
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Factura guardada sin conexión. Se subirá cuando haya internet.'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }

    try {
      // Subir comprobante nuevo si se eligió
      if (_nuevoDoc != null) {
        _documentoPath = await LiquidacionesService.uploadDocumento(_nuevoDoc!.path);
      }
      final factura = Factura(
        liquidacionId: widget.liquidacionId,
        proveedor: _proveedor.text.trim(),
        numeroFactura: _numero.text.trim(),
        tipo: _tipo,
        monto: parseNum(_monto.text),
        fecha: _fecha,
        documento: _documentoPath,
      );

      if (widget.existente == null) {
        await LiquidacionesService.createFactura(factura);
      } else {
        await LiquidacionesService.updateFactura(widget.existente!.id!, factura);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        final msg = e.toString().contains('pendiente')
            ? 'Esta liquidación ya fue aprobada/rechazada; no se puede modificar.'
            : e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final tieneDoc = _nuevoDoc != null || (_documentoPath != null && _documentoPath!.isNotEmpty);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.of(context).surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: AppColors.of(context).surfaceVariant, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(widget.existente == null ? 'Agregar factura' : 'Editar factura',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                  items: _tipos.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _tipo = v ?? 'OTROS'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _proveedor,
                  decoration: const InputDecoration(labelText: 'Proveedor', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _numero,
                  decoration: const InputDecoration(labelText: 'N° de factura', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _monto,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Monto (₡)', border: OutlineInputBorder(), prefixText: '₡ '),
                  validator: (v) {
                    final d = double.tryParse((v ?? '').trim());
                    if (d == null || d <= 0) return 'Monto inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _fecha,
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _fecha = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Fecha', border: OutlineInputBorder()),
                    child: Text('${_fecha.day}/${_fecha.month}/${_fecha.year}'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _elegirOrigen,
                  icon: Icon(tieneDoc ? Icons.check_circle : Icons.attach_file,
                      color: tieneDoc ? Colors.green : primary),
                  label: Text(tieneDoc ? 'Comprobante adjunto (cambiar)' : 'Adjuntar comprobante (opcional)'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: tieneDoc ? Colors.green : primary,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _guardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(widget.existente == null ? 'Agregar factura' : 'Guardar cambios',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
