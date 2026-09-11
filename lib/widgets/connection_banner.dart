// =============================================================================
// connection_banner.dart — Banner global de conectividad y estado de carga
// -----------------------------------------------------------------------------
// Se muestra arriba de todas las pestañas (HomeScreen). Tres estados:
//   1. Sin internet  → naranja: "Sin conexión. Mostrando datos guardados..."
//   2. Carga fallida → rojo: "No se pudieron cargar los datos" + Reintentar
//   3. Todo bien     → no se muestra
// Los datos que se ven en la app vienen de la caché local cuando aplica.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/connectivity_service.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    final hm = '${two(d.hour)}:${two(d.minute)}';
    return sameDay ? 'hoy a las $hm' : 'el ${two(d.day)}/${two(d.month)} a las $hm';
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectivityService>();
    final provider = context.watch<AppProvider>();

    final bool offline = !conn.isOnline;
    final bool failed = provider.loadError != null;
    if (!offline && !failed) return const SizedBox.shrink();

    final DateTime? since = provider.lastSyncAt;
    final bool hasData = provider.hasCachedData;

    final Color bg = offline ? Colors.orange.shade50 : Colors.red.shade50;
    final Color border = offline ? Colors.orange.shade200 : Colors.red.shade200;
    final Color fg = offline ? Colors.orange.shade900 : Colors.red.shade900;
    final IconData icon = offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded;

    final String title = offline
        ? (conn.hasNetwork ? 'Sin acceso a internet' : 'Sin conexión')
        : 'No se pudieron cargar los datos';
    final String detail = hasData
        ? 'Mostrando datos guardados ${since != null ? _fmt(since) : 'en el teléfono'}.'
        : 'No hay datos guardados en este teléfono todavía.';

    return Material(
      color: bg,
      child: InkWell(
        onTap: failed ? () => _showDetail(context, provider.loadError!) : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: fg, fontSize: 13)),
                    Text(detail,
                        style: TextStyle(color: fg, fontSize: 12)),
                  ],
                ),
              ),
              if (provider.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                TextButton(
                  onPressed: () async {
                    await conn.checkInternet(force: true);
                    provider.fetchData();
                  },
                  style: TextButton.styleFrom(foregroundColor: fg),
                  child: const Text('REINTENTAR'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Detalle del error'),
        content: SingleChildScrollView(child: SelectableText(error)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR')),
        ],
      ),
    );
  }
}
