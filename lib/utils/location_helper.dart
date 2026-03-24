import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationHelper {
  static Future<LocationPermission> requestPermissionWithDisclosure(BuildContext context) async {
    var perm = await Geolocator.checkPermission();
    
    // Only show disclosure if we don't have permission yet
    if (perm == LocationPermission.denied) {
      // Show Google Play compliant prominent disclosure
      bool? userConsented = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.location_on, color: Colors.blue),
                SizedBox(width: 8),
                Text("Uso de Ubicación"),
              ],
            ),
            content: const Text(
              "MecsaOPS recopila datos de ubicación para permitir el seguimiento de sus rutas, "
              "calcular el kilometraje recorrido y registrar la ubicación de las visitas a clientes, "
              "incluso cuando la aplicación está cerrada o no se está utilizando.\n\n"
              "Por favor, seleccione 'Permitir todo el tiempo' en la siguiente pantalla para que "
              "el rastreo de viaje funcione correctamente.",
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("DENEGAR", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text("ACEPTAR", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );

      if (userConsented == true) {
        // Now ask for the actual Android permission
        perm = await Geolocator.requestPermission();
      } else {
        return LocationPermission.denied;
      }
    }
    return perm;
  }
}
