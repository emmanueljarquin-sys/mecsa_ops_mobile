// =============================================================================
// correcciones_screen.dart
// Pantalla admin: solicitudes de corrección pendientes (viáticos + kilometraje).
// El admin lee el motivo del empleado, escribe una respuesta y marca procesada.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../services/admin_service.dart';

class CorreccionesScreen extends StatefulWidget {
  const CorreccionesScreen({super.key});

  @override
  State<CorreccionesScreen> createState() => _CorreccionesScreenState();
}

class _CorreccionesScreenState extends State<CorreccionesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final data = await AdminService.getCorreccionesPendientes();
      if (!mounted) return;
      setState(() {
        _items = data;
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

  Future<void> _procesar(Map<String, dynamic> item) async {
    final respuestaCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Procesar corrección'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['_empleado'] ?? 'Empleado'} — ${item['_origen']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(item['solicitud_correccion']?.toString() ?? '-',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: respuestaCtrl,
              decoration: const InputDecoration(
                labelText: 'Respuesta al empleado (opcional)',
                hintText: 'Ej.: Corregido en el sistema.',
                border: OutlineInputBorder(),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar procesada'),
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
      final p = context.read<AppProvider>();
      await AdminService.procesarCorreccion(
        actorId: p.currentEmployeeId ?? '',
        schema: item['_schema'].toString(),
        table: item['_tabla'].toString(),
        recordId: item['id'].toString(),
        respuesta: respuestaCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrección procesada'), backgroundColor: Colors.green),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Solicitudes de Corrección'),
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
    if (_items.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 140),
        Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
        SizedBox(height: 12),
        Center(child: Text('No hay solicitudes de corrección')),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = _items[i];
        final esViatico = item['_origen'] == 'viaticos';
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(esViatico ? Icons.receipt_long : Icons.directions_car,
                      size: 18, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 6),
                  Text(esViatico ? 'Viáticos' : 'Kilometraje',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Pendiente',
                        style: TextStyle(fontSize: 11, color: Colors.deepOrange)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(item['_empleado']?.toString() ?? 'Empleado',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(item['solicitud_correccion']?.toString() ?? '-',
                    style: const TextStyle(fontSize: 13, height: 1.35)),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                    onPressed: () => _procesar(item),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Procesar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
