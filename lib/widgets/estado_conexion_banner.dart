import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/offline_service.dart';

/// Banner de estado que se muestra ARRIBA de todas las pestañas. Ataca el
/// "pantalla vacía sin explicación": avisa cuando no hay internet, cuando falló
/// la carga de datos (con Reintentar) y cuando hay registros pendientes de subir
/// (con Subir ahora). Nunca deja al usuario adivinando.
class EstadoConexionBanner extends StatefulWidget {
  const EstadoConexionBanner({super.key});

  @override
  State<EstadoConexionBanner> createState() => _EstadoConexionBannerState();
}

class _EstadoConexionBannerState extends State<EstadoConexionBanner> {
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      final off = !r.any((x) => x != ConnectivityResult.none);
      if (mounted) setState(() => _offline = off);
      if (!off) OfflineService.instance.flush(); // volvió la red → subir pendientes
    });
  }

  Future<void> _check() async {
    try {
      final r = await Connectivity().checkConnectivity();
      final off = !r.any((x) => x != ConnectivityResult.none);
      if (mounted) setState(() => _offline = off);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final offline = OfflineService.instance;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_offline)
          _barra(
            bg: const Color(0xFFFEF2F2),
            fg: const Color(0xFFB91C1C),
            icon: Icons.wifi_off,
            text:
                'Sin conexión a internet. Lo que guardes queda en el teléfono y se sube solo.',
          ),
        if (!_offline &&
            provider.errorMessage != null &&
            provider.user != null)
          _barra(
            bg: const Color(0xFFFEF2F2),
            fg: const Color(0xFFB91C1C),
            icon: Icons.error_outline,
            text: 'No se pudieron cargar los datos.',
            accion: 'Reintentar',
            onTap: () => provider.fetchData(),
          ),
        AnimatedBuilder(
          animation: offline,
          builder: (_, _) {
            if (offline.pendingCount == 0) return const SizedBox.shrink();
            return _barra(
              bg: const Color(0xFFFFF7ED),
              fg: const Color(0xFF9A3412),
              icon: offline.isFlushing
                  ? Icons.sync
                  : Icons.cloud_upload_outlined,
              text: offline.isFlushing
                  ? 'Subiendo ${offline.pendingCount} registro(s) pendiente(s)…'
                  : '${offline.pendingCount} registro(s) pendiente(s) de subir. Ya están guardados en el teléfono.',
              accion: offline.isFlushing ? null : 'Subir ahora',
              onTap: offline.isFlushing ? null : () => offline.flush(),
            );
          },
        ),
      ],
    );
  }

  Widget _barra({
    required Color bg,
    required Color fg,
    required IconData icon,
    required String text,
    String? accion,
    VoidCallback? onTap,
  }) {
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    color: fg, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            if (accion != null)
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                    foregroundColor: fg,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32)),
                child: Text(accion,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}
