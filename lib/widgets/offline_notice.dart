// =============================================================================
// offline_notice.dart — Banner "estás sin conexión" para formularios
// -----------------------------------------------------------------------------
// Se muestra solo cuando ConnectivityService dice que no hay internet real.
// Úsalo dentro de un Column: `const OfflineNotice(texto: '...')`.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connectivity_service.dart';

class OfflineNotice extends StatelessWidget {
  final String texto;
  /// true = naranja (se puede seguir, quedará pendiente); false = rojo (bloqueado).
  final bool permiteContinuar;
  final EdgeInsetsGeometry margin;

  const OfflineNotice({
    super.key,
    required this.texto,
    this.permiteContinuar = true,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityService>().isOnline;
    if (online) return const SizedBox.shrink();
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final MaterialColor base = permiteContinuar ? Colors.orange : Colors.red;
    // En oscuro: fondo translúcido y texto claro; en claro: pastel y texto oscuro.
    final Color fondo = dark ? base.withValues(alpha: 0.18) : base.shade50;
    final Color borde = dark ? base.shade700 : (permiteContinuar ? base.shade300 : base.shade200);
    final Color color = dark ? base.shade100 : base.shade900;
    final Color icono = dark ? base.shade300 : (permiteContinuar ? base.shade800 : base.shade700);
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borde),
      ),
      child: Row(
        children: [
          Icon(permiteContinuar ? Icons.cloud_off : Icons.wifi_off, color: icono),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
