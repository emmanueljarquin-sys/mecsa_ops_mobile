// =============================================================================
// notifications_screen.dart — Campana del Dashboard
// -----------------------------------------------------------------------------
// Lista las notificaciones guardadas por NotificacionesService (push,
// liquidaciones, sincronización, versión). Tocar una la marca leída y navega
// al detalle cuando aplica (visita, liquidaciones, copias de seguridad).
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/notificaciones_service.dart';
import '../theme/app_theme.dart';
import 'backup_settings_screen.dart';
import 'visita_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificacionApp> _items = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final l = await NotificacionesService.instance.listar();
    if (!mounted) return;
    setState(() {
      _items = l;
      _cargando = false;
    });
  }

  String _fecha(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    final hh = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Hoy $hh';
    final ayer = now.subtract(const Duration(days: 1));
    if (d.year == ayer.year && d.month == ayer.month && d.day == ayer.day) return 'Ayer $hh';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} $hh';
  }

  IconData _icono(String tipo) {
    switch (tipo) {
      case 'liquidacion':
        return Icons.receipt_long;
      case 'visita':
        return Icons.map;
      case 'reserva':
        return Icons.directions_car;
      case 'sync':
        return Icons.cloud_done_outlined;
      case 'version':
        return Icons.system_update;
      case 'chat':
        return Icons.chat_bubble_outline;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _color(String tipo) {
    switch (tipo) {
      case 'liquidacion':
        return Colors.orange.shade700;
      case 'visita':
        return Colors.green.shade700;
      case 'reserva':
        return Colors.blue.shade700;
      case 'sync':
        return Colors.teal.shade700;
      case 'version':
        return Colors.purple.shade700;
      case 'chat':
        return const Color(0xFF25D366);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Future<void> _abrir(NotificacionApp n) async {
    await NotificacionesService.instance.marcarLeida(n.id);
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    switch (n.tipo) {
      case 'visita':
        final id = n.data['visita_id']?.toString();
        final v = provider.visitas.firstWhere(
          (x) => x['id'].toString() == id,
          orElse: () => <String, dynamic>{},
        );
        if (v.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => VisitaDetailScreen(visita: v)));
        } else {
          Navigator.pop(context);
          provider.setIndex(3);
        }
        break;
      case 'liquidacion':
        Navigator.pop(context);
        provider.setIndex(2);
        break;
      case 'reserva':
        Navigator.pop(context);
        provider.setIndex(1);
        break;
      case 'sync':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupSettingsScreen()));
        break;
      default:
        break;
    }
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (_items.any((n) => !n.leida))
            IconButton(
              tooltip: 'Marcar todas como leídas',
              icon: const Icon(Icons.done_all),
              onPressed: () async {
                await NotificacionesService.instance.marcarTodasLeidas();
                _cargar();
              },
            ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Borrar todas',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('¿Borrar notificaciones?'),
                    content: const Text('Se eliminará el historial de este teléfono.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
                    ],
                  ),
                );
                if (ok == true) {
                  await NotificacionesService.instance.limpiar();
                  _cargar();
                }
              },
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: c.textMuted),
                      const SizedBox(height: 12),
                      Text('Sin notificaciones', style: TextStyle(color: c.textSecondary, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Aquí verás avisos de liquidaciones, pagos y sincronización.',
                          style: TextStyle(color: c.textMuted, fontSize: 12)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
                    itemBuilder: (context, i) {
                      final n = _items[i];
                      return Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red.shade400,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) async {
                          await NotificacionesService.instance.eliminar(n.id);
                          _cargar();
                        },
                        child: ListTile(
                          tileColor: n.leida ? null : Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                          leading: CircleAvatar(
                            backgroundColor: _color(n.tipo).withValues(alpha: 0.15),
                            child: Icon(_icono(n.tipo), color: _color(n.tipo), size: 22),
                          ),
                          title: Text(
                            n.titulo,
                            style: TextStyle(
                              fontWeight: n.leida ? FontWeight.w500 : FontWeight.bold,
                              color: c.textPrimary,
                            ),
                          ),
                          subtitle: Text(n.cuerpo, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.textSecondary)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_fecha(n.fecha), style: TextStyle(fontSize: 11, color: c.textMuted)),
                              if (!n.leida)
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _abrir(n),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
