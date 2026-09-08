// =============================================================================
// correccion_widgets.dart
// Widgets reutilizables para el flujo de "Solicitar corrección":
//   - showSolicitarCorreccionDialog(): diálogo con textarea + envío
//   - CorreccionBanner: banner amarillo mostrando la solicitud pendiente
//   - correccionActionButton(): botón outline con ícono, uso rápido en AppBar
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

/// Diálogo modal para pedir el motivo y disparar la solicitud.
///
/// [schema]/[table]/[recordId] identifican el registro (viáticos o kilometraje).
/// Devuelve true si la solicitud se envió con éxito.
Future<bool> showSolicitarCorreccionDialog(
  BuildContext context, {
  required String schema,
  required String table,
  required String recordId,
  String titulo = 'Solicitar corrección',
}) async {
  final motivoCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_note, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(titulo, style: const TextStyle(fontSize: 17))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "No puedes editar el registro directamente. Escribe qué necesita "
            "corregirse y un administrador lo revisará.",
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: motivoCtrl,
            decoration: const InputDecoration(
              labelText: "¿Qué hay que corregir?",
              hintText: "Ej.: el kilometraje inicial dice 12500 pero era 12800",
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 4,
            minLines: 3,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 4),
          const Text(
            "Al enviar, este registro queda en estado Corrección Solicitada "
            "hasta que un administrador responda.",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text("Cancelar"),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.send, size: 18),
          label: const Text("Enviar"),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );

  if (ok != true) return false;
  if (!context.mounted) return false;

  final provider = context.read<AppProvider>();
  final success = await provider.solicitarCorreccion(
    schema: schema,
    table: table,
    recordId: recordId,
    motivo: motivoCtrl.text.trim(),
  );

  if (!context.mounted) return success;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success
          ? "Solicitud enviada. Un administrador la revisará."
          : (provider.errorMessage ?? "No se pudo enviar la solicitud")),
      backgroundColor: success ? Colors.green : Colors.red,
    ),
  );
  return success;
}

/// Banner amarillo para mostrar arriba de un detalle cuando ya se pidió corrección.
class CorreccionBanner extends StatelessWidget {
  final String motivo;
  final String? fecha;
  final String? respuestaAdmin;

  const CorreccionBanner({
    super.key,
    required this.motivo,
    this.fecha,
    this.respuestaAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final tieneRespuesta = (respuestaAdmin ?? '').trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tieneRespuesta ? Colors.blue.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tieneRespuesta ? Colors.blue.shade200 : Colors.orange.shade200,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                tieneRespuesta ? Icons.reply : Icons.pending_actions,
                size: 18,
                color: tieneRespuesta ? Colors.blue.shade800 : Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Text(
                tieneRespuesta
                    ? "Corrección procesada"
                    : "Corrección solicitada — en revisión",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: tieneRespuesta ? Colors.blue.shade900 : Colors.orange.shade900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            motivo,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          if (tieneRespuesta) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const Text(
              "Respuesta del administrador:",
              style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(respuestaAdmin!, style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
          if (fecha != null && fecha!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              "Enviado: $fecha",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
