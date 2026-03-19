import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
  List<Map<String, dynamic>> employees = [];
  List<Map<String, dynamic>> departments =
      []; // Nuevo: Departamentos para registro
  String? currentEmployeeId;
  Map<String, dynamic>?
  currentEmployeeData; // Nuevo: Datos completos del perfil

  RealtimeChannel? _liquidacionesChannel;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  String? _notificationMessage;

  // GPS Audio Preferences
  bool _isGpsMuted = false;
  String? _selectedGpsVoiceName;
  List<Map<String, String>> _availableVoices = [];
  final FlutterTts _tts = FlutterTts();

  bool get isGpsMuted => _isGpsMuted;
  String? get selectedGpsVoiceName => _selectedGpsVoiceName;
  List<Map<String, String>> get availableVoices => _availableVoices;
  // ...
  Future<void> _fetchCurrentEmployeeId() async {
    try {
      if (user?.email == null) return;
      // Fetch completo de datos del empleado
      final res = await _supabase
          .from('Empleados')
          .select()
          .eq('email', user!.email!)
          .maybeSingle();

      if (res != null) {
        if (res['activo'] == false) {
          await _supabase.auth.signOut();
          throw "Cuenta desactivada por un administrador.";
        }
        currentEmployeeId = res['id'].toString();
        currentEmployeeData = res;
        notifyListeners();
      } else {
        // No employee found, currentEmployeeId remains null
      }
    } catch (e) {
      debugPrint("Error fetching employee ID: $e");
      if (e.toString().contains("desactivada")) {
        errorMessage = e.toString();
        rethrow;
      }
    }
  }

  String? get notificationMessage => _notificationMessage;

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
        _unsubscribeFromLiquidaciones(); // Clean up
        notifyListeners();
      }
    });
    _initNotifications();
    _loadGpsPreferences();
    fetchData(); // Initial attempt
  }

  Future<void> _loadGpsPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isGpsMuted = prefs.getBool('gps_muted') ?? false;
    _selectedGpsVoiceName = prefs.getString('gps_voice_name');
    await loadAvailableVoices(); // Load voices as well
    notifyListeners();
  }

  Future<void> loadAvailableVoices() async {
    try {
      final List<dynamic> voices = await _tts.getVoices;
      _availableVoices = voices
          .map((v) => Map<String, String>.from(v))
          .where((v) => v['locale']!.startsWith('es'))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading voices in provider: $e");
    }
  }

  Future<void> setGpsMute(bool value) async {
    _isGpsMuted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gps_muted', value);
    notifyListeners();
  }

  Future<void> setGpsVoice(String name) async {
    _selectedGpsVoiceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gps_voice_name', name);

    // Apply voice to local tts instance if it matches
    try {
      final voice = _availableVoices.firstWhere((v) => v['name'] == name);
      await _tts.setVoice(voice);
    } catch (_) {}

    notifyListeners();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        // Handle click
      },
    );

    // Request Android 13+ permissions
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }

    _saveFcmToken();
  }

  Future<void> _saveFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && currentEmployeeId != null) {
        debugPrint("FCM Token: $token");
        await _supabase
            .from('Empleados')
            .update({'fcm_token': token})
            .eq('id', currentEmployeeId!);
      }
    } catch (e) {
      debugPrint("Error saving FCM token: $e");
    }
  }

  Future<bool> signIn(String email, String password) async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        // Verificar si el empleado está activo
        final empRes = await _supabase
            .from('Empleados')
            .select('activo')
            .eq('email', email)
            .maybeSingle();

        if (empRes != null && empRes['activo'] == false) {
          await _supabase.auth.signOut();
          throw "Su cuenta está pendiente de activación por un administrador.";
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Login error: $e");
      errorMessage = e.toString().contains("pendiente de activación")
          ? e.toString()
          : "Error al iniciar sesión: ${e.toString()}";
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String nombre,
    required String apellido,
    required String telefono,
    required int departamentoId,
    File? photoFile,
  }) async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      // 1. Obtener el último código de empleado para el correlativo (GM-XXX)
      final lastEmployee = await _supabase
          .from('Empleados')
          .select('codigo_empleado')
          .like('codigo_empleado', 'GM-%')
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      int nextCode = 1;
      if (lastEmployee != null && lastEmployee['codigo_empleado'] != null) {
        final lastCodeStr = lastEmployee['codigo_empleado'].toString();
        // Extraer número después del prefijo GM-
        final parts = lastCodeStr.split('-');
        if (parts.length > 1) {
          final numberPart = parts.last;
          final lastCodeNum = int.tryParse(numberPart);
          if (lastCodeNum != null) {
            nextCode = lastCodeNum + 1;
          }
        }
      }
      final String codigoEmpleado = "GM-${nextCode.toString().padLeft(3, '0')}";

      // 2. Registrar en auth.users
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': "$nombre $apellido"},
      );

      if (response.user == null) throw "Error al crear usuario en Auth";

      // 3. Subir foto solo si se proporciona
      String? photoUrl;
      if (photoFile != null) {
        final fileExt = photoFile.path.split('.').last;
        final fileName =
            'register_${response.user!.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        final filePath = 'temp_registration/$fileName';

        await _supabase.storage.from('empleados').upload(filePath, photoFile);
        photoUrl = _supabase.storage.from('empleados').getPublicUrl(filePath);
      }

      // 4. Crear registro en la tabla Empleados
      await _supabase.from('Empleados').insert({
        'codigo_empleado': codigoEmpleado,
        'nombre': nombre,
        'apellido': apellido,
        'email': email,
        'telefono': telefono,
        'departamento': departamentoId,
        'id_user': response.user!.id,
        'activo': false,
        if (photoUrl != null) 'photo': photoUrl,
      });

      // Importante: Cerrar sesión inmediatamente para que no entre a la App
      // hasta que el administrador lo apruebe.
      await _supabase.auth.signOut();

      return true;
    } catch (e) {
      debugPrint("SignUp error: $e");
      errorMessage = "Error al crear cuenta: ${e.toString()}";
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
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Siempre intentar cargar departamentos (necesario para registro)
      await fetchDepartments();

      if (user == null) return;

      // 1. First lookup Employee ID (needed for reservations/viaticos filtering)
      await _fetchCurrentEmployeeId();

      // 2. Fetch all data in parallel
      await Future.wait([
        _fetchFlotilla(),
        _fetchViaticos(),
        _fetchRutas(),
        _fetchProjects(),
        _fetchMyReservations(),
        _fetchEmployees(),
      ]);
    } catch (e) {
      debugPrint("Error fetching data: $e");
      if (user != null) {
        errorMessage = e.toString().contains("desactivada")
            ? e.toString()
            : "Error de conexión: $e";
      }
    } finally {
      isLoading = false;
      notifyListeners();
      if (user != null) _subscribeToLiquidaciones();
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
                // Obtener URL pública desde el cliente para evitar URLs hardcodeadas
                imageUrl = _supabase.storage
                    .from('flotilla')
                    .getPublicUrl(foto);
              }
            }

            return {
              'name':
                  "${v['marca'] ?? ''} ${v['modelo'] ?? 'Vehículo'}", // Safe access
              'id': v['id'].toString(), // Force String
              'plate': v['placa'] ?? 'S/P',
              'year': v['year']?.toString() ?? '',
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
      if (currentEmployeeId == null) return;

      final res = await _supabase
          .schema('viaticos')
          .from('liquidaciones')
          .select()
          .eq('empleado_id', currentEmployeeId!);
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
      if (currentEmployeeId == null) return;

      final resVisitas = await _supabase
          .schema('visitas')
          .from('visitas')
          .select()
          .eq('empleado_id', currentEmployeeId!)
          .order('fecha', ascending: false);

      visitas = List<Map<String, dynamic>>.from(resVisitas);

      // Conteo para el dashboard
      rutasActivas = visitas.where((v) => v['estado'] == 'en_curso').length;
    } catch (e) {
      debugPrint("Error loading visitas: $e");
      visitas = [];
      rutasActivas = 0;
    }
  }

  Future<void> refreshVisitas() async {
    await _fetchRutas();
    notifyListeners();
  }

  Future<bool> createVisita(Map<String, dynamic> visitaData) async {
    try {
      isLoading = true;
      notifyListeners();

      if (currentEmployeeId == null) await _fetchCurrentEmployeeId();

      final data = {...visitaData, 'empleado_id': currentEmployeeId};

      await _supabase.schema('visitas').from('visitas').insert(data);
      await _fetchRutas();
      return true;
    } catch (e) {
      debugPrint("Error creating visita: $e");
      errorMessage = "Error al registrar visita: $e";
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateVisita(String id, Map<String, dynamic> visitaData) async {
    try {
      isLoading = true;
      notifyListeners();

      await _supabase
          .schema('visitas')
          .from('visitas')
          .update(visitaData)
          .eq('id', id);

      await _fetchRutas();
      return true;
    } catch (e) {
      debugPrint("Error updating visita: $e");
      errorMessage = "Error al actualizar visita: $e";
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> uploadVisitaFoto(File file) async {
    try {
      final fileName = "visita_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final path = "visitas/$fileName";

      await _supabase.storage.from('visitas_fotos').upload(path, file);

      final publicUrl = _supabase.storage
          .from('visitas_fotos')
          .getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint("Error uploading visita photo: $e");
      return null;
    }
  }

  Future<void> _fetchProjects() async {
    try {
      final res = await _supabase
          .schema('proyectos')
          .from('projects')
          .select(
            'project_id, title',
          ); // Cambiado a 'title' según lo descubierto

      projects = (res as List)
          .map(
            (p) => {
              'id': p['project_id'].toString(),
              'name': p['title'] ?? 'Sin nombre',
            },
          )
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint("Error loading projects: $e");
      // Don't block app if projects fail
      projects = [];
    }
  }

  Future<void> _fetchEmployees() async {
    try {
      final res = await _supabase
          .from('Empleados')
          .select('id, nombre, apellido')
          .order('nombre', ascending: true);

      employees = (res as List)
          .map((e) {
            final n = e['nombre'] ?? '';
            final a = e['apellido'] ?? '';
            return {
              'id': e['id'],
              'nombre_completo': "$n $a".trim().isNotEmpty
                  ? "$n $a"
                  : "Empleado #${e['id']}",
            };
          })
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint("Error loading employees: $e");
      employees = [];
    }
  }

  Future<void> fetchDepartments() async {
    try {
      final res = await _supabase
          .schema('cms')
          .from('departamento')
          .select('id, nombre')
          .order('nombre', ascending: true);

      departments = List<Map<String, dynamic>>.from(res as List);
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading departments: $e");
      departments = [];
    }
  }

  String getDepartmentName(dynamic id) {
    if (id == null) return "Sin asignar";
    try {
      final deptId = int.tryParse(id.toString());
      if (deptId == null) return id.toString();

      final dept = departments.firstWhere(
        (d) => d['id'].toString() == deptId.toString(),
        orElse: () => {},
      );

      return dept['nombre'] ?? id.toString();
    } catch (e) {
      return id.toString();
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

      // NUEVO: Verificar estado actual del vehículo en la lista local para evitar reservas directas
      try {
        final veh = vehiculos.firstWhere((v) => v['id'] == vehiculoId);
        if (veh['status'] != 'available') {
          throw "Este vehículo ya no está disponible (${veh['estado']}).";
        }
      } catch (e) {
        if (e is String) rethrow;
        // Si no está en la lista local, tal vez es nuevo, procedemos con cautela o ignoramos
      }

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

  void clearNotificationMessage() {
    _notificationMessage = null;
    notifyListeners();
  }

  void _unsubscribeFromLiquidaciones() {
    if (_liquidacionesChannel != null) {
      _supabase.removeChannel(_liquidacionesChannel!);
      _liquidacionesChannel = null;
    }
  }

  void _subscribeToLiquidaciones() {
    if (currentEmployeeId == null) {
      debugPrint("Realtime: No hay ID de empleado para suscribirse.");
      return;
    }
    if (_liquidacionesChannel != null) {
      debugPrint("Realtime: Canal ya existente, ignorando suscripción.");
      return;
    }

    debugPrint(
      "Realtime: Intentando suscribir a changes para empleado $currentEmployeeId en viaticos.liquidaciones...",
    );

    try {
      _liquidacionesChannel = _supabase
          .channel('public:liquidaciones_user_$currentEmployeeId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'viaticos',
            table: 'liquidaciones',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'empleado_id',
              value: currentEmployeeId!,
            ),
            callback: (payload) {
              debugPrint(
                "Realtime: EVENTO RECIBIDO! Payload: ${payload.toString()}",
              );
              final newVal = payload.newRecord;
              debugPrint("Realtime: Nuevo estado: ${newVal['estado']}");

              if (newVal['estado'] == 'aprobada' ||
                  newVal['estado'] == 'rechazada') {
                _notificationMessage =
                    "Tu liquidación ha sido ${newVal['estado']}";
                _showLocalNotification("IMPORTANTE", _notificationMessage!);
                _fetchViaticos();
                notifyListeners();
              }
            },
          )
          .subscribe((status, error) {
            debugPrint("Realtime Status: $status");
            if (error != null) debugPrint("Realtime Error: $error");
          });
    } catch (e) {
      debugPrint("Error subscribing to realtime: $e");
    }
  }

  Future<void> _showLocalNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'channel_liquidaciones',
      'Liquidaciones',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecond, // Unique ID
      title,
      body,
      details,
    );
  }

  Future<void> updateProfilePhoto(File imageFile) async {
    try {
      if (currentEmployeeId == null) {
        debugPrint("❌ No hay currentEmployeeId");
        return;
      }

      debugPrint(
        "📸 Iniciando actualización de foto para empleado: $currentEmployeeId",
      );
      isLoading = true;
      notifyListeners();

      final fileExt = imageFile.path.split('.').last;
      final fileName =
          'profile_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = '$currentEmployeeId/$fileName';

      debugPrint("📁 Subiendo archivo: $filePath");

      // 1. Upload to Supabase Storage
      await _supabase.storage
          .from('empleados')
          .upload(
            filePath,
            imageFile,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      debugPrint("✅ Archivo subido exitosamente");

      // 2. Get Public URL
      final String publicUrl = _supabase.storage
          .from('empleados')
          .getPublicUrl(filePath);

      debugPrint("🔗 URL pública generada: $publicUrl");

      // 3. Update DB
      debugPrint("💾 Actualizando base de datos...");
      final response = await _supabase
          .from('Empleados')
          .update({'photo': publicUrl})
          .eq('id', currentEmployeeId!)
          .select();

      debugPrint("✅ Respuesta de actualización DB: $response");

      // 4. Update Local
      if (currentEmployeeData != null) {
        currentEmployeeData!['photo'] = publicUrl;
        debugPrint("✅ Estado local actualizado");
      }

      _notificationMessage = "Foto de perfil actualizada";
      notifyListeners();

      debugPrint("🎉 Proceso completado exitosamente");
    } catch (e) {
      debugPrint("❌ Error updating profile photo: $e");
      errorMessage = "Error al actualizar foto: $e";
      notifyListeners();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
