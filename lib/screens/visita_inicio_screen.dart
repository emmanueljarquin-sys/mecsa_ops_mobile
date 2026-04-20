import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/location_helper.dart';

const String kMapsKey = "AIzaSyASZXQg6DuMo2NRbxnhmLssq6lVPaBL8ZU";

// ─────────────────────────────────────────────────────────────────
// PANTALLA COMPLETA: WIZARD DE 3 PASOS
// ─────────────────────────────────────────────────────────────────
class VisitaInicioScreen extends StatefulWidget {
  final Map<String, dynamic>? visitaExistente;
  const VisitaInicioScreen({super.key, this.visitaExistente});

  @override
  State<VisitaInicioScreen> createState() => _VisitaInicioScreenState();
}

class _VisitaInicioScreenState extends State<VisitaInicioScreen> {
  int _paso = 1; // 1=Inicio, 2=En Ruta, 3=Finalizar

  // ── Paso 1 ──
  final _odoIniCtrl = TextEditingController();
  File? _fotoInicio;
  Position? _posInicio;
  bool _gettingGps = false;
  bool _iniciando = false;
  String? _visitaId;
  String? _vehiculoId; // Vehículo seleccionado para el kilometraje

  // ── Paso 2 (Tracking) ──
  final Completer<GoogleMapController> _mapCtrl = Completer();
  List<Map<String, dynamic>> _waypoints = [];
  List<LatLng> _polylinePoints = [];
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  LatLng? _currentPos;
  StreamSubscription<Position>? _posStream;
  Timer? _timer;
  int _segundos = 0;

  // ── Paso 3 ──
  final _odoFinCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  File? _fotoFin;
  List<String> _proysSel = [];
  bool _finalizando = false;

  @override
  void initState() {
    super.initState();
    if (widget.visitaExistente != null) {
      _cargarVisitaExistente();
    } else {
      _obtenerGPS();
    }
  }

  void _cargarVisitaExistente() {
    final v = widget.visitaExistente!;
    _visitaId = v['id'].toString();
    _odoIniCtrl.text = v['km_inicial']?.toString() ?? '';
    _vehiculoId = v['vehiculo_id']?.toString();
    
    // Proyectos previos
    if (v['proyectos_visitados'] != null) {
      _proysSel = List<String>.from(v['proyectos_visitados']);
    }

    // Reconstruir Waypoints y Ruta
    if (v['waypoints'] != null) {
      final List rawWps = v['waypoints'] is String 
          ? json.decode(v['waypoints']) 
          : v['waypoints'];
      
      _waypoints = List<Map<String, dynamic>>.from(rawWps);
      _polylinePoints = _waypoints.map((wp) => LatLng(
        (wp['lat'] as num).toDouble(), 
        (wp['lng'] as num).toDouble()
      )).toList();

      if (_polylinePoints.isNotEmpty) {
        _currentPos = _polylinePoints.last;
        _posInicio = Position(
          latitude: _polylinePoints.first.latitude,
          longitude: _polylinePoints.first.longitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      }
    }

    // Calcular segundos transcurridos
    if (v['hora_inicio_dt'] != null) {
      final start = DateTime.tryParse(v['hora_inicio_dt']);
      if (start != null) {
        _segundos = DateTime.now().difference(start).inSeconds;
        if (_segundos < 0) _segundos = 0;
      }
    }

    _paso = 2; // Saltar al mapa
    _iniciarTracking();
    _iniciarTimer();
  }

  @override
  void dispose() {
    _posStream?.cancel();
    _timer?.cancel();
    _odoIniCtrl.dispose();
    _odoFinCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════
  // GPS
  // ══════════════════════════════════════════════════
  Future<void> _obtenerGPS() async {
    setState(() => _gettingGps = true);
    try {
      var perm = await LocationHelper.requestPermissionWithDisclosure(context);
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) throw 'GPS denegado';

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      setState(() => _posInicio = pos);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS: $e'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => _gettingGps = false);
    }
  }

  // ══════════════════════════════════════════════════
  // FOTO
  // ══════════════════════════════════════════════════
  Future<void> _tomarFoto(bool esInicio) async {
    final pic = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );
    if (pic != null && mounted) {
      setState(() {
        if (esInicio) {
          _fotoInicio = File(pic.path);
        } else {
          _fotoFin = File(pic.path);
        }
      });
    }
  }

  // ══════════════════════════════════════════════════
  // PASO 1 → INICIAR VIAJE
  // ══════════════════════════════════════════════════
  Future<void> _iniciarViaje() async {
    final provider = context.read<AppProvider>();
    final empId = provider.currentEmployeeId;
    if (empId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró tu perfil de empleado.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // ── VALIDACIÓN OBLIGATORIA ──
    if (_odoIniCtrl.text.isEmpty || (double.tryParse(_odoIniCtrl.text) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El kilometraje inicial es obligatorio.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_fotoInicio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Es obligatorio tomar la foto del odómetro para iniciar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_vehiculoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Es obligatorio seleccionar un vehículo para el cálculo de kilometraje.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _iniciando = true);

    try {
      final String? id = await provider.startVisitaV2(
        lat: _posInicio?.latitude ?? 0,
        lng: _posInicio?.longitude ?? 0,
        odometroInicial: _odoIniCtrl.text,
        vehiculoId: _vehiculoId!,
        fotoOdometro: _fotoInicio,
      );

      if (id != null) {
        _visitaId = id;
        if (_posInicio != null) {
          _currentPos = LatLng(_posInicio!.latitude, _posInicio!.longitude);
          _waypoints.add({
            'lat': _posInicio!.latitude,
            'lng': _posInicio!.longitude,
            'ts': DateTime.now().toIso8601String(),
          });
        }
        setState(() => _paso = 2);
        _iniciarTracking();
        _iniciarTimer();

        // --- AUTOMATIZACIÓN DE RASTREO ---
        provider.trackingService.startTracking(activityId: _visitaId);
      } else {
        throw provider.errorMessage ?? 'Error al iniciar visita';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  // ══════════════════════════════════════════════════
  // TRACKING GPS EN TIEMPO REAL
  // ══════════════════════════════════════════════════
  void _iniciarTracking() {
    _posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) async {
      final newPt = LatLng(pos.latitude, pos.longitude);
      final wp = {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'ts': DateTime.now().toIso8601String(),
      };

      setState(() {
        _currentPos = newPt;
        _waypoints.add(wp);
        _polylinePoints.add(newPt);
        _polylines = {
          Polyline(
            polylineId: const PolylineId('ruta'),
            points: List.from(_polylinePoints),
            color: Colors.blue,
            width: 5,
          ),
        };
        _markers
          ..removeWhere((m) => m.markerId.value == 'yo')
          ..add(
            Marker(
              markerId: const MarkerId('yo'),
              position: newPt,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
              flat: true,
              rotation: pos.heading,
              anchor: const Offset(0.5, 0.5),
            ),
          );
      });

      // Animar cámara
      if (_mapCtrl.isCompleted) {
        final ctrl = await _mapCtrl.future;
        ctrl.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: newPt,
              zoom: 16,
              tilt: 30,
              bearing: pos.heading,
            ),
          ),
        );
      }

      // Guardar waypoints en BD cada 8 puntos
      if (_waypoints.length % 8 == 0 && _visitaId != null) {
        _guardarWaypoints();
      }
    });
  }

  Future<void> _guardarWaypoints() async {
    if (_visitaId == null) return;
    try {
      final provider = context.read<AppProvider>();
      await provider.updateVisitaWaypointsV2(_visitaId!, _waypoints);
    } catch (_) {}
  }

  void _iniciarTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _segundos++);
    });
  }

  String get _timerDisplay {
    final h = _segundos ~/ 3600;
    final m = (_segundos % 3600) ~/ 60;
    final s = _segundos % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ══════════════════════════════════════════════════
  // PASO 2 → IR A FINALIZACIÓN
  // ══════════════════════════════════════════════════
  void _irAFinalizar() {
    _posStream?.cancel();
    _timer?.cancel();
    _guardarWaypoints();
    setState(() => _paso = 3);
  }

  // ══════════════════════════════════════════════════
  // PASO 3 → FINALIZAR VISITA
  // ══════════════════════════════════════════════════
  Future<void> _finalizarVisita() async {
    if (_visitaId == null) return;
    // ── VALIDACIÓN OBLIGATORIA ──
    if (_odoFinCtrl.text.isEmpty || (double.tryParse(_odoFinCtrl.text) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El kilometraje final es obligatorio.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Buscamos si la visita ya tiene foto en el provider (por si es una reanudación)
    final provider = context.read<AppProvider>();
    final visitaPrevia = provider.visitas.firstWhere(
      (v) => v['id'].toString() == _visitaId,
      orElse: () => {},
    );
    final String? fotoExistente = visitaPrevia['foto_odometro_fin'];

    if (_fotoFin == null && (fotoExistente == null || fotoExistente.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Es obligatorio tomar la foto del odómetro final.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_obsCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las notas de la visita son obligatorias. Describe lo realizado.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _finalizando = true);
    try {
      final result = await provider.finishVisitaV2(
        id: _visitaId!,
        odometroFinal: _odoFinCtrl.text,
        observaciones: _obsCtrl.text,
        proyectosVisitados: _proysSel,
        waypoints: _waypoints,
        fotoOdometroFin: _fotoFin,
      );

      if (result != null) {
        final km = result['km_recorridos'] ?? 0;
        final dur = result['duracion_minutos'] ?? 0;
        final h = dur ~/ 60;
        final m = dur % 60;

        if (mounted) {
          // --- AUTOMATIZACIÓN DE RASTREO ---
          provider.trackingService.stopTracking();

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 32),
                  SizedBox(width: 12),
                  Text('¡Visita Completada!', style: TextStyle(fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow(Icons.timer, 'Duración',
                      h > 0 ? '${h}h ${m}min' : '${m} min'),
                  _summaryRow(Icons.speed, 'Distancia',
                      km is num ? '${km.toStringAsFixed(1)} km' : '$km km'),
                  _summaryRow(Icons.location_on, 'Puntos GPS',
                      '${_waypoints.length} registros'),
                  if (result['monto_pago_km'] != null)
                    _summaryRow(
                        Icons.payments_outlined,
                        'Monto Viático',
                        '₡${(result['monto_pago_km'] as num).toStringAsFixed(0)}',
                        isHighlight: true),
                ],
              ),
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Ver Mis Visitas',
                      style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    Navigator.of(context).pop(); // Cerrar diálogo
                    Navigator.of(context).pop(); // Volver a lista
                  },
                ),
              ],
            ),
          );
        }
      } else {
        throw provider.errorMessage ?? 'Error al finalizar visita';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al finalizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _finalizando = false);
    }
  }

  Widget _summaryRow(IconData icon, String label, String value,
      {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isHighlight ? Colors.green : Colors.blueAccent),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isHighlight ? Colors.green : Colors.black87)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_paso == 1
            ? 'Iniciar Visita'
            : _paso == 2
                ? 'En Ruta — $_timerDisplay'
                : 'Finalizar Visita'),
        backgroundColor: _paso == 2
            ? const Color(0xFF166534)
            : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: _paso == 1
          ? _buildPaso1()
          : _paso == 2
              ? _buildPaso2()
              : _buildPaso3(),
    );
  }

  // ─────────────────────────────────────────────────
  // PASO 1 UI
  // ─────────────────────────────────────────────────
  void _mostrarRegistroVehiculo() {
    final aliasCtrl = TextEditingController();
    int? antiguedad;
    String? tipo;
    String? combustible;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Registrar Nuevo Vehículo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _label('Alias (Ej: Hilux Gris)', isRequired: true),
              TextFormField(
                controller: aliasCtrl,
                decoration: _inputDeco('Nombre del vehículo'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Antigüedad (Años)', isRequired: true),
                        DropdownButtonFormField<int>(
                          decoration: _inputDeco('Años'),
                          items: List.generate(20, (i) => i).map((i) {
                            return DropdownMenuItem(value: i, child: Text('$i'));
                          }).toList(),
                          onChanged: (v) => antiguedad = v,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Combustible', isRequired: true),
                        DropdownButtonFormField<String>(
                          decoration: _inputDeco('Tipo'),
                          items: const [
                            DropdownMenuItem(value: 'gasolina', child: Text('Gasolina')),
                            DropdownMenuItem(value: 'gasolina a', child: Text('Gasol A (<=1.6)')),
                            DropdownMenuItem(value: 'gasolina b', child: Text('Gasol B (>1.6)')),
                            DropdownMenuItem(value: 'diesel', child: Text('Diesel')),
                            DropdownMenuItem(value: 'electrico', child: Text('Elec')),
                          ],
                          onChanged: (v) => combustible = v,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _label('Tipo de Vehículo', isRequired: true),
              DropdownButtonFormField<String>(
                decoration: _inputDeco('Tipo'),
                items: const [
                  DropdownMenuItem(value: 'rural', child: Text('Rural')),
                  DropdownMenuItem(value: 'liviano', child: Text('Liviano')),
                  DropdownMenuItem(value: 'motocicleta', child: Text('Moto')),
                  DropdownMenuItem(value: 'hibrido', child: Text('Híbrido')),
                  DropdownMenuItem(value: 'electrico', child: Text('Eléctrico')),
                ],
                onChanged: (v) => tipo = v,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (aliasCtrl.text.isEmpty || antiguedad == null || tipo == null || combustible == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Cargue todos los campos')));
                      return;
                    }
                    final ok = await context.read<AppProvider>().registerPersonalVehicle(
                      alias: aliasCtrl.text,
                      antiguedad: antiguedad!,
                      tipo: tipo!,
                      combustible: combustible!,
                    );
                    if (ok && mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehículo registrado')));
                    }
                  },
                  child: const Text('Guardar Vehículo', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaso1() {
    final provider = context.watch<AppProvider>();
    final emp = provider.currentEmployeeData;
    final nombre = emp != null
        ? '${emp['nombre'] ?? ''} ${emp['apellido'] ?? ''}'.trim()
        : 'No detectado';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stepper visual
          _buildStepper(1),
          const SizedBox(height: 24),

          // Empleado auto-detectado
          _card(
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF1E293B),
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('RESPONSABLE',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      Text(nombre,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
                Icon(Icons.check_circle,
                    color: emp != null ? Colors.green : Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // GPS Status
          _card(
            child: Row(
              children: [
                Icon(
                  _posInicio != null ? Icons.location_on : Icons.location_off,
                  color:
                      _posInicio != null ? Colors.green : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('UBICACIÓN GPS',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      Text(
                        _gettingGps
                            ? 'Detectando...'
                            : _posInicio != null
                                ? '${_posInicio!.latitude.toStringAsFixed(4)}, ${_posInicio!.longitude.toStringAsFixed(4)}'
                                : 'Sin GPS — toca para reintentar',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _posInicio != null
                                ? Colors.black87
                                : Colors.orange),
                      ),
                    ],
                  ),
                ),
                if (_gettingGps)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blue),
                    onPressed: _obtenerGPS,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Selección de Vehículo
          _label('VEHÍCULO PERSONAL', isRequired: true),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _vehiculoId,
                  isExpanded: true,
                  decoration: _inputDeco('Seleccione su vehículo'),
                  items: provider.personalVehicles.map((v) {
                    return DropdownMenuItem<String>(
                      value: v['id'].toString(),
                      child: Text(v['alias'] ?? 'Vehículo'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _vehiculoId = val),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: _mostrarRegistroVehiculo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Odómetro
          _label('ODÓMETRO INICIAL (km)', isRequired: true),
          TextFormField(
            controller: _odoIniCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDeco('Ej: 45230'),
          ),
          const SizedBox(height: 20),

          // Foto odómetro
          _label('FOTO DEL ODÓMETRO', isRequired: true),
          GestureDetector(
            onTap: () => _tomarFoto(true),
            child: _fotoInicio != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(_fotoInicio!,
                        height: 180, width: double.infinity,
                        fit: BoxFit.cover),
                  )
                : Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.blue.shade200,
                          width: 2,
                          style: BorderStyle.solid),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 40, color: Colors.blue),
                        SizedBox(height: 8),
                        Text('Toca para fotografiar el odómetro',
                            style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _iniciando ? null : _iniciarViaje,
              icon: _iniciando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded, color: Colors.white),
              label: Text(
                _iniciando ? 'Iniciando...' : 'Iniciar Viaje',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // PASO 2 UI: MAPA EN VIVO
  // ─────────────────────────────────────────────────
  Widget _buildPaso2() {
    return Stack(
      children: [
        // Mapa
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentPos ?? const LatLng(14.0, -87.2),
            zoom: 15,
          ),
          onMapCreated: (c) => _mapCtrl.complete(c),
          polylines: _polylines,
          markers: _markers,
          myLocationEnabled: false,
          zoomControlsEnabled: false,
        ),

        // Panel superior con timer
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF166534).withOpacity(0.95),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TIEMPO',
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      Text(_timerDisplay,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('PUNTOS GPS',
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      Text('${_waypoints.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Botón finalizar
        Positioned(
          bottom: 30, left: 24, right: 24,
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _irAFinalizar,
              icon: const Icon(Icons.flag_rounded, color: Colors.white),
              label: const Text('Finalizar Visita',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────
  // PASO 3 UI: FINALIZACIÓN
  // ─────────────────────────────────────────────────
  Widget _buildPaso3() {
    final provider = context.watch<AppProvider>();
    final proyectos = provider.projects;
    final odomIni = double.tryParse(_odoIniCtrl.text) ?? 0;
    final odomFin = double.tryParse(_odoFinCtrl.text) ?? 0;
    final km = odomFin > odomIni ? odomFin - odomIni : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepper(3),
          const SizedBox(height: 20),

          // Resumen auto-calculado
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF334155)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statCard('⏱', _timerDisplay, 'Duración'),
                _statCard('📍', '${_waypoints.length}', 'Puntos GPS'),
                _statCard(
                    '🛣',
                    km > 0 ? '${km.toStringAsFixed(1)} km' : '-- km',
                    'Estimado'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Odómetro final
          _label('ODÓMETRO FINAL (km)', isRequired: true),
          TextFormField(
            controller: _odoFinCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDeco('Ej: 45480'),
            onChanged: (_) => setState(() {}),
          ),
          if (km > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '✅ Km recorridos: ${km.toStringAsFixed(1)} km',
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 20),

          // Foto odómetro final
          _label('FOTO DEL ODÓMETRO FINAL', isRequired: true),
          GestureDetector(
            onTap: () => _tomarFoto(false),
            child: _fotoFin != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(_fotoFin!,
                        height: 160, width: double.infinity,
                        fit: BoxFit.cover),
                  )
                : (context.read<AppProvider>().visitas.firstWhere((v) => v['id'].toString() == _visitaId, orElse: () => {})['foto_odometro_fin'] != null)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          context.read<AppProvider>().visitas.firstWhere((v) => v['id'].toString() == _visitaId)['foto_odometro_fin'],
                          height: 160, width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Center(child: Text('Error al cargar foto previa')),
                        ),
                      )
                    : Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200, width: 2),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 36, color: Colors.redAccent),
                        SizedBox(height: 6),
                        Text('Foto del odómetro final',
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // Proyectos visitados
          _label('PROYECTOS VISITADOS (Múltiple)'),
          if (_proysSel.isNotEmpty)
            Wrap(
              spacing: 8,
              children: _proysSel.map((id) {
                final p = proyectos.firstWhere((element) => element['id'].toString() == id, orElse: () => {'name': id});
                return Chip(
                  label: Text(p['name'] ?? id, style: const TextStyle(fontSize: 12)),
                  onDeleted: () => setState(() => _proysSel.remove(id)),
                  deleteIconColor: Colors.red,
                  backgroundColor: Colors.blue.shade50,
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _mostrarBuscadorProyectos(proyectos),
            icon: const Icon(Icons.search),
            label: const Text('Buscar y Seleccionar Proyectos'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),

          // Observaciones
          _label('OBSERVACIONES / NOTAS'),
          TextFormField(
            controller: _obsCtrl,
            maxLines: 4,
            decoration: _inputDeco(
                'Ejemplo: Se realizó el levantamiento arquitectónico en planta baja y se contactó al encargado.'),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _finalizando ? null : _finalizarVisita,
              icon: _finalizando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white),
              label: Text(
                _finalizando ? 'Guardando...' : 'Confirmar y Cerrar Visita',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // HELPERS UI
  // ─────────────────────────────────────────────────
  Widget _buildStepper(int activo) {
    return Row(
      children: [
        _stepCircle(1, 'Inicio', activo),
        Expanded(
          child: Container(
            height: 3,
            color: activo >= 2 ? Colors.green : Colors.grey.shade300,
          ),
        ),
        _stepCircle(2, 'Ruta', activo),
        Expanded(
          child: Container(
            height: 3,
            color: activo >= 3 ? Colors.green : Colors.grey.shade300,
          ),
        ),
        _stepCircle(3, 'Final', activo),
      ],
    );
  }

  Widget _stepCircle(int num, String label, int activo) {
    final done = num < activo;
    final active = num == activo;
    return Column(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: done
              ? Colors.green
              : active
                  ? const Color(0xFF1E293B)
                  : Colors.grey.shade300,
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : Text('$num',
                  style: TextStyle(
                      color: active ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF1E293B) : Colors.grey)),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: child,
    );
  }

  Widget _statCard(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        Text(label,
            style:
                const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _label(String text, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: RichText(
        text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.blueGrey.shade400,
              letterSpacing: 0.5,
              fontFamily: 'Inter'), // Aseguramos fuente si se usa RichText
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  void _mostrarBuscadorProyectos(List<Map<String, dynamic>> proyectos) {
    String query = "";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = proyectos.where((p) {
            final name = p['name']?.toString().toLowerCase() ?? '';
            final id = p['id']?.toString().toLowerCase() ?? '';
            return name.contains(query.toLowerCase()) || id.contains(query.toLowerCase());
          }).toList();

          return AlertDialog(
            title: const Text('Seleccionar Proyectos'),
            contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            content: SizedBox(
              width: double.maxFinite,
              height: 500,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre o ID...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setDialogState(() => query = v),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        final id = p['id'].toString();
                        final isSel = _proysSel.contains(id);
                        return CheckboxListTile(
                          title: Text(p['name'] ?? id),
                          subtitle: Text('ID: $id'),
                          value: isSel,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) _proysSel.add(id);
                              else _proysSel.remove(id);
                            });
                            setDialogState(() {});
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('LISTO'),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
    );
  }
}
