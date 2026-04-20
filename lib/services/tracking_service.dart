import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class TrackingService {
  static final _supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionStream;
  
  bool _isTracking = false;
  bool get isTracking => _isTracking;

  // Stream de la posición actual para la UI local
  final _currentLocationController = StreamController<Position>.broadcast();
  Stream<Position> get currentLocationStream => _currentLocationController.stream;

  /// Inicia el rastreo de ubicación
  Future<void> startTracking({String? activityId}) async {
    if (_isTracking) return;

    // 1. Verificar permisos
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    // 2. Configurar el stream de ubicación
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Notificar cada 10 metros
    );

    _isTracking = true;
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      _handleLocationUpdate(position, activityId);
    });
  }

  /// Detiene el rastreo
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
  }

  /// Maneja cada actualización de ubicación
  void _handleLocationUpdate(Position position, String? activityId) async {
    // 1. Notificar a la UI local
    _currentLocationController.add(position);

    // 2. Persistir en Supabase (Solo si hay un usuario autenticado)
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        await _supabase.schema('visitas').from('ops_tracking').insert({
          'user_id': user.id,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'heading': position.heading,
          'activity_id': activityId,
        });
      } catch (e) {
        debugPrint('Error persistiendo ubicación: $e');
      }
    }
  }

  void dispose() {
    _currentLocationController.close();
    stopTracking();
  }
}
