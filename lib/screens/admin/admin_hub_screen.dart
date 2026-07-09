// =============================================================================
// admin_hub_screen.dart
// Menú principal del modo Administración. Solo visible para quien tenga
// acceso a la web (AppProvider.isWebAdmin). Cada tarjeta abre una función.
// Las tarjetas se muestran según los permisos del usuario.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import 'aprobar_liquidaciones_screen.dart';
import 'aprobar_reservas_screen.dart';
import 'correcciones_screen.dart';
import 'desbloquear_reservas_screen.dart';

class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final primary = Theme.of(context).primaryColor;

    final cards = <Widget>[];

    if (p.canApproveLiquidaciones) {
      cards.add(_AdminCard(
        icon: Icons.receipt_long,
        color: Colors.green,
        title: 'Aprobar Liquidaciones',
        subtitle: 'Revisa y aprueba/rechaza viáticos pendientes',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AprobarLiquidacionesScreen())),
      ));
    }
    if (p.canApproveReservas) {
      cards.add(_AdminCard(
        icon: Icons.directions_car,
        color: Colors.blue,
        title: 'Aprobar Reservas',
        subtitle: 'Aprueba/rechaza reservas de vehículos',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AprobarReservasScreen())),
      ));
    }
    if (p.canManageAdmin) {
      cards.add(_AdminCard(
        icon: Icons.edit_note,
        color: Colors.orange,
        title: 'Solicitudes de Corrección',
        subtitle: 'Procesa correcciones de viáticos y kilometraje',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CorreccionesScreen())),
      ));
      cards.add(_AdminCard(
        icon: Icons.lock_open,
        color: Colors.red,
        title: 'Desbloquear Reservas',
        subtitle: 'Reactiva empleados bloqueados por strikes',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const DesbloquearReservasScreen())),
      ));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Administración'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: cards.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No tienes funciones administrativas asignadas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: cards,
            ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.blueGrey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
