import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart'; // Added flutter_tts import
import '../providers/app_provider.dart';
import 'dart:ui';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;

// Usando la misma API Key encontrada en MapPickerScreen
const String kGoogleMapsApiKey = "AIzaSyASZXQg6DuMo2NRbxnhmLssq6lVPaBL8ZU";

class TripNavScreen extends StatefulWidget {
  final Map<String, dynamic> entity; // Puede ser reserva o visita
  final String destination;
  final bool isVisita;
  final List<String>? waypoints;
  final List<Map<String, dynamic>>? multiStops;

  const TripNavScreen({
    super.key,
    required this.entity,
    required this.destination,
    this.isVisita = false,
    this.waypoints,
    this.multiStops,
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
  List<dynamic> _legs = [];
  int _currentLegIndex = 0;
  List<dynamic> _steps = [];
  int _currentStepIndex = 0;
  String _nextInstruction = "Buscando ruta...";
  String _distanceToNext = "";
  final FlutterTts _tts = FlutterTts();
  BitmapDescriptor? _carIcon;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  double _heading = 0.0;

  @override
  void initState() {
    super.initState();
    _initTts(); // Initialize TTS
    _loadCarIcon(); // Load car icon
    _startTracking(); // Renamed from _getCurrentLocation to keep original logic
    _startCompass(); // Escuchar la brújula
  }

  void _startCompass() {
    _magnetometerSubscription = magnetometerEvents.listen((
      MagnetometerEvent event,
    ) {
      // Calcular el ángulo (azimuth) basado en el magnetómetro
      final double heading = math.atan2(event.y, event.x) * (180 / math.pi);
      // Ajustar para que el 0 sea el norte y los ángulos sean consistentes con el marcador
      final double adjustedHeading = (heading + 90) % 360;

      if ((adjustedHeading - _heading).abs() > 2) {
        // Evitar micro-temblores
        setState(() {
          _heading = adjustedHeading;
          // Si ya existe el marcador, actualizar su rotación inmediatamente
          _updateMarkerRotation();
        });
      }
    });
  }

  void _updateMarkerRotation() {
    if (_currentPosition == null) return;

    _markers.removeWhere((m) => m.markerId.value == 'user_location');
    _markers.add(
      Marker(
        markerId: const MarkerId('user_location'),
        position: _currentPosition!,
        icon:
            _carIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: _heading,
      ),
    );
  }

  // Initialize TTS settings
  Future<void> _initTts() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    await _tts.setLanguage("es-MX");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Las voces ya están cargadas en el provider
    final voices = provider.availableVoices;

    if (voices.isNotEmpty) {
      final savedVoiceName = provider.selectedGpsVoiceName;
      Map<String, String>? voiceToSet;

      if (savedVoiceName != null) {
        try {
          voiceToSet = voices.firstWhere((v) => v['name'] == savedVoiceName);
        } catch (_) {
          voiceToSet = voices.first;
        }
      } else {
        voiceToSet = voices.first;
      }

      if (voiceToSet != null) {
        await _tts.setVoice(voiceToSet);
        if (savedVoiceName == null) {
          provider.setGpsVoice(voiceToSet['name']!);
        }
      }
    }
  }

  void _toggleMute() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final newVal = !provider.isGpsMuted;
    provider.setGpsMute(newVal);
    if (newVal) {
      _tts.stop();
    }
  }

  Future<void> _speak(String text) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isGpsMuted) {
      await _tts.speak(text);
    }
  }

  // Load custom car icon
  Future<void> _loadCarIcon() async {
    final icon = await _createNavigationArrow();
    if (mounted) {
      setState(() {
        _carIcon = icon;
      });
    }
  }

  Future<BitmapDescriptor> _createNavigationArrow() async {
    final PictureRecorder pictureRecorder = PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 100.0;

    // Dibujar la flecha azul tipo Waze/Navigation
    final Paint paint = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.fill;

    final Path path = Path();
    path.moveTo(size / 2, 0); // Punta superior
    path.lineTo(size, size); // Esquina inferior derecha
    path.lineTo(size / 2, size * 0.7); // Hueco inferior central
    path.lineTo(0, size); // Esquina inferior izquierda
    path.close();

    // Sombra sutil
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, paint);

    // Borde blanco fino
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, borderPaint);

    final img = await pictureRecorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final data = await img.toByteData(format: ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
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
          // Add initial user marker
          _markers.add(
            Marker(
              markerId: const MarkerId('user_location'),
              position: _currentPosition!,
              icon:
                  _carIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
              anchor: const Offset(0.5, 0.5), // Center the icon
              flat: true, // Keep the icon flat on the map
              rotation: position.heading, // Rotate based on heading
            ),
          );
        });
        // Dejar un pequeño respiro para el Mapa antes de cargar ruta
        Future.delayed(const Duration(milliseconds: 500), () => _loadRoute());
      }

      // Escuchar cambios de ubicación
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update more frequently for navigation
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
                widget.entity['id'].toString(),
                meters / 1000.0, // Acumular en KM
              );
              _lastRecordedPosition = position;
            }
          } else {
            _lastRecordedPosition = position;
          }

          setState(() {
            _currentPosition = newPos;
            _updateMarkerRotation();
          });

          if (_controller.isCompleted) {
            final controller = await _controller.future;
            controller.animateCamera(CameraUpdate.newLatLng(newPos));
          }

          // --- ACTUALIZAR INSTRUCCIÓN ACTUAL ---
          _updateCurrentInstruction(position);
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
      String locationData = widget.destination;

      if (locationData.contains('|')) {
        final parts = locationData.split('|');
        final coords = parts[0].split(',');
        destCoords = LatLng(
          double.parse(coords[0].trim()),
          double.parse(coords[1].trim()),
        );
      } else if (locationData.contains(',')) {
        final parts = locationData.split(',');
        if (parts.length == 2 &&
            double.tryParse(parts[0].trim()) != null &&
            double.tryParse(parts[1].trim()) != null) {
          destCoords = LatLng(
            double.parse(parts[0].trim()),
            double.parse(parts[1].trim()),
          );
        } else {
          // No son coordenadas, usar geocoding
          destCoords = await _geocodeAddress(locationData);
        }
      } else {
        // No tiene comas ni separador, intentar geocoding directo
        destCoords = await _geocodeAddress(locationData);
      }

      // 2. Obtener ruta (Directions API)
      print("TripNav: [STEP 7] Fetching Directions API...");
      String dirUrl =
          "https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=${destCoords.latitude},${destCoords.longitude}&mode=driving&language=es&key=$kGoogleMapsApiKey";

      if (widget.waypoints != null && widget.waypoints!.isNotEmpty) {
        final String waypointsStr = widget.waypoints!.join('|');
        dirUrl += "&waypoints=$waypointsStr";
      }

      final dirRes = await http
          .get(Uri.parse(dirUrl))
          .timeout(const Duration(seconds: 15));
      final dirData = json.decode(dirRes.body);

      if (dirData['status'] == 'OK') {
        print("TripNav: [STEP 8] Route found successfully!");
        final route = dirData['routes'][0];
        final points = route['overview_polyline']['points'];
        final List<LatLng> polylinePoints = _decodePolyline(points);

        if (mounted) {
          setState(() {
            _legs = route['legs'];
            _currentLegIndex = 0;
            _steps = _legs[0]['steps'];
            _currentStepIndex = 0;
            _currentStepIndex = 0;
            if (_steps.isNotEmpty) {
              _nextInstruction = _cleanHtml(_steps[0]['html_instructions']);
              _distanceToNext = _steps[0]['distance']['text'];

              final provider = Provider.of<AppProvider>(context, listen: false);
              final String? firstName = provider.currentEmployeeData?['nombre'];
              final String? lastName =
                  provider.currentEmployeeData?['apellido'];
              String userName = "Colaborador Mecsa";

              if (firstName != null || lastName != null) {
                userName = "${firstName ?? ''} ${lastName ?? ''}".trim();
              } else {
                userName =
                    provider.currentEmployeeData?['nombre_completo'] ??
                    "Colaborador Mecsa";
              }

              _speak(
                "Bienvenido $userName, iniciaremos el viaje. $_nextInstruction en $_distanceToNext",
              );
            }
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: polylinePoints,
                color: Theme.of(context).primaryColor,
                width: 6,
              ),
            );

            if (widget.multiStops != null) {
              for (var i = 0; i < widget.multiStops!.length; i++) {
                final stop = widget.multiStops![i];
                final stopLat = stop['lat']?.toDouble();
                final stopLng = stop['lng']?.toDouble();
                if (stopLat != null && stopLng != null) {
                  _markers.add(
                    Marker(
                      markerId: MarkerId('stop_$i'),
                      position: LatLng(stopLat, stopLng),
                      infoWindow: InfoWindow(
                        title: stop['cliente'] ?? "Parada ${i + 1}",
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        i == widget.multiStops!.length - 1
                            ? BitmapDescriptor.hueRed
                            : BitmapDescriptor.hueOrange,
                      ),
                    ),
                  );
                }
              }
            } else {
              _markers.add(
                Marker(
                  markerId: const MarkerId('destination'),
                  position: destCoords,
                  infoWindow: InfoWindow(
                    title:
                        "Destino: ${widget.destination.contains('|') ? widget.destination.split('|')[1] : widget.destination}",
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                ),
              );
            }

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

  Future<LatLng> _geocodeAddress(String address) async {
    print("TripNav: [GEOCODE] Geocoding address: $address");
    final url =
        "https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$kGoogleMapsApiKey";
    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);

    if (data['status'] == 'OK') {
      final location = data['results'][0]['geometry']['location'];
      return LatLng(location['lat'], location['lng']);
    } else {
      throw "No se pudo encontrar la ubicación: ${data['status']}";
    }
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
        backgroundColor: const Color(0xFF0F172A),
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
              myLocationEnabled: false, // Managed manually with custom marker
              myLocationButtonEnabled: false,
              polylines: _polylines,
              markers: _markers,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            )
          else
            const Center(child: CircularProgressIndicator()),

          // --- PANEL DE INSTRUCCIONES SUPERIOR ---
          if (!_isLoading && _errorMsg == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.9),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Icon(Icons.navigation, color: Colors.white),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.multiStops != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  "PARADA ${_currentLegIndex + 1} DE ${widget.multiStops!.length}",
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            Text(
                              _nextInstruction,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              "En $_distanceToNext",
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white70),
                        onPressed: _showVoiceSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // --- BOTÓN DE SILENCIO FLOTANTE ---
          if (!_isLoading && _errorMsg == null)
            Consumer<AppProvider>(
              builder: (context, provider, child) {
                return Positioned(
                  right: 20,
                  bottom: 100,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: provider.isGpsMuted
                        ? Colors.red.shade400
                        : Colors.blueAccent,
                    child: Icon(
                      provider.isGpsMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _toggleMute,
                  ),
                );
              },
            ),

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

  void _showVoiceSettings() {
    showDialog(
      context: context,
      builder: (context) => Consumer<AppProvider>(
        builder: (context, provider, child) {
          final voices = provider.availableVoices;
          return AlertDialog(
            title: const Text("Configuración de Voz"),
            content: voices.isEmpty
                ? const Text(
                    "No se encontraron otras voces disponibles en español.",
                  )
                : SizedBox(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: voices.length,
                      itemBuilder: (context, index) {
                        final voice = voices[index];
                        final isSelected =
                            provider.selectedGpsVoiceName == voice['name'];
                        return ListTile(
                          title: Text(voice['name'] ?? 'Voz desconocida'),
                          subtitle: Text(voice['locale'] ?? ''),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Colors.blue)
                              : null,
                          onTap: () async {
                            await provider.setGpsVoice(voice['name']!);
                            await _tts.setVoice(voice);
                            _tts.speak(
                              "Esta es una prueba de la voz seleccionada.",
                            );
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CERRAR"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _updateCurrentInstruction(Position position) {
    if (_steps.isEmpty) return;

    // Verificar si estamos cerca del punto final del paso actual para pasar al siguiente
    final currentStep = _steps[_currentStepIndex];
    final endLoc = currentStep['end_location'];

    double metersToEnd = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      endLoc['lat'],
      endLoc['lng'],
    );

    // Umbral de 30 metros para pasar de paso
    if (metersToEnd < 30) {
      if (_currentStepIndex < _steps.length - 1) {
        final oldIndex = _currentStepIndex;
        setState(() {
          _currentStepIndex++;
          _nextInstruction = _cleanHtml(
            _steps[_currentStepIndex]['html_instructions'],
          );
          _distanceToNext = _steps[_currentStepIndex]['distance']['text'];
        });

        // Hablar si cambió la instrucción
        if (oldIndex != _currentStepIndex) {
          _tts.speak("$_nextInstruction en $_distanceToNext");
        }
      } else if (_currentLegIndex < _legs.length - 1) {
        // Hemos llegado al final del LEG actual (Waypoint)
        final oldLegIndex = _currentLegIndex;
        setState(() {
          _currentLegIndex++;
          _steps = _legs[_currentLegIndex]['steps'];
          _currentStepIndex = 0;
          _nextInstruction = _cleanHtml(_steps[0]['html_instructions']);
          _distanceToNext = _steps[0]['distance']['text'];
        });

        if (oldLegIndex != _currentLegIndex) {
          String stopName = "tu destino intermedio";
          if (widget.multiStops != null &&
              oldLegIndex < widget.multiStops!.length) {
            final stop = widget.multiStops![oldLegIndex];
            stopName = stop['cliente'] ?? stopName;
          }
          _tts.speak(
            "Has llegado a $stopName. Iniciando siguiente tramo hacia $_nextInstruction en $_distanceToNext",
          );
        }
      } else {
        // LLEGADA AL DESTINO FINAL
        String stopName = widget.destination;
        if (widget.multiStops != null && widget.multiStops!.isNotEmpty) {
          stopName = widget.multiStops!.last['cliente'] ?? stopName;
        }
        _tts.speak("Has llegado a tu destino final, $stopName. ¡Buen trabajo!");

        // Evitar que siga entrando aquí
        setState(() {
          _steps = [];
          _nextInstruction = "Llegaste a tu destino";
        });
      }
    } else {
      // Actualizar distancia dinámica
      setState(() {
        _distanceToNext = metersToEnd > 1000
            ? "${(metersToEnd / 1000).toStringAsFixed(1)} km"
            : "${metersToEnd.toInt()} m";
      });
    }
  }

  String _cleanHtml(String html) {
    // Regex simple para quitar etiquetas HTML de Google (ej: <b>, <div>)
    return html.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');
  }

  @override
  void dispose() {
    _tts.stop();
    _magnetometerSubscription?.cancel();
    super.dispose();
  }
}
