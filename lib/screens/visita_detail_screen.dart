import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'trip_nav_screen.dart';

class VisitaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> visita;

  const VisitaDetailScreen({super.key, required this.visita});

  @override
  State<VisitaDetailScreen> createState() => _VisitaDetailScreenState();
}

class _VisitaDetailScreenState extends State<VisitaDetailScreen> {
  late Map<String, dynamic> _visita;

  @override
  void initState() {
    super.initState();
    _visita = widget.visita;
  }

  @override
  Widget build(BuildContext context) {
    final double? lat = _visita['lat']?.toDouble();
    final double? lng = _visita['lng']?.toDouble();
    final String estado = (_visita['estado'] ?? 'programada')
        .toString()
        .toLowerCase();

    List<dynamic> combinedPhotos = [];
    if (_visita['fotos'] != null && _visita['fotos'] is List) {
      combinedPhotos.addAll(_visita['fotos'] as List);
    }
    if (_visita['foto_odometro_inicio'] != null && _visita['foto_odometro_inicio'].toString().isNotEmpty) {
      combinedPhotos.add(_visita['foto_odometro_inicio']);
    }
    if (_visita['foto_odometro_fin'] != null && _visita['foto_odometro_fin'].toString().isNotEmpty) {
      combinedPhotos.add(_visita['foto_odometro_fin']);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Detalle de Visita"),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lat != null && lng != null) _buildMap(lat, lng),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatusBadge(estado),
                      Text(
                        _visita['fecha'] ?? '',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _visita['cliente'] ?? 'Sin cliente',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    _visita['direccion'] ?? 'Ubicación no registrada',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),

                  if (_visita['destinos'] != null &&
                      (_visita['destinos'] as List).isNotEmpty) ...[
                    const Text(
                      "RUTA PROGRAMADA",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDestinosTimeline(),
                  ],
                  const Divider(height: 40),

                  _buildSection(
                    "PROYECTO",
                    _visita['proyecto']?['nombre'] ?? 'N/A',
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    "TIPO DE VISITA",
                    _visita['tipo_visita']?.toUpperCase() ?? 'CLIENTE',
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    "NOTAS DEL REPORTE",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Text(
                      _visita['notas'] ?? 'Sin notas registradas.',
                      style: const TextStyle(height: 1.5),
                    ),
                  ),

                  const SizedBox(height: 24),
                  if (combinedPhotos.isNotEmpty) ...[
                    const Text(
                      "FOTOS ADJUNTAS",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPhotoGrid(combinedPhotos),
                  ],

                  const SizedBox(height: 40),
                  if (estado == 'programada')
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: () => _showStartTripDialog(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              "INICIAR VIAJE",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (estado == 'en_curso')
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        children: [
                          _buildActionButton(
                            "VER MAPA / RUTA",
                            Icons.navigation,
                            Colors.blue,
                            () {
                              final List<dynamic> stops =
                                  _visita['destinos'] ?? [];
                              final String mainDest =
                                  _visita['direccion'] ?? "";

                              // Construir waypoints y destino final
                              String finalDestination = mainDest;
                              List<String> waypoints = [];

                              if (stops.isNotEmpty) {
                                waypoints.add(
                                  mainDest,
                                ); // Primera parada es waypoint
                                for (int i = 0; i < stops.length - 1; i++) {
                                  waypoints.add(stops[i]['direccion'] ?? "");
                                }
                                finalDestination =
                                    stops.last['direccion'] ?? "";
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TripNavScreen(
                                    entity: _visita,
                                    destination: finalDestination,
                                    waypoints: waypoints.isNotEmpty
                                        ? waypoints
                                        : null,
                                    multiStops: _getCombinedStops(),
                                    isVisita: true,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildActionButton(
                            "FINALIZAR VISITA",
                            Icons.check_circle_outline,
                            Colors.green,
                            () => _showCompleteDialog(context),
                          ),
                        ],
                      ),
                    ),
                  if (estado == 'completada') ...[
                    _buildSection(
                      "KILOMETRAJE",
                      "Inicial: ${_visita['odometro_inicial'] ?? _visita['km_inicial'] ?? 'N/A'} - Final: ${_visita['odometro_final'] ?? _visita['km_final'] ?? 'N/A'}",
                    ),
                    const SizedBox(height: 16),
                    _buildSection(
                      "DURACIÓN",
                      "${_visita['duracion_minutos'] ?? _visita['duracion'] ?? 'N/A'} minutos",
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(double lat, double lng) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(lat, lng),
          zoom: 15,
        ),
        markers: {
          Marker(markerId: const MarkerId('pos'), position: LatLng(lat, lng)),
        },
        liteModeEnabled: true, // Optimizado para scrolls
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
      ),
    );
  }

  Widget _buildSection(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.blueGrey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String estado) {
    Color color;
    switch (estado) {
      case 'completada':
        color = Colors.green;
        break;
      case 'en_curso':
        color = Colors.blue;
        break;
      case 'cancelada':
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildPhotoGrid(List photos) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        // Manejar tanto String como Map<String, dynamic>
        final raw = photos[index];
        final String url = raw is String
            ? raw
            : (raw is Map ? (raw['url'] ?? raw['path'] ?? '').toString() : '');
        if (url.isEmpty) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );
      },
    );
  }

  void _showStartTripDialog(BuildContext context) {
    final kmController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Iniciar Viaje"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Ingresa el kilometraje actual del vehículo:"),
            const SizedBox(height: 16),
            TextField(
              controller: kmController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Kilometraje Inicial",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (kmController.text.isEmpty) return;
              final provider = context.read<AppProvider>();
              final success = await provider
                  .updateVisita(_visita['id'].toString(), {
                    'estado': 'en_curso',
                    'km_inicial': kmController.text,
                    'hora_inicio': TimeOfDay.now().format(context),
                  });
              if (success && mounted) {
                setState(() {
                  _visita['estado'] = 'en_curso';
                  _visita['km_inicial'] = kmController.text;
                  _visita['hora_inicio_dt'] = DateTime.now()
                      .toIso8601String(); // Para cálculos precisos
                });
                Navigator.pop(context); // Cerrar dialog
                // Navegar automáticamente a la ruta
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) {
                      final List<dynamic> stops = _visita['destinos'] ?? [];
                      final String mainDest = _visita['direccion'] ?? "";

                      String finalDestination = mainDest;
                      List<String> waypoints = [];

                      if (stops.isNotEmpty) {
                        waypoints.add(mainDest);
                        for (int i = 0; i < stops.length - 1; i++) {
                          waypoints.add(stops[i]['direccion'] ?? "");
                        }
                        finalDestination = stops.last['direccion'] ?? "";
                      }

                      return TripNavScreen(
                        entity: _visita,
                        destination: finalDestination,
                        waypoints: waypoints.isNotEmpty ? waypoints : null,
                        multiStops: _getCombinedStops(),
                        isVisita: true,
                      );
                    },
                  ),
                );
              }
            },
            child: const Text("COMENZAR"),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getCombinedStops() {
    List<Map<String, dynamic>> combined = [];
    // Primera parada
    combined.add({
      'direccion': _visita['direccion'],
      'lat': _visita['lat'],
      'lng': _visita['lng'],
      'cliente': _visita['cliente'],
    });
    // Paradas adicionales
    if (_visita['destinos'] != null) {
      combined.addAll(List<Map<String, dynamic>>.from(_visita['destinos']));
    }
    return combined;
  }

  Widget _buildDestinosTimeline() {
    final List<dynamic> stops = _visita['destinos'] ?? [];
    return Column(
      children: [
        _buildTimelineItem(
          "1",
          _visita['direccion'] ?? "Principal",
          cliente: _visita['cliente'] ?? "Principal",
          isFirst: true,
        ),
        ...List.generate(stops.length, (index) {
          final s = stops[index];
          return _buildTimelineItem(
            "${index + 2}",
            s['direccion'] ?? "Parada ${index + 2}",
            cliente: s['cliente'] ?? "Cliente ${index + 2}",
            tipo: s['tipo_visita'],
            proyecto: s['proyecto_nombre'],
            isLast: index == stops.length - 1,
          );
        }),
      ],
    );
  }

  Widget _buildTimelineItem(
    String label,
    String address, {
    required String cliente,
    String? tipo,
    String? proyecto,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 2,
              height: 10,
              color: isFirst
                  ? Colors.transparent
                  : Colors.blue.withOpacity(0.3),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isFirst ? Colors.blue : Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isFirst ? Colors.white : Colors.blue,
                  ),
                ),
              ),
            ),
            Container(
              width: 2,
              height: 30,
              color: isLast ? Colors.transparent : Colors.blue.withOpacity(0.3),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cliente,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  if (tipo != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tipo.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.blueGrey[600],
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (proyecto != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "Proyecto: $proyecto",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showCompleteDialog(BuildContext context) {
    final resultController = TextEditingController();
    final provider = context.read<AppProvider>();

    // --- AUTOMATIZACIÓN ---
    final double distRecorrida = provider.getTripDistance(
      _visita['id'].toString(),
    );
    final double kmInicial =
        double.tryParse(_visita['km_inicial']?.toString() ?? '0') ?? 0;
    final double kmFinalAuto = kmInicial + distRecorrida;
    final kmFinalController = TextEditingController(
      text: kmFinalAuto.toStringAsFixed(1),
    );

    // Cálculo de duración
    int duracionAuto = 0;
    if (_visita['hora_inicio_dt'] != null) {
      final start = DateTime.parse(_visita['hora_inicio_dt']);
      duracionAuto = DateTime.now().difference(start).inMinutes;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Finalizar Visita"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Detalles del cierre de visita:"),
              const SizedBox(height: 16),
              TextField(
                controller: kmFinalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Kilometraje Final (Confirmar)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.speed, color: Colors.blue),
                ),
              ),
              const SizedBox(height: 12),
              _buildSection("Duración Estimada (Auto)", "$duracionAuto min"),
              const SizedBox(height: 12),
              TextField(
                controller: resultController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: "Resultado / Notas finales",
                  hintText: "¿Qué se logró en esta visita?",
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              Consumer<AppProvider>(
                builder: (context, provider, _) {
                  final dist = provider.getTripDistance(
                    _visita['id'].toString(),
                  );
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "Distancia medida por GPS: ${dist.toStringAsFixed(2)} km",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (resultController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Por favor escribe el resultado"),
                  ),
                );
                return;
              }

              final success = await provider
                  .updateVisita(_visita['id'].toString(), {
                    'estado': 'completada',
                    'resultado': resultController.text,
                    'km_final': kmFinalController.text,
                    'duracion': duracionAuto.toString(),
                    'hora_fin': TimeOfDay.now().format(context),
                  });
              if (success && mounted) {
                Navigator.pop(context); // Cerrar dialog
                Navigator.pop(context); // Volver a lista
              }
            },
            child: const Text("FINALIZAR"),
          ),
        ],
      ),
    );
  }
}
