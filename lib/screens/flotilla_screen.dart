import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_provider.dart';
import 'reservation_form_screen.dart';
import 'reservation_detail_screen.dart';

class FlotillaScreen extends StatelessWidget {
  const FlotillaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final vehicles = provider.vehiculos;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Flotilla',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212529),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReservationFormScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'Reservar',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Section: MIS RESERVAS
              const Text(
                'MIS RESERVAS',
                style: TextStyle(
                  color: Color(0xFF6C757D),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),

              // Dynamic Reservation List
              if (provider.myReservations.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Text(
                    "No tienes reservas activas",
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...provider.myReservations.map((res) {
                  // Extract vehicle data safely
                  final vehiculo = res['vehiculos'] is Map
                      ? res['vehiculos']
                      : {}; // Adjust based on actual API response
                  // If vehiculo is empty, maybe look up in provider.vehiculos by vehicle_id?
                  // For now assuming join works.

                  final marca = vehiculo['marca'] ?? '';
                  final modelo = vehiculo['modelo'] ?? 'Vehículo';
                  final nombreVehiculo = "$marca $modelo".trim();

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

                  final estadoDb = res['estado'] ?? 'Pendiente';
                  String estadoDisplay = estadoDb.toUpperCase();
                  Color badgeColorBg = const Color(
                    0xFFFFF3CD,
                  ); // Default yellow (pending)
                  Color badgeColorText = const Color(0xFF856404);

                  if (estadoDisplay.contains('APROB') ||
                      estadoDisplay.contains('CONFIRM')) {
                    badgeColorBg = const Color(0xFFD1E7DD);
                    badgeColorText = const Color(0xFF0F5132);
                    estadoDisplay = "CONFIRMADA";
                  } else if (estadoDisplay.contains('RECHAZ') ||
                      estadoDisplay.contains('CANCEL')) {
                    badgeColorBg = const Color(0xFFF8D7DA);
                    badgeColorText = const Color(0xFF721C24);
                  }

                  // Date Formatting
                  String fechaDisplay = res['fecha_salida'] ?? '';
                  String horaDisplay = '';
                  try {
                    if (fechaDisplay.isNotEmpty) {
                      final dt = DateTime.parse(fechaDisplay);
                      // Custom simpler format manually or use intl if imported.
                      // Using manual string manipulation to be safe without intl import in this part if unchecked.
                      // Actually main.dart uses intl, so we can assumes it's available?
                      // Safest is to use basic string splitting or DateTime methods.
                      final cDate = "${dt.day}/${dt.month}/${dt.year}";
                      final cTime =
                          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                      fechaDisplay = cDate;
                      horaDisplay = cTime;
                    }
                  } catch (e) {
                    // Fallback to raw string
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.grey.withOpacity(0.1)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ReservationDetailScreen(reservation: res),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          // Image Section
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              bottomLeft: Radius.circular(20),
                            ),
                            child: Image.network(
                              imageUrl ?? 'https://via.placeholder.com/120',
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Container(
                                width: 120,
                                height: 120,
                                color: Colors.grey[300],
                                child: const Icon(Icons.directions_car),
                              ),
                            ),
                          ),
                          // Info Section
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          nombreVehiculo.isNotEmpty
                                              ? nombreVehiculo
                                              : 'Reserva #${res['id']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeColorBg,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          estadoDisplay,
                                          style: TextStyle(
                                            color: badgeColorText,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    vehiculo['placa'] ?? 'Placa pendiente',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Fecha y Hora
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 14,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        fechaDisplay,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF495057),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(
                                        Icons.access_time,
                                        size: 14,
                                        color: Color(0xFFFD7E14),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        horaDisplay,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF495057),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (res['ubicacion'] != null &&
                                      res['ubicacion']
                                          .toString()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.map_outlined,
                                          size: 14,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            res['ubicacion']
                                                    .toString()
                                                    .contains('|')
                                                ? res['ubicacion']
                                                      .toString()
                                                      .split('|')[1]
                                                : res['ubicacion'],
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),

              const SizedBox(height: 32),

              // Section: VEHÍCULOS DISPONIBLES
              const Text(
                'VEHÍCULOS DISPONIBLES',
                style: TextStyle(
                  color: Color(0xFF6C757D),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),

              // Vehicle List
              ...vehicles.map((v) => _VehicleListCard(data: v)).toList(),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleListCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _VehicleListCard({required this.data});

  @override
  Widget build(BuildContext context) {
    bool isAvailable = data['status'] == 'available';

    return GestureDetector(
      onTap: isAvailable
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReservationFormScreen(vehicle: data),
                ),
              );
            }
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "Este vehículo no está disponible (${data['estado']}).",
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.grey.withOpacity(0.1)),
        ),
        child: Opacity(
          opacity: isAvailable ? 1.0 : 0.6,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    data['image'],
                    width: 70,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      width: 70,
                      height: 50,
                      color: Colors.grey[200],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        "${data['plate']} ${data['year'] != '' ? '• ' + data['year'].toString() : ''}",
                        style: TextStyle(color: Colors.blue[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isAvailable
                            ? const Color(0xFF00C853)
                            : const Color(0xFFF44336),
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isAvailable)
                      const Text(
                        "Ocupado",
                        style: TextStyle(fontSize: 8, color: Colors.red),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
