import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/app_provider.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<LatLng> _trail = [];
  
  StreamSubscription<Position>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _startLocalTracking();
  }

  void _startLocalTracking() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    
    _locationSubscription = provider.trackingService.currentLocationStream.listen((Position position) {
      final newPos = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _trail.add(newPos);
        
        // Actualizar Marcador
        _markers.clear();
        _markers.add(Marker(
          markerId: const MarkerId('current_pos'),
          position: newPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Mi Ubicación Actual'),
        ));

        // Actualizar Polilínea (Rastro)
        _polylines.clear();
        _polylines.add(Polyline(
          polylineId: const PolylineId('trail'),
          points: _trail,
          color: Colors.blueAccent.withOpacity(0.7),
          width: 5,
        ));
      });

      // Mover cámara
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(newPos),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rastreo en Vivo'),
        actions: [
          IconButton(
            icon: Icon(provider.isTracking ? Icons.stop_circle : Icons.play_arrow),
            color: provider.isTracking ? Colors.red : Colors.green,
            onPressed: () => provider.toggleTracking(),
          )
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(9.9281, -84.0907), // Costa Rica
              zoom: 15,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (controller) => _mapController = controller,
          ),
          if (!provider.isTracking)
            Container(
              color: Colors.black26,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off, size: 48, color: Colors.grey),
                        const SizedBox(height: 10),
                        const Text('El rastreo está desactivado'),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => provider.toggleTracking(),
                          child: const Text('Iniciar Rastreo Estilo Uber'),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }
}
