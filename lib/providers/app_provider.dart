import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class AppProvider extends ChangeNotifier {
  int _currentIndex = 0;
  final _supabase = Supabase.instance.client;

  int get currentIndex => _currentIndex;

  // Stats
  int totalVehiculos = 0;
  int inspeccionesPendientes = 0;
  int liquidacionesPendientes = 0;
  int rutasActivas = 0;

  // Data Lists
  List<Map<String, dynamic>> vehiculos = [];
  List<Map<String, dynamic>> gastos = [];
  List<Map<String, dynamic>> visitas = [];
  List<Map<String, dynamic>> reservas = [];
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> myReservations = [];
  String? currentEmployeeId;

  bool isLoading = true;
  String? errorMessage;
  User? get user => _supabase.auth.currentUser;

  AppProvider() {
    _init();
  }

  void _init() {
    _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        fetchData();
      } else if (data.event == AuthChangeEvent.signedOut) {
        // Clear data on logout
        vehiculos = [];
        projects = [];
        notifyListeners();
      }
    });
    fetchData(); // Initial attempt
  }

  Future<bool> signIn(String email, String password) async {
    try {
      isLoading = true;
      notifyListeners();

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Login error: $e");
      errorMessage = "Error al iniciar sesión: ${e.toString()}";
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  void setIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  Future<void> fetchData() async {
    if (user == null) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // 1. First lookup Employee ID (needed for reservations/viaticos filtering)
      await _fetchCurrentEmployeeId();

      // 2. Fetch all data in parallel
      await Future.wait([
        _fetchFlotilla(),
        _fetchViaticos(),
        _fetchRutas(),
        _fetchProjects(),
        _fetchMyReservations(),
      ]);
    } catch (e) {
      debugPrint("Error fetching data: $e");
      errorMessage = "Error de conexión: $e";
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchCurrentEmployeeId() async {
    try {
      if (user?.email == null) return;
      // Using verified table 'Empleados' and column 'email'
      final res = await _supabase
          .from('Empleados')
          .select('id')
          .eq('email', user!.email!)
          .maybeSingle();

      if (res != null) {
        currentEmployeeId = res['id'].toString();
      }
    } catch (e) {
      debugPrint("Error fetching employee ID: $e");
    }
  }

  Future<void> _fetchMyReservations() async {
    try {
      if (currentEmployeeId == null) return;

      // Fetch reservations + joined vehicle data
      // join syntax: '*, vehiculo:vehiculos(*)' if relations exist.
      // If no explicit FK name, try '*, vehiculos(*)' or just fetch unrelated/manual join if needed.
      // Trying 'vehiculos(*)' assuming standard Supabase inferred relation.
      final res = await _supabase
          .schema('flotilla')
          .from('reservas')
          .select('*, vehiculos(*)')
          .eq('empleado_id', currentEmployeeId!)
          .order('fecha_salida', ascending: true);

      myReservations = List<Map<String, dynamic>>.from(res);

      // Post-process to ensure clean structure similar to vehicle list if needed
      // but simpler to just pass raw Map to UI.
    } catch (e) {
      debugPrint("Error fetching my reservations: $e");
      // Fallback: fetch just reservations
      try {
        final res = await _supabase
            .schema('flotilla')
            .from('reservas')
            .select()
            .eq('empleado_id', currentEmployeeId!)
            .order('fecha_salida', ascending: true);
        myReservations = List<Map<String, dynamic>>.from(res);
      } catch (e2) {
        print("Fallback failed: $e2");
      }
    }
  }

  Future<void> _fetchFlotilla() async {
    try {
      // 1. Vehículos
      final resVehiculos = await _supabase
          .schema('flotilla')
          .from('vehiculos')
          .select();

      if (resVehiculos == null) {
        totalVehiculos = 0;
        vehiculos = [];
        return;
      }

      totalVehiculos = (resVehiculos as List).length;

      // Map DB columns to UI expected keys
      vehiculos = (resVehiculos)
          .map((v) {
            // Handle 'foto' which might be JSONB, String, or Null
            String imageUrl = 'https://via.placeholder.com/150';
            final dynamic foto = v['foto'];
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

            return {
              'name':
                  "${v['marca'] ?? ''} ${v['modelo'] ?? 'Vehículo'}", // Safe access
              'id': v['id'].toString(), // Force String
              'plate': v['placa'] ?? 'S/P',
              'year': v['year'] ?? '',
              'status': _mapStatus(v['estado']),
              'image': imageUrl,
              'estado': v['estado'] ?? 'Desconocido',
            };
          })
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint("Error loading flotilla: $e");
      rethrow;
    }
  }

  Future<void> _fetchViaticos() async {
    try {
      final res = await _supabase
          .schema('viaticos')
          .from('liquidaciones')
          .select();
      liquidacionesPendientes = (res as List)
          .where((e) => e['estado'] != 'Aprobado')
          .length;

      gastos = res
          .map(
            (g) => {
              'id': g['id'].toString(),
              'concepto': g['descripcion'] ?? 'Gasto Operativo',
              'monto': (g['total'] ?? 0.0).toDouble(),
              'fecha': g['created_at']?.substring(0, 10) ?? '',
              'estado': g['estado'] ?? 'Pendiente',
            },
          )
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint("Error loading viaticos: $e");
      rethrow;
    }
  }

  Future<void> _fetchRutas() async {
    try {
      final resVisitas = await _supabase
          .schema('rutas')
          .from('visitas')
          .select();
      // Assuming 'rutas' table for count
      final resRutas = await _supabase
          .schema('rutas')
          .from('rutas')
          .select('id');
      rutasActivas = (resRutas as List).length;

      visitas = (resVisitas as List)
          .map(
            (v) => {
              'client': v['cliente'] ?? 'Cliente',
              'project': v['proyecto'] ?? 'Proyecto',
              'address': v['direccion'] ?? 'Ubicación no registrada',
              'date': v['fecha_programada'] ?? '',
              'isCompleted': v['check_in'] != null,
            },
          )
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint("Warning loading rutas (Schema might be missing): $e");
      // Do not rethrow, just keep empty lists so other features work
      visitas = [];
      rutasActivas = 0;
    }
  }

  Future<void> _fetchProjects() async {
    try {
      final res = await _supabase
          .schema('proyectos')
          .from('projects')
          .select('project_id, title'); // Adjust columns as needed

      projects = (res as List)
          .map((p) => {'id': p['project_id'].toString(), 'name': p['title']})
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint("Error loading projects: $e");
      // Don't block app if projects fail
      projects = [];
    }
  }

  Future<bool> createReservation(Map<String, dynamic> reservationData) async {
    try {
      isLoading = true;
      notifyListeners();

      if (user == null) throw "Usuario no autenticado"; // NEW

      // Use cached ID or fetch it // NEW
      if (currentEmployeeId == null) {
        // NEW
        await _fetchCurrentEmployeeId(); // NEW
        if (currentEmployeeId == null) {
          // NEW
          throw "No se encontró perfil de empleado para ${user!.email}"; // NEW
        }
      } // NEW

      final String vehiculoId = reservationData['vehiculo_id'].toString();
      final String startStr = reservationData['fecha_salida'];
      final String endStr = reservationData['fecha_regreso'];

      // Check for overlapping reservations
      // An overlap occurs if: (StartA < EndB) and (EndA > StartB)
      // We look for any existing reservation that satisfies this with the NEW dates.
      // Existing.fecha_salida < New.End AND Existing.fecha_regreso > New.Start

      final overlap = await _supabase
          .schema('flotilla')
          .from('reservas')
          .select('id')
          .eq('vehiculo_id', vehiculoId)
          .neq('estado', 'Cancelada')
          .neq('estado', 'Rechazada')
          .lt('fecha_salida', endStr)
          .gt('fecha_regreso', startStr)
          .limit(1);

      if (overlap.isNotEmpty) {
        throw "El vehículo ya está reservado en ese horario.\nIntenta con otra hora o vehículo.";
      }

      final Map<String, dynamic> data = {
        ...reservationData,
        'empleado_id': currentEmployeeId, // Using cached ID
      };

      await _supabase.schema('flotilla').from('reservas').insert(data);

      // Refresh data
      await Future.wait([
        _fetchFlotilla(),
        _fetchMyReservations(), // NEW
      ]);

      return true;
    } catch (e) {
      debugPrint("Error creating reservation: $e");
      errorMessage = "Error al crear reserva: ${e.toString()}";
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveVehicleRegister({
    required String reservaId,
    required String tipo,
    required double kilometraje,
    required double nivelAceite,
    required double nivelCombustible,
    required String estadoPintura,
    required String estadoLlantas,
    required String estadoInteriores,
    required bool poseeKit,
    required bool poseeRefraccion,
    required bool poseeCompass,
    required Map<String, dynamic> localPhotos, // Map of key -> File path
  }) async {
    try {
      isLoading = true;
      notifyListeners();

      if (user == null) throw "No autenticado";
      if (currentEmployeeId == null) await _fetchCurrentEmployeeId();
      if (currentEmployeeId == null) throw "No se encontró el ID de empleado";

      // 1. Upload photos first
      final Map<String, String> photoUrls = {};
      for (var entry in localPhotos.entries) {
        if (entry.value != null) {
          final url = await _uploadRegisterPhoto(
            entry.value,
            entry.key,
            reservaId,
          );
          if (url != null) photoUrls["foto_${entry.key}"] = url;
        }
      }

      // 2. Insert record
      // Use reservaId directly as UUID string
      final Map<String, dynamic> data = {
        'reserva_id': reservaId,
        'empleado_id': currentEmployeeId,
        'tipo': tipo,
        'kilometraje': kilometraje,
        'nivel_aceite': nivelAceite,
        'nivel_combustible': nivelCombustible,
        'estado_pintura': estadoPintura,
        'estado_llantas': estadoLlantas,
        'estado_interiores': estadoInteriores,
        'posee_kit': poseeKit,
        'posee_refraccion': poseeRefraccion,
        'posee_compass': poseeCompass,
        'ubicacion': '',
        ...photoUrls,
      };

      // 2.5 Get current location if possible
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        data['ubicacion'] = "${pos.latitude},${pos.longitude}";
      } catch (e) {
        debugPrint("Could not get registration location: $e");
      }

      await _supabase
          .schema('flotilla')
          .from('registros_vehiculos')
          .insert(data);

      // Refresh data
      await fetchData();
      return true;
    } catch (e) {
      debugPrint("Error saving vehicle register: $e");
      errorMessage = "Error al guardar registro: $e";
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> _uploadRegisterPhoto(
    dynamic fileSource,
    String name,
    String reservaId,
  ) async {
    try {
      final fileName =
          "register_${reservaId}_${name}_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final path = "registros/$fileName";

      final File file = fileSource is File
          ? fileSource
          : File(fileSource.toString());

      await _supabase.storage
          .from('fotos_registro_vehiculos')
          .upload(path, file);

      return fileName;
    } catch (e) {
      debugPrint("Error uploading photo $name: $e");
      // Rethrow to let saveVehicleRegister catch it and abort insert if critical
      throw "Error subiendo foto $name: $e";
    }
  }

  String _mapStatus(String? dbStatus) {
    if (dbStatus == null || dbStatus == 'EMPTY') return 'available';
    final s = dbStatus.toLowerCase();

    if (s.contains('disponible') || s.contains('empty') || s.contains('activo'))
      return 'available';
    if (s.contains('ocupado') || s.contains('ruta') || s.contains('uso'))
      return 'occupied';

    return 'maintenance';
  }

  // --- Trip Tracking Methods ---
  final Map<String, double> _activeTripDistances =
      {}; // reservaId -> distanceInKm

  void updateTripDistance(String reservaId, double km) {
    _activeTripDistances[reservaId] =
        (_activeTripDistances[reservaId] ?? 0.0) + km;
    notifyListeners();
  }

  double getTripDistance(String reservaId) {
    return _activeTripDistances[reservaId] ?? 0.0;
  }

  void clearTripDistance(String reservaId) {
    _activeTripDistances.remove(reservaId);
    notifyListeners();
  }
}
