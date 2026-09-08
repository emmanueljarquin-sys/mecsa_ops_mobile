// =============================================================================
// aprobar_liquidaciones_screen.dart
// Pantalla admin: lista de liquidaciones pendientes que el usuario puede
// aprobar/rechazar. Reusa AdminService.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../services/admin_service.dart';
import '../../models/liquidacion.dart';
import '../liquidacion_detail_screen.dart';

class AprobarLiquidacionesScreen extends StatefulWidget {
  const AprobarLiquidacionesScreen({super.key});

  @override
  State<AprobarLiquidacionesScreen> createState() =>
      _AprobarLiquidacionesScreenState();
}

class _AprobarLiquidacionesScreenState
    extends State<AprobarLiquidacionesScreen> {
  bool _loading = true;
  String? _error;
  List<Liquidacion> _pendientes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = context.read<AppProvider>();
      final data = await AdminService.getPendientesParaAprobar(
        actorId: p.currentEmployeeId ?? '',
        isAdminOrConta: p.isRoleAdmin || p.isContabilidad,
      );
      if (!mounted) return;
      setState(() {
        _pendientes = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _decidir(Liquidacion liq, bool aprobar) async {
    final comentarioCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aprobar ? 'Aprobar liquidación' : 'Rechazar liquidación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${liq.empleadoCompleto} · ₡${(liq.total ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: comentarioCtrl,
              decoration: InputDecoration(
                labelText: aprobar ? 'Comentario (opcional)' : 'Motivo del rechazo',
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: aprobar ? Colors.green : Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Feedback de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final p = context.read<AppProvider>();
      await AdminService.aprobarLiquidacion(
        actorId: p.currentEmployeeId ?? '',
        liquidacionId: liq.id,
        aprobar: aprobar,
        comentario: comentarioCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context); // cerrar loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(aprobar ? 'Liquidación aprobada' : 'Liquidación rechazada'),
          backgroundColor: aprobar ? Colors.green : Colors.orange,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // cerrar loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Aprobar Liquidaciones'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.error_outline, size: 56, color: Colors.red),
          const SizedBox(height: 12),
          Center(child: Text('Error: $_error', textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
          ),
        ],
      );
    }
    if (_pendientes.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 140),
          Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          SizedBox(height: 12),
          Center(child: Text('No hay liquidaciones pendientes')),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _pendientes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final liq = _pendientes[i];
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        liq.empleadoCompleto,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Text(
                      '₡${(liq.total ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  liq.proyectoNombre ?? 'Sin proyecto',
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                Text(
                  'Fecha: ${liq.fecha.toLocal().toString().split(' ').first}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LiquidacionDetailScreen(liquidacionId: liq.id),
                        ),
                      ),
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('Ver detalle'),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: () => _decidir(liq, false),
                      child: const Text('Rechazar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () => _decidir(liq, true),
                      child: const Text('Aprobar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
