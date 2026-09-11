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
    final Color fondo = permiteContinuar ? Colors.orange.shade50 : Colors.red.shade50;
    final Color borde = permiteContinuar ? Colors.orange.shade300 : Colors.red.shade200;
    final Color color = permiteContinuar ? Colors.orange.shade900 : Colors.red.shade900;
    final Color icono = permiteContinuar ? Colors.orange.shade800 : Colors.red.shade700;
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
