// =============================================================================
// desbloquear_reservas_screen.dart
// Pantalla admin: empleados bloqueados para reservas → desbloquear.
// =============================================================================
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';

class DesbloquearReservasScreen extends StatefulWidget {
  const DesbloquearReservasScreen({super.key});

  @override
  State<DesbloquearReservasScreen> createState() =>
      _DesbloquearReservasScreenState();
}

class _DesbloquearReservasScreenState extends State<DesbloquearReservasScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bloqueados = [];

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
      final data = await AdminService.getEmpleadosBloqueados();
      if (!mounted) return;
      setState(() {
        _bloqueados = data;
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

  Future<void> _desbloquear(Map<String, dynamic> emp) async {
    final nombre = '${emp['nombre'] ?? ''} ${emp['apellido'] ?? ''}'.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desbloquear empleado'),
        content: Text(
          '¿Desbloquear a $nombre para que pueda volver a reservar vehículos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desbloquear'),
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
      await AdminService.desbloquearEmpleado(emp['id'].toString());
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nombre desbloqueado'), backgroundColor: Colors.green),
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
        title: const Text('Desbloquear Reservas'),
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
    if (_bloqueados.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 140),
        Icon(Icons.lock_open, size: 64, color: Colors.green),
        SizedBox(height: 12),
        Center(child: Text('No hay empleados bloqueados')),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _bloqueados.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = _bloqueados[i];
        final nombre = '${e['nombre'] ?? ''} ${e['apellido'] ?? ''}'.trim();
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red.shade50,
              child: const Icon(Icons.lock, color: Colors.red),
            ),
            title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Bloqueado por reservas sin registrar',
                style: TextStyle(fontSize: 12)),
            trailing: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => _desbloquear(e),
              child: const Text('Desbloquear'),
            ),
          ),
        );
      },
    );
  }
}
