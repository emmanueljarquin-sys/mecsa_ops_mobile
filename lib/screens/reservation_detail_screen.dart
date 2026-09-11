import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_image.dart';
import '../utils/mensajes_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:gal/gal.dart';
import '../providers/app_provider.dart';
import '../services/offline_service.dart';
import '../services/ruta_pdf_service.dart';
import '../widgets/correccion_widgets.dart';
import 'vehicle_register_screen.dart';
import 'trip_nav_screen.dart';

class ReservationDetailScreen extends StatelessWidget {
  final Map<String, dynamic> reservation;
  /// Historial: solo información (reserva, salida y entrada), sin acciones.
  final bool soloLectura;

  const ReservationDetailScreen({super.key, required this.reservation, this.soloLectura = false});

  @override
  Widget build(BuildContext context) {
    final vehiculo = reservation['vehiculos'] is Map
        ? reservation['vehiculos']
        : {};
    final marca = vehiculo['marca'] ?? '';
    final modelo = vehiculo['modelo'] ?? 'Vehículo';
    final nombreVehiculo = "$marca $modelo".trim().isNotEmpty
        ? "$marca $modelo"
        : "Reserva #${reservation['id']}";
    final placa = vehiculo['placa'] ?? 'Sin placa';

    // Image logic (Standardized)
    String? imageUrl;
    final dynamic foto = vehiculo['foto'];
    if (foto != null) {
      if (foto is String && foto.startsWith('http')) {
        imageUrl = foto;
      } else if (foto is Map && foto['url'] != null) {
        imageUrl = foto['url'];
      } else if (foto is String) {
        imageUrl = Supabase.instance.client.storage
            .from('flotilla')
            .getPublicUrl(foto);
      }
    }

    final estado = (reservation['estado'] ?? 'Pendiente')
        .toString()
        .toUpperCase();

    // Status colors
    Color statusColor = Colors.orange;
    if (estado.contains('CONFIRM') || estado.contains('APROB')) {
      statusColor = Colors.green;
    }
    if (estado.contains('RECHAZ') || estado.contains('CANCEL')) {
      statusColor = Colors.red;
    }

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: const Text('Detalles de Reserva'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Image Card
            Stack(
              children: [
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(color: AppColors.of(context).surfaceVariant),
                  child: imageUrl != null
                      ? CachedImage(
                          imageUrl,
                          fit: BoxFit.cover,
                          fallbackIcon: Icons.directions_car,
                          fallbackSize: 80,
                        )
                      : const Icon(
                          Icons.directions_car,
                          size: 80,
                          color: Colors.grey,
                        ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      estado,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Plate
                  Text(
                    nombreVehiculo,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Placa: $placa",
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).primaryColor.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  // BOTONES DE REGISTRO
                  if (estado != 'PENDIENTE' &&
                      estado != 'RECHAZADA' &&
                      estado != 'CANCELADA') ...[
                    const Divider(height: 40),
                    _buildSectionTitle("REGISTRO DE USO"),
                    const SizedBox(height: 12),
                    _buildRegistrationButtons(context),
                    const SizedBox(height: 30),
                  ],

                  // --- Botón Cancelar Reserva: solo si futura y aún cancelable ---
                  if (!soloLectura &&
                      (estado == 'PENDIENTE' || estado.contains('APROB')) &&
                      _puedeCancelar(reservation)) ...[
                    _buildCancelButton(context),
                    const SizedBox(height: 24),
                  ],

                  _buildSectionTitle("ITINERARIO"),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.calendar_today,
                    "Salida",
                    _formatDate(reservation['fecha_salida']),
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.calendar_today,
                    "Regreso",
                    _formatDate(reservation['fecha_regreso']),
                    color: Colors.green,
                  ),

                  // Horas de control (para el colaborador que hizo la reserva)
                  if (reservation['created_at'] != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.event_available,
                      "Reservada el",
                      _formatDate(reservation['created_at']?.toString()),
                      color: Colors.indigo,
                    ),
                  ],
                  if (reservation['fecha_aprobacion'] != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.verified,
                      "Aprobada el",
                      _formatDate(reservation['fecha_aprobacion']?.toString()),
                      color: Colors.teal,
                    ),
                  ],

                  const SizedBox(height: 30),

                  // Location
                  if (reservation['ubicacion'] != null &&
                      reservation['ubicacion'].toString().isNotEmpty) ...[
                    _buildSectionTitle("UBICACIÓN / DESTINO"),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.of(context).surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.of(context).surfaceVariant),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.map, color: Colors.redAccent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              reservation['ubicacion']?.toString().contains(
                                        '|',
                                      ) ==
                                      true
                                  ? reservation['ubicacion'].toString().split(
                                      '|',
                                    )[1]
                                  : (reservation['ubicacion'] ??
                                        "Sin ubicación"),
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.of(context).textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],

                  // Motivo
                  _buildSectionTitle("MOTIVO DEL VIAJE"),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.of(context).surfaceVariant),
                    ),
                    child: Text(
                      reservation['motivo'] ?? "No especificado",
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: AppColors.of(context).textPrimary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Admin Comments
                  if (reservation['comentarios'] != null &&
                      reservation['comentarios'].toString().isNotEmpty) ...[
                    _buildSectionTitle("COMENTARIOS DEL ADMINISTRADOR"),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.blue.withValues(alpha: 0.18) : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Text(
                        reservation['comentarios'],
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.blue.shade900,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Cancelar reserva
  // ────────────────────────────────────────────────────────────
  bool _puedeCancelar(Map<String, dynamic> r) {
    final fs = DateTime.tryParse(r['fecha_salida']?.toString() ?? '');
    if (fs == null) return false;
    return fs.isAfter(DateTime.now());
  }

  Widget _buildCancelButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmCancel(context),
        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
        label: const Text(
          "CANCELAR RESERVA",
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.red, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Cancelar reserva?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Esta acción no se puede deshacer. ¿Por qué la cancelas?",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: "Motivo (opcional)",
                border: OutlineInputBorder(),
              ),
              maxLength: 200,
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Volver"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sí, cancelar"),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;

    final provider = context.read<AppProvider>();
    final success = await provider.cancelarReserva(
      reservaId: reservation['id'].toString(),
      motivo: motivoCtrl.text.trim(),
    );

    if (!context.mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Reserva cancelada"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // volver al listado
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? "No se pudo cancelar"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ----- Exportar registro de ruta: PDF + guardar fotos al carrete -----

  Widget _buildExportButtons(
    BuildContext context, {
    required Map<String, dynamic> regSalida,
    required Map<String, dynamic> regEntrada,
    required double kmSalida,
    required double kmEntrada,
    required double kmTotal,
    required DateTime tSalida,
    required DateTime tEntrada,
    required String duracion,
  }) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _exportarPdf(
              context,
              regSalida: regSalida,
              regEntrada: regEntrada,
              kmSalida: kmSalida,
              kmEntrada: kmEntrada,
              kmTotal: kmTotal,
              tSalida: tSalida,
              tEntrada: tEntrada,
              duracion: duracion,
            ),
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text("DESCARGAR PDF DE LA VISITA"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF013483),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _guardarFotos(context, regSalida, regEntrada),
            icon: const Icon(Icons.download, size: 18),
            label: const Text("GUARDAR FOTOS EN LA GALERÍA"),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF013483),
              side: const BorderSide(color: Color(0xFF013483)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportarPdf(
    BuildContext context, {
    required Map<String, dynamic> regSalida,
    required Map<String, dynamic> regEntrada,
    required double kmSalida,
    required double kmEntrada,
    required double kmTotal,
    required DateTime tSalida,
    required DateTime tEntrada,
    required String duracion,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    _mostrarCargando(context, "Generando PDF…");
    try {
      final vehiculo =
          reservation['vehiculos'] is Map ? reservation['vehiculos'] : {};
      final marca = (vehiculo['marca'] ?? '').toString();
      final modelo = (vehiculo['modelo'] ?? 'Vehículo').toString();
      final nombreVehiculo =
          "$marca $modelo".trim().isEmpty ? "Vehículo" : "$marca $modelo".trim();
      final placa = (vehiculo['placa'] ?? 'Sin placa').toString();

      String? conductor;
      final emp = reservation['empleado'];
      if (emp is Map && emp['nombre'] != null) {
        conductor = emp['nombre'].toString();
      }
      conductor ??= reservation['empleado_nombre']?.toString();

      final bytes = await RutaPdfService.construirPdf(
        vehiculo: nombreVehiculo,
        placa: placa,
        destino: _destinoLegible(),
        conductor: conductor,
        fechaSalida: _formatDate(reservation['fecha_salida']),
        fechaRegreso: _formatDate(reservation['fecha_regreso']),
        motivo: (reservation['motivo'] ?? 'No especificado').toString(),
        reservaId: reservation['id'].toString(),
        kmSalida: kmSalida,
        kmEntrada: kmEntrada,
        kmTotal: kmTotal,
        duracion: duracion,
        horaSalida: _hora(tSalida),
        horaEntrada: _hora(tEntrada),
        regSalida: regSalida,
        regEntrada: regEntrada,
      );

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // cerrar loading
      }
      final placaFile = placa.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'visita_${placaFile}_${reservation['id']}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      messenger.showSnackBar(
        SnackBar(content: Text(mensajeError(e, accion: 'generar el PDF'))),
      );
    }
  }

  Future<void> _guardarFotos(
    BuildContext context,
    Map<String, dynamic> regSalida,
    Map<String, dynamic> regEntrada,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final urls = RutaPdfService.urlsDeFotos(regSalida, regEntrada);
    if (urls.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("No hay fotos para guardar.")),
      );
      return;
    }

    // Permiso de galería.
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text("Se necesita permiso para guardar en la galería."),
            ),
          );
          return;
        }
      }
    } catch (_) {}

    if (!context.mounted) {
      return;
    }
    _mostrarCargando(context, "Guardando fotos…");
    int ok = 0;
    for (final u in urls) {
      final bytes = await RutaPdfService.descargarBytes(u);
      if (bytes != null) {
        try {
          await Gal.putImageBytes(bytes, album: 'MecsaOPS');
          ok++;
        } catch (_) {}
      }
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok == urls.length
            ? "$ok fotos guardadas en la galería."
            : "$ok de ${urls.length} fotos guardadas."),
      ),
    );
  }

  void _mostrarCargando(BuildContext context, String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
  }

  String _destinoLegible() {
    final u = reservation['ubicacion']?.toString() ?? '';
    if (u.isEmpty) return 'Sin ubicación';
    final parts = u.split('|');
    return parts.length > 1 ? parts[1] : u;
  }

  String _hora(DateTime d) =>
      "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  /// Aviso amarillo: el registro se hizo sin conexión y está en la cola.
  Widget _avisoPendiente(BuildContext context, String texto) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.orange.withValues(alpha: 0.18) : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_upload_outlined, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.orange.shade100 : Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Resumen de solo lectura cuando falta la salida o la entrada.
  Widget _estadoRegistrosSoloLectura(
      BuildContext context, Map<String, dynamic> regSalida, Map<String, dynamic> regEntrada) {
    final c = AppColors.of(context);
    Widget fila(String etiqueta, Map<String, dynamic> reg) {
      final ok = reg.isNotEmpty;
      final km = reg['kilometraje'];
      final fecha = DateTime.tryParse(reg['fecha_registro']?.toString() ?? '');
      final detalle = ok
          ? [
              if (km != null) '$km km',
              if (fecha != null)
                '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}',
              if (reg['_pendiente'] == true) 'pendiente de subir',
            ].join(' · ')
          : 'No registrada';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.cancel, size: 20, color: ok ? Colors.green : c.textMuted),
            const SizedBox(width: 10),
            Text(etiqueta, style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
            const Spacer(),
            Text(detalle, style: TextStyle(fontSize: 12, color: ok ? c.textSecondary : c.textMuted)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          fila('Salida', regSalida),
          Divider(height: 1, color: c.border),
          fila('Entrada', regEntrada),
        ],
      ),
    );
  }

  Widget _buildRegistrationButtons(BuildContext context) {
    final reservaId = reservation['id'].toString();
    // Escuchar la cola: cuando una operación sube, se reconstruye.
    context.watch<OfflineService>();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: context.read<AppProvider>().getRegistrosReserva(reservaId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              mensajeError(snapshot.error, accion: 'cargar los registros de uso'),
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final regs = snapshot.data ?? [];
        final Map<String, dynamic> regSalida = regs.firstWhere(
          (r) => r['tipo'].toString().toLowerCase() == 'salida',
          orElse: () => {},
        );
        final Map<String, dynamic> regEntrada = regs.firstWhere(
          (r) => r['tipo'].toString().toLowerCase() == 'entrada',
          orElse: () => {},
        );

        final hasSalida = regSalida.isNotEmpty;
        final hasEntrada = regEntrada.isNotEmpty;
        final salidaPendiente = regSalida['_pendiente'] == true;
        final entradaPendiente = regEntrada['_pendiente'] == true;

        // Historial: solo informar qué se registró, sin botones de acción.
        if (soloLectura && !(hasSalida && hasEntrada)) {
          return _estadoRegistrosSoloLectura(context, regSalida, regEntrada);
        }

        if (!hasSalida) {
          return _buildActionButton(
            context,
            "REGISTRAR SALIDA",
            Icons.outbond,
            Theme.of(context).primaryColor,
            () =>
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VehicleRegisterScreen(
                      reservation: reservation,
                      tipo: 'salida',
                    ),
                  ),
                ).then((_) {
                  if (context.mounted) (context as Element).markNeedsBuild();
                }),
          );
        } else if (!hasEntrada) {
          return Column(
            children: [
              if (salidaPendiente)
                _avisoPendiente(context,
                    'Salida registrada sin conexión. Se subirá automáticamente cuando haya internet.'),
              _buildActionButton(
                context,
                "INICIAR VIAJE (DENTRO DE APP)",
                Icons.navigation,
                Theme.of(context).primaryColor,
                () {
                  // --- AUTOMATIZACIÓN DE RASTREO ---
                  context.read<AppProvider>().trackingService.startTracking(
                    activityId: reservaId
                  );

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TripNavScreen(
                        entity: reservation,
                        destination: reservation['ubicacion'] ?? "Destino",
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                context,
                "REGISTRAR ENTRADA (REGRESO)",
                Icons.login,
                Colors.green,
                () =>
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleRegisterScreen(
                          reservation: reservation,
                          tipo: 'entrada',
                        ),
                      ),
                    ).then((_) {
                      if (context.mounted)
                        (context as Element).markNeedsBuild();
                    }),
              ),
            ],
          );
        } else {
          // Both checkout and check-in exist: SHOW SUMMARY
          final double kmSalida = (regSalida['kilometraje'] ?? 0.0).toDouble();
          final double kmEntrada = (regEntrada['kilometraje'] ?? 0.0)
              .toDouble();
          final double kmTotales = kmEntrada - kmSalida;

          final DateTime tSalida =
              DateTime.tryParse(regSalida['fecha_registro']?.toString() ?? '') ??
                  DateTime.now();
          final DateTime tEntrada =
              DateTime.tryParse(regEntrada['fecha_registro']?.toString() ?? '') ??
                  DateTime.now();
          final Duration duracion = tEntrada.difference(tSalida);

          final String duracionStr =
              "${duracion.inHours}h ${duracion.inMinutes.remainder(60)}m";

          return Column(children: [
            if (salidaPendiente || entradaPendiente)
              _avisoPendiente(context, salidaPendiente && entradaPendiente
                  ? 'Salida y entrada registradas sin conexión. Se subirán automáticamente cuando haya internet.'
                  : salidaPendiente
                      ? 'Salida registrada sin conexión. Se subirá automáticamente cuando haya internet.'
                      : 'Entrada registrada sin conexión. Se subirá automáticamente cuando haya internet.'),
            Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade100.withOpacity(0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.stars,
                      color: Theme.of(context).primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "RESUMEN DE VIAJE",
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCol(
                      Icons.timer,
                      "Duración",
                      duracionStr,
                      Colors.blue.shade700,
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.blue.shade100,
                    ),
                    _buildStatCol(
                      Icons.speed,
                      "Inicio (km)",
                      kmSalida.toStringAsFixed(0),
                      Colors.blue.shade700,
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.blue.shade100,
                    ),
                    _buildStatCol(
                      Icons.flag,
                      "Fin (km)",
                      kmEntrada.toStringAsFixed(0),
                      Colors.blue.shade700,
                    ),
                  ],
                ),
                const Divider(height: 24),
                Center(
                  child: Text(
                    "TOTAL RECORRIDO: ${kmTotales.toStringAsFixed(1)} KM",
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Divider(height: 24),
                _buildExportButtons(
                  context,
                  regSalida: regSalida,
                  regEntrada: regEntrada,
                  kmSalida: kmSalida,
                  kmEntrada: kmEntrada,
                  kmTotal: kmTotales,
                  tSalida: tSalida,
                  tEntrada: tEntrada,
                  duracion: duracionStr,
                ),
                // Banners de solicitud ya enviada (si aplica)
                if ((regSalida['solicitud_correccion'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CorreccionBanner(
                    motivo: "SALIDA: ${regSalida['solicitud_correccion']}",
                    fecha: regSalida['fecha_correccion']?.toString().split('.').first,
                    respuestaAdmin: regSalida['respuesta_admin'],
                  ),
                ],
                if ((regEntrada['solicitud_correccion'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  CorreccionBanner(
                    motivo: "ENTRADA: ${regEntrada['solicitud_correccion']}",
                    fecha: regEntrada['fecha_correccion']?.toString().split('.').first,
                    respuestaAdmin: regEntrada['respuesta_admin'],
                  ),
                ],
                // Botones Solicitar corrección (uno por registro, solo si no hay ya solicitud)
                const SizedBox(height: 12),
                Row(
                  children: [
                    if ((regSalida['solicitud_correccion'] ?? '').toString().isEmpty)
                      if (!soloLectura)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_note, size: 18, color: Colors.orange),
                          label: const Text(
                            "Corregir salida",
                            style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.orange, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () async {
                            final ok = await showSolicitarCorreccionDialog(
                              context,
                              schema: 'flotilla',
                              table: 'registros_vehiculos',
                              recordId: regSalida['id'].toString(),
                              titulo: 'Corregir kilometraje de salida',
                            );
                            if (ok && context.mounted) {
                              (context as Element).markNeedsBuild();
                            }
                          },
                        ),
                      ),
                    if ((regSalida['solicitud_correccion'] ?? '').toString().isEmpty &&
                        (regEntrada['solicitud_correccion'] ?? '').toString().isEmpty)
                      const SizedBox(width: 8),
                    if ((regEntrada['solicitud_correccion'] ?? '').toString().isEmpty)
                      if (!soloLectura)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_note, size: 18, color: Colors.orange),
                          label: const Text(
                            "Corregir entrada",
                            style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.orange, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () async {
                            final ok = await showSolicitarCorreccionDialog(
                              context,
                              schema: 'flotilla',
                              table: 'registros_vehiculos',
                              recordId: regEntrada['id'].toString(),
                              titulo: 'Corregir kilometraje de entrada',
                            );
                            if (ok && context.mounted) {
                              (context as Element).markNeedsBuild();
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          ]);
        }
      },
    );
  }

  Widget _buildStatCol(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color.withOpacity(0.7)),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: AppColors.light.textSecondary,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color color = Colors.grey,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1B263B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "-";
    try {
      final dt = DateTime.parse(dateStr);
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateStr;
    }
  }
}
