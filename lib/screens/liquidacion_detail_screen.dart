import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/liquidacion.dart';
import '../services/liquidaciones_service.dart';

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
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
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
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Detalle de Liquidación'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: liquidacion != null && liquidacion!.estado == 'pendiente'
            ? [
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _deleteLiquidacion,
                ),
              ]
            : null,
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
                  Text('Error: $error'),
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
                    child:
                        liquidacion!.facturas == null ||
                            liquidacion!.facturas!.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'No hay facturas registradas',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : Column(
                            children: liquidacion!.facturas!
                                .map(
                                  (factura) => _FacturaItem(factura: factura),
                                )
                                .toList(),
                          ),
                  ),
                ],
              ),
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

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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

  const _FacturaItem({required this.factura});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
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
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
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
              Text(
                '₡${factura.monto.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
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
          if (factura.documento != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _viewDocument(factura.documento!),
                  icon: const Icon(Icons.description, size: 18),
                  label: const Text('Ver Comprobante'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _viewDocument(String path) async {
    final url = Uri.parse(
      'https://awhuzekjpoapamijlvua.supabase.co/storage/v1/object/public/facturas_viaticos/$path',
    );
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'No se pudo abrir la URL';
      }
    } catch (e) {
      debugPrint('Error al abrir documento: $e');
    }
  }
}
