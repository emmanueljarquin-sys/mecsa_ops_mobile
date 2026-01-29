import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

// Usando la misma API Key encontrada en MapPickerScreen
const String kGoogleMapsApiKey = "AIzaSyASZXQg6DuMo2NRbxnhmLssq6lVPaBL8ZU";

class TripNavScreen extends StatefulWidget {
  final Map<String, dynamic> reservation;
  final String destination;

  const TripNavScreen({
    super.key,
    required this.reservation,
    required this.destination,
  });

  @override
  State<TripNavScreen> createState() => _TripNavScreenState();
}

class _TripNavScreenState extends State<TripNavScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  LatLng? _currentPosition;
  Position? _lastRecordedPosition; // Para calcular distancia acumulada
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  bool _isLoading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    print("TripNav: [STEP 1] Starting tracking...");
    try {
      // 1. Verificar servicios y permisos antes de pedir posición
      print("TripNav: [STEP 2] Checking permissions...");
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw "Permiso de ubicación denegado.";
        }
      }

      print("TripNav: [STEP 3] Getting current position...");
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      print(
        "TripNav: [STEP 4] Received position: ${position.latitude}, ${position.longitude}",
      );

      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _lastRecordedPosition = position;
        });
        // Dejar un pequeño respiro para el Mapa antes de cargar ruta
        Future.delayed(const Duration(milliseconds: 500), () => _loadRoute());
      }

      // Escuchar cambios de ubicación
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) async {
        if (mounted) {
          final newPos = LatLng(position.latitude, position.longitude);

          // --- CÁLCULO DE DISTANCIA AUTOMÁTICO ---
          if (_lastRecordedPosition != null) {
            double meters = Geolocator.distanceBetween(
              _lastRecordedPosition!.latitude,
              _lastRecordedPosition!.longitude,
              position.latitude,
              position.longitude,
            );

            // Filtramos pequeñas variaciones del GPS (ruido) menores a 5 metros
            if (meters > 5) {
              final provider = Provider.of<AppProvider>(context, listen: false);
              provider.updateTripDistance(
                widget.reservation['id'].toString(),
                meters / 1000.0, // Acumular en KM
              );
              _lastRecordedPosition = position;
            }
          } else {
            _lastRecordedPosition = position;
          }

          setState(() => _currentPosition = newPos);

          if (_controller.isCompleted) {
            final controller = await _controller.future;
            controller.animateCamera(CameraUpdate.newLatLng(newPos));
          }
        }
      }, onError: (e) => print("TripNav: Location stream error: $e"));
    } catch (e) {
      print("TripNav: [ERROR] Tracking failed: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg =
              "Error de GPS: $e\n\nAsegúrate de tener el GPS encendido.";
        });
      }
    }
  }

  Future<void> _loadRoute() async {
    if (_currentPosition == null) return;
    print("TripNav: [STEP 5] Loading route to ${widget.destination}...");

    try {
      // 1. Obtener coordenadas del destino
      LatLng destCoords;
      if (widget.destination.contains(',')) {
        try {
          final parts = widget.destination.split(',');
          destCoords = LatLng(
            double.parse(parts[0].trim()),
            double.parse(parts[1].trim()),
          );
        } catch (e) {
          throw "Formato de coordenadas inválido.";
        }
      } else {
        print("TripNav: [STEP 6] Geocoding address...");
        final geoUrl =
            "https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(widget.destination)}&key=$kGoogleMapsApiKey";
        final geoRes = await http
            .get(Uri.parse(geoUrl))
            .timeout(const Duration(seconds: 15));
        final geoData = json.decode(geoRes.body);
        if (geoData['status'] == 'OK') {
          final loc = geoData['results'][0]['geometry']['location'];
          destCoords = LatLng(loc['lat'], loc['lng']);
        } else {
          throw "No se encontró el destino (${geoData['status']})";
        }
      }

      // 2. Obtener ruta (Directions API)
      print("TripNav: [STEP 7] Fetching Directions API...");
      final dirUrl =
          "https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=${destCoords.latitude},${destCoords.longitude}&mode=driving&key=$kGoogleMapsApiKey";
      final dirRes = await http
          .get(Uri.parse(dirUrl))
          .timeout(const Duration(seconds: 15));
      final dirData = json.decode(dirRes.body);

      if (dirData['status'] == 'OK') {
        print("TripNav: [STEP 8] Route found successfully!");
        final points = dirData['routes'][0]['overview_polyline']['points'];
        final List<LatLng> polylinePoints = _decodePolyline(points);

        if (mounted) {
          setState(() {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: polylinePoints,
                color: const Color(0xFF0064A5),
                width: 6,
              ),
            );

            _markers.add(
              Marker(
                markerId: const MarkerId('destination'),
                position: destCoords,
                infoWindow: InfoWindow(title: "Destino: ${widget.destination}"),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed,
                ),
              ),
            );

            _isLoading = false;
            _errorMsg = null;
          });

          // Ajustar cámara (SIN BLOQUEAR EL ESTADO DE CARGA)
          try {
            print("TripNav: [STEP 9] Adjusting camera bounds...");
            final controller = await _controller.future.timeout(
              const Duration(seconds: 5),
            );
            _fitBounds(polylinePoints, controller);
          } catch (cameraError) {
            print("TripNav: Warning - Could not adjust camera: $cameraError");
          }
        }
      } else {
        String msg = "Google Maps error: ${dirData['status']}";
        if (dirData['status'] == 'REQUEST_DENIED') {
          msg =
              "API de Google Maps Denegada.\n\nPor favor, asegúrate de tener activada la 'Directions API' en tu consola de Google Cloud.";
        }
        throw msg;
      }
    } catch (e) {
      print("TripNav: [ERROR] Route loading failed: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = e.toString().replaceAll("Exception: ", "");
        });
      }
    }
  }

  // Helper para decodificar polylines de Google
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  void _fitBounds(List<LatLng> points, GoogleMapController controller) {
    double minLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLat = points.first.latitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("En Ruta"),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          if (_currentPosition != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentPosition!,
                zoom: 16,
              ),
              onMapCreated: (c) => _controller.complete(c),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              polylines: _polylines,
              markers: _markers,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            )
          else
            const Center(child: CircularProgressIndicator()),

          if (_isLoading)
            Center(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 8,
                child: const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 3),
                      SizedBox(height: 20),
                      Text(
                        "Trazando la mejor ruta...",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Buscando caminos en tiempo real",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_errorMsg != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  color: Colors.red.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 40,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "No se pudo trazar la ruta",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMsg!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _errorMsg = null;
                            });
                            _loadRoute();
                          },
                          child: const Text("Reintentar"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Botones Flotantes
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: "center",
                  onPressed: () async {
                    if (_currentPosition != null) {
                      final c = await _controller.future;
                      c.animateCamera(
                        CameraUpdate.newLatLngZoom(_currentPosition!, 17),
                      );
                    }
                  },
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Colors.blue),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: "finish",
                  onPressed: () => Navigator.pop(context),
                  backgroundColor: Colors.redAccent,
                  label: const Text(
                    "FINALIZAR VIAJE",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.stop),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
