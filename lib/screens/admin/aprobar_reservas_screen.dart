// =============================================================================
// aprobar_reservas_screen.dart
// Pantalla admin: reservas de vehículo pendientes → aprobar/rechazar.
// =============================================================================
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';

class AprobarReservasScreen extends StatefulWidget {
  const AprobarReservasScreen({super.key});

  @override
  State<AprobarReservasScreen> createState() => _AprobarReservasScreenState();
}

class _AprobarReservasScreenState extends State<AprobarReservasScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pendientes = [];

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
      final data = await AdminService.getReservasPendientes();
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

  String _vehiculoLabel(Map<String, dynamic> r) {
    final v = r['vehiculo'];
    if (v is Map) {
      final marca = (v['marca'] ?? '').toString();
      final modelo = (v['modelo'] ?? '').toString();
      final placa = (v['placa'] ?? '').toString();
      final base = '$marca $modelo'.trim();
      if (base.isNotEmpty) {
        return placa.isNotEmpty ? '$base ($placa)' : base;
      }
    }
    return 'Vehículo';
  }

  String _empleadoLabel(Map<String, dynamic> r) {
    final e = r['empleado'];
    if (e is Map) return '${e['nombre'] ?? ''} ${e['apellido'] ?? ''}'.trim();
    return 'Solicitante';
  }

  Future<void> _decidir(Map<String, dynamic> reserva, bool aprobar) async {
    final comentarioCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aprobar ? 'Aprobar reserva' : 'Rechazar reserva'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_empleadoLabel(reserva)} · ${_vehiculoLabel(reserva)}',
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await AdminService.decidirReserva(
        reservaId: reserva['id'].toString(),
        aprobar: aprobar,
        vehiculoId: reserva['vehiculo_id']?.toString(),
        comentarios: comentarioCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(aprobar ? 'Reserva aprobada' : 'Reserva rechazada'),
          backgroundColor: aprobar ? Colors.green : Colors.orange,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  String _fmtFecha(dynamic iso) {
    if (iso == null) return '-';
    final d = DateTime.tryParse(iso.toString());
    if (d == null) return iso.toString();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Aprobar Reservas'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline, size: 56, color: Colors.red),
        const SizedBox(height: 12),
        Center(child: Text('Error: $_error', textAlign: TextAlign.center)),
        const SizedBox(height: 12),
        Center(child: ElevatedButton(onPressed: _load, child: const Text('Reintentar'))),
      ]);
    }
    if (_pendientes.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 140),
        Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
        SizedBox(height: 12),
        Center(child: Text('No hay reservas pendientes')),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _pendientes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _pendientes[i];
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_vehiculoLabel(r),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text('Solicita: ${_empleadoLabel(r)}',
                    style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.logout, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Salida: ${_fmtFecha(r['fecha_salida'])}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                Row(children: [
                  const Icon(Icons.login, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Regreso: ${_fmtFecha(r['fecha_regreso'])}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                if ((r['motivo'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(r['motivo'].toString(),
                      style: const TextStyle(fontSize: 12.5)),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  const Spacer(),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () => _decidir(r, false),
                    child: const Text('Rechazar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => _decidir(r, true),
                    child: const Text('Aprobar'),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
