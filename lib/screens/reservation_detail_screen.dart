import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'vehicle_register_screen.dart';
import 'trip_nav_screen.dart';

class ReservationDetailScreen extends StatelessWidget {
  final Map<String, dynamic> reservation;

  const ReservationDetailScreen({super.key, required this.reservation});

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
        imageUrl =
            "https://awhuzekjpoapamijlvua.supabase.co/storage/v1/object/public/flotilla/$foto";
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
      backgroundColor: const Color(0xFFF8F9FA),
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
                  decoration: BoxDecoration(color: Colors.grey[200]),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(
                            Icons.directions_car,
                            size: 80,
                            color: Colors.grey,
                          ),
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

                  const SizedBox(height: 30),

                  // Location
                  if (reservation['ubicacion'] != null &&
                      reservation['ubicacion'].toString().isNotEmpty) ...[
                    _buildSectionTitle("UBICACIÓN / DESTINO"),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
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
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      reservation['motivo'] ?? "No especificado",
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.black87,
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
                        color: Colors.blue.shade50,
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

  Widget _buildRegistrationButtons(BuildContext context) {
    final supabase = Supabase.instance.client;
    final reservaId = reservation['id'].toString();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase
          .schema('flotilla')
          .from('registros_vehiculos')
          .select()
          .eq('reserva_id', reservaId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Error: ${snapshot.error}",
              style: const TextStyle(color: Colors.red, fontSize: 11),
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
              _buildActionButton(
                context,
                "INICIAR VIAJE (DENTRO DE APP)",
                Icons.navigation,
                Theme.of(context).primaryColor,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TripNavScreen(
                      reservation: reservation,
                      destination: reservation['ubicacion'] ?? "Destino",
                    ),
                  ),
                ),
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

          final DateTime tSalida = DateTime.parse(regSalida['fecha_registro']);
          final DateTime tEntrada = DateTime.parse(
            regEntrada['fecha_registro'],
          );
          final Duration duracion = tEntrada.difference(tSalida);

          final String duracionStr =
              "${duracion.inHours}h ${duracion.inMinutes.remainder(60)}m";

          return Container(
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
              ],
            ),
          );
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
      style: const TextStyle(
        color: Color(0xFF6C757D),
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
