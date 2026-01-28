import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

// NOTA: El usuario debe configurar su API Key.
const String kGoogleMapsApiKey = "AIzaSyBoqj2bFlP61oWgzjaHC6oZxhNMEOUBf5Y";

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();
  final TextEditingController _searchController = TextEditingController();

  LatLng _lastMapPosition = const LatLng(
    9.9281,
    -84.0907,
  ); // Costa Rica default
  String _selectedAddress = "Seleccione ubicación...";
  List<dynamic> _predictions = [];

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(9.9281, -84.0907),
    zoom: 14.4746,
  );

  void _onCameraMove(CameraPosition position) {
    _lastMapPosition = position.target;
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() => _predictions = []);
      return;
    }

    try {
      final url =
          "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(query)}&key=$kGoogleMapsApiKey&language=es&components=country:cr";
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          setState(() {
            _predictions = data['predictions'];
          });
        }
      }
    } catch (e) {
      debugPrint("Error searching places: $e");
    }
  }

  Future<void> _goToPlace(dynamic prediction) async {
    try {
      final placeId = prediction['place_id'];
      final url =
          "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$kGoogleMapsApiKey&language=es";
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final lat = result['geometry']['location']['lat'];
          final lng = result['geometry']['location']['lng'];

          final controller = await _controller.future;
          controller.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
          );

          setState(() {
            _selectedAddress = prediction['description'] ?? "";
            _predictions = [];
            _searchController.text = _selectedAddress;
          });
        }
      }
    } catch (e) {
      debugPrint("Error getting place details: $e");
    }
  }

  Future<void> _reverseGeocode(LatLng position) async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$kGoogleMapsApiKey&language=es";
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          setState(() {
            _selectedAddress = data['results'][0]['formatted_address'] ?? "";
            _searchController.text = _selectedAddress;
          });
        }
      }
    } catch (e) {
      debugPrint("Error reverse geocoding: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Buscar Ubicación",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0064A5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _initialPosition,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: () => _reverseGeocode(_lastMapPosition),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),

          // Marcador Central
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 35),
              child: Icon(Icons.location_on, color: Colors.red, size: 50),
            ),
          ),

          // Buscador Superior
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Buscar destino...",
                      border: InputBorder.none,
                      icon: const Icon(Icons.search, color: Color(0xFF0064A5)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _predictions = []);
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) => _searchPlaces(val),
                  ),
                ),

                // Lista de Predicciones
                if (_predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _predictions.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading: const Icon(Icons.place, color: Colors.grey),
                          title: Text(_predictions[index]['description'] ?? ""),
                          onTap: () => _goToPlace(_predictions[index]),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Botón Confirmar Selección
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'address': _selectedAddress,
                  'lat': _lastMapPosition.latitude,
                  'lng': _lastMapPosition.longitude,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0064A5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 5,
              ),
              child: const Text(
                "Confirmar Ubicación",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
