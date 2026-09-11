import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/app_logger.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/liquidaciones_local.dart';
import '../services/liquidaciones_service.dart';
import '../models/liquidacion.dart';
import '../services/offline_service.dart';
import '../utils/mensajes_error.dart';
import '../services/reservas_local.dart';
import '../services/vehiculos_local.dart';
import '../services/imagenes_cache.dart';
import '../services/sync_service.dart';
import '../services/tracking_service.dart';

/// Resultado de clasificar una excepción relacionada con la sesión.
enum _SesionError { ninguno, red, invalida }

class AppProvider extends ChangeNotifier {
  int _currentIndex = 0;
  final _supabase = Supabase.instance.client;
  final _trackingService = TrackingService();

  TrackingService get trackingService => _trackingService;

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
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> companies = [];
  List<Map<String, dynamic>> employees = []; // Lista general de empleados
  List<Map<String, dynamic>> personalVehicles = []; // Vehículos personales del vendedor

  // ── Estado de carga / caché ─────────────────────────────────────
  /// Error de la última carga general (null si la última carga fue bien).
  /// Lo muestra ConnectionBanner. Distinto de errorMessage (acciones puntuales).
  String? loadError;
  /// Última vez que fetchData() terminó bien, o fecha de la caché si aún no.
  DateTime? lastSyncAt;
  /// Nombres de consultas que fallaron en la carga actual (las que no relanzan).
  final List<String> _fallosCarga = [];
  // ── Estado de sesión ────────────────────────────────────────────
  /// La sesión guardada ya no sirve (JWT vencido/rechazado) pero todavía hay
  /// refresh token: HomeScreen muestra un modal con "Renovar" / "Cerrar sesión".
  bool sessionExpired = false;
  /// Aviso para LoginScreen tras un cierre de sesión forzado.
  String? loginNotice;
  bool _renovandoSesion = false;
  bool _sesionInvalidada = false;
  bool get renovandoSesion => _renovandoSesion;

  /// Hay algo que mostrar (de red o de caché).
  bool get hasCachedData =>
      vehiculos.isNotEmpty ||
      myReservations.isNotEmpty ||
      visitas.isNotEmpty ||
      gastos.isNotEmpty;

  String? currentEmployeeId;
  Map<String, dynamic>?
  currentEmployeeData; // Nuevo: Datos completos del perfil

  // ── Flags de acceso administrativo ─────────────────────────────
  // El "modo Administración" en la app se muestra a quien tenga acceso
  // a la web (OPS en sistemas_acceso). Dentro, cada acción respeta las
  // reglas de rol que ya valida el servidor.
  bool _isWebAdmin = false;          // ve la sección Administración
  bool _isRoleAdmin = false;         // rol Administrador/SuperAdmin/admin
  bool _isContabilidad = false;      // rol Contabilidad
  bool _isResponsable = false;       // responsable de ≥1 departamento

  // Vistas/módulos permitidos según rol_permisos (por ROL, igual que la web).
  Set<String> _allowedViews = {};
  // Permisos POR PERSONA (tokens en Empleados.sistemas_acceso, en MAYÚSCULA).
  List<String> _sistemas = [];

  bool get isWebAdmin => _isWebAdmin;
  bool get isRoleAdmin => _isRoleAdmin;
  bool get isContabilidad => _isContabilidad;
  bool get isResponsable => _isResponsable;

  /// ¿El usuario puede ver un módulo?
  /// - Admin (Administrador/SuperAdmin) ve todo.
  /// - Por ROL: si rol_permisos del rol tiene el slug (página Roles).
  /// - Por PERSONA: si sistemas_acceso tiene el token (slug en MAYÚSCULA, página Usuarios).
  bool canViewModule(String slug) =>
      _isRoleAdmin ||
      _allowedViews.contains(slug) ||
      _sistemas.contains(slug.toUpperCase());

  /// Módulo de Auditorías de Vehículos (permiso 'auditorias' en rol_permisos).
  bool get canAudit => canViewModule('auditorias');

  // ── Funciones del modo Administración ───────────────────────────────────
  // Admin (Administrador/SuperAdmin) ve todo. El resto solo si tiene el
  // permiso configurado por rol en la web (rol_permisos), igual que Auditorías.
  // Excepción: liquidaciones también las ven contabilidad y responsables
  // (los responsables solo las de su departamento — lo valida el servidor).
  bool get canApproveLiquidaciones =>
      _isRoleAdmin || _isContabilidad || _isResponsable || _allowedViews.contains('aprobar_liquidaciones');
  bool get canApproveReservas => canViewModule('aprobar_reservas');
  bool get canProcesarCorrecciones => canViewModule('procesar_correcciones');
  bool get canDesbloquear => canViewModule('desbloquear_reservas');

  /// ¿Tiene al menos una función administrativa? (para mostrar el botón).
  bool get hasAdminAccess =>
      canApproveLiquidaciones || canApproveReservas || canProcesarCorrecciones || canDesbloquear;

  RealtimeChannel? _liquidacionesChannel;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  String? _notificationMessage;

  // GPS Audio Preferences
  bool _isGpsMuted = false;
  String? _selectedGpsVoiceName;
  List<Map<String, String>> _availableVoices = [];
  final FlutterTts _tts = FlutterTts();
  
  // App Update State
  String? _updateUrl;
  bool _forceUpdate = false;
  String? get updateUrl => _updateUrl;
  bool get forceUpdate => _forceUpdate;

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
          .select('id, codigo_empleado, nombre, apellido, email, telefono, activo, photo, id_rol, fcm_token, rol, chat_role, sistemas_acceso, departamento')
          .ilike('email', user!.email!)
          .maybeSingle();

      if (res != null) {
        if (res['activo'] == false) {
          await _supabase.auth.signOut();
          throw "Cuenta desactivada por un administrador.";
        }
        _applyEmployeeBase(res);

        // ¿Es responsable de algún departamento de viáticos?
        try {
          final resp = await _supabase
              .from('viaticos_responsables_departamento')
              .select('id')
              .eq('empleado_id', currentEmployeeId as Object)
              .limit(1);
          _isResponsable = (resp as List).isNotEmpty;
        } catch (_) {
          _isResponsable = false;
        }

        // Permisos por módulo del rol (mismo origen que la web: rol_permisos).
        try {
          final rolName = (res['rol'] ?? '').toString();
          if (rolName.isNotEmpty) {
            final perms = await _supabase
                .from('rol_permisos')
                .select('vista_slug, puede_ver')
                .eq('rol_nombre', rolName);
            _allowedViews = {
              for (final p in perms as List)
                if (p['puede_ver'] == true) p['vista_slug'].toString()
            };
          } else {
            _allowedViews = {};
          }
        } catch (_) {
          _allowedViews = {};
        }

        // Caché del perfil para arrancar sin conexión con el mismo empleado
        // y los mismos permisos.
        cache.put('perfil', {
          'empleado': res,
          'isResponsable': _isResponsable,
          'allowedViews': _allowedViews.toList(),
        });

        notifyListeners();
      } else {
        // No employee found, currentEmployeeId remains null
        log.w('auth', 'No se encontró empleado para el correo de la sesión',
            data: {'email': user?.email});
        _isWebAdmin = false;
        _isRoleAdmin = false;
        _isContabilidad = false;
        _isResponsable = false;
        _allowedViews = {};
        _sistemas = [];
      }
    } catch (e, st) {
      log.e('auth', 'Falló la consulta del empleado', error: e, stack: st);
      if (e.toString().contains("desactivada")) {
        errorMessage = e.toString();
        rethrow;
      }
      _detectarSesionExpirada('empleado', e);
    }
  }

  /// Aplica id, datos y flags derivados del registro de Empleados.
  /// Compartido por la carga en línea y la carga desde caché.
  void _applyEmployeeBase(Map<String, dynamic> res) {
    currentEmployeeId = res['id'].toString();
    currentEmployeeData = res;

    // ── Calcular flags administrativos ──
    final rol = (res['rol'] ?? '').toString().toLowerCase().trim();
    _isRoleAdmin = ['administrador', 'admin', 'superadmin', 'superadministrador']
        .contains(rol);
    _isContabilidad = rol == 'contabilidad';

    final List sistemas = (res['sistemas_acceso'] as List?) ?? [];
    // Permisos POR PERSONA (tokens en sistemas_acceso, ej. 'AUDITORIAS').
    _sistemas = sistemas.map((e) => e.toString().toUpperCase()).toList();
    // Acceso a la web = tiene OPS entre sus sistemas
    _isWebAdmin = sistemas.contains('OPS') || _isRoleAdmin;
  }

  /// Carga desde la caché local lo último que se vio, para que la app tenga
  /// datos aunque no haya conexión. Se llama antes del primer fetchData().
  Future<void> _loadFromCache() async {
    if (user == null) return;
    final sw = Stopwatch()..start();
    try {
      final perfil = (await cache.get('perfil'))?.asMap();
      if (perfil != null && perfil['empleado'] is Map) {
        _applyEmployeeBase(Map<String, dynamic>.from(perfil['empleado']));
        _isResponsable = perfil['isResponsable'] == true;
        _allowedViews = ((perfil['allowedViews'] as List?) ?? [])
            .map((e) => e.toString())
            .toSet();
      }

      Future<List<Map<String, dynamic>>> lista(String k) async =>
          (await cache.get(k))?.asList() ?? [];

      final results = await Future.wait([
        lista('vehiculos'),
        lista('reservas'),
        lista('gastos'),
        lista('visitas'),
        lista('proyectos'),
        lista('empleados'),
        lista('departamentos'),
        lista('empresas'),
        lista('vehiculosPersonales'),
      ]);
      if (results[0].isNotEmpty) {
        vehiculos = results[0];
        totalVehiculos = vehiculos.length;
      }
      if (results[1].isNotEmpty) myReservations = results[1];
      // La tabla `reservas` de SQLite manda sobre la caché JSON.
      final reservasSql = await ReservasLocal.instance.listar(currentEmployeeId);
      if (reservasSql.isNotEmpty) myReservations = reservasSql;
      if (results[2].isNotEmpty) {
        gastos = results[2];
        liquidacionesPendientes =
            gastos.where((e) => e['estado'] != 'Aprobado').length;
      }
      if (results[3].isNotEmpty) {
        visitas = results[3];
        rutasActivas = visitas.where((v) => v['estado'] == 'en_curso').length;
      }
      if (results[4].isNotEmpty) projects = results[4];
      if (results[5].isNotEmpty) employees = results[5];
      if (results[6].isNotEmpty) departments = results[6];
      if (results[7].isNotEmpty) companies = results[7];
      if (results[8].isNotEmpty) personalVehicles = results[8];
      // La tabla `vehiculos` de SQLite manda sobre la caché JSON.
      final vehSql = await VehiculosLocal.instance.listar(currentEmployeeId);
      if (vehSql.isNotEmpty) personalVehicles = vehSql;

      lastSyncAt ??= await cache.lastUpdated(['vehiculos', 'reservas']);
      log.i('cache', 'Datos cargados desde caché', data: {
        'ms': sw.elapsedMilliseconds,
        'vehiculos': vehiculos.length,
        'reservas': myReservations.length,
        'perfil': perfil != null,
        'ultimaSync': lastSyncAt?.toIso8601String(),
      });
      notifyListeners();
    } catch (e, st) {
      log.w('cache', 'No se pudo cargar la caché', error: e);
      debugPrint('$st');
    }
  }

  // ── Manejo de sesión expirada ───────────────────────────────────
  /// Distingue "falló por red" (mantener sesión, usar caché) de "el servidor
  /// rechazó la sesión" (hay que renovar o volver a entrar).
  static _SesionError _clasificarErrorSesion(Object e) {
    if (e is AuthRetryableFetchException) return _SesionError.red;
    if (e is AuthException) {
      final sc = e.statusCode ?? '';
      if (sc.startsWith('5')) return _SesionError.red;
      return _SesionError.invalida; // 400/401/403, sesión ausente, JWT inválido
    }
    if (e is PostgrestException) {
      final c = e.code ?? '';
      final m = e.message.toLowerCase();
      if (c == 'PGRST301' || c == '401' || m.contains('jwt')) {
        return _SesionError.invalida;
      }
      return _SesionError.ninguno;
    }
    final s = e.toString().toLowerCase();
    if (s.contains('jwt expired') || s.contains('invalid jwt')) {
      return _SesionError.invalida;
    }
    return _SesionError.ninguno;
  }

  /// Marca la sesión como expirada (dispara el modal en HomeScreen).
  void _marcarSesionExpirada(String origen, Object e) {
    _sesionInvalidada = true;
    if (sessionExpired) return;
    sessionExpired = true;
    log.w('auth', 'Sesión rechazada por el servidor',
        data: {'origen': origen}, error: e);
    notifyListeners();
  }

  /// Si una excepción es de sesión inválida, marca el estado. Devuelve true
  /// si lo era (para que quien llama no la trate como error de red).
  bool _detectarSesionExpirada(String origen, Object e) {
    if (_clasificarErrorSesion(e) != _SesionError.invalida) return false;
    _marcarSesionExpirada(origen, e);
    return true;
  }

  /// Intenta renovar la sesión con el refresh token. Devuelve true si quedó
  /// renovada. Si el servidor rechaza el refresh token, gotrue cierra la
  /// sesión solo y la app vuelve al login con [loginNotice].
  Future<bool> renovarSesion({bool silencioso = false}) async {
    if (_renovandoSesion) return false;
    _renovandoSesion = true;
    if (!silencioso) notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final res = await _supabase.auth
          .refreshSession()
          .timeout(const Duration(seconds: 12));
      final ok = res.session != null;
      log.i('auth', ok ? 'Sesión renovada' : 'refreshSession sin sesión', data: {
        'ms': sw.elapsedMilliseconds,
        'expira': res.session?.expiresAt,
      });
      if (ok) {
        sessionExpired = false;
        _sesionInvalidada = false;
        loadError = null;
        notifyListeners();
        if (!silencioso) fetchData();
      }
      return ok;
    } catch (e, st) {
      final kind = _clasificarErrorSesion(e);
      if (kind == _SesionError.invalida) {
        log.e('auth', 'El servidor rechazó el refresh token',
            data: {'ms': sw.elapsedMilliseconds}, error: e, stack: st);
        _sesionInvalidada = true;
        loginNotice = 'Tu sesión expiró. Volvé a iniciar sesión.';
        // gotrue normalmente ya cerró la sesión; si no, lo hacemos nosotros.
        if (user != null) {
          try {
            await _supabase.auth.signOut();
          } catch (_) {}
        }
      } else {
        log.w('auth', 'No se pudo renovar la sesión (red/timeout)',
            data: {'ms': sw.elapsedMilliseconds}, error: e);
        if (!silencioso) {
          errorMessage =
              'No se pudo renovar la sesión. Revisá la conexión e intentá de nuevo.';
        }
        connectivity.checkInternet(force: true);
      }
      return false;
    } finally {
      _renovandoSesion = false;
      notifyListeners();
    }
  }

  /// Al arrancar con sesión guardada: si el token ya venció, renovarlo antes
  /// de cargar datos. Sin red se mantiene la sesión y se usa la caché.
  Future<void> _verificarSesionAlArrancar() async {
    final s = _supabase.auth.currentSession;
    if (s == null) return;
    if (!s.isExpired) return;
    log.i('auth', 'Token vencido al arrancar; intentando renovar',
        data: {'expiraba': s.expiresAt});
    await renovarSesion(silencioso: true);
  }

  /// Registra una consulta que falló pero no detiene la carga (mantiene los
  /// datos anteriores / de caché). fetchData() lo refleja en loadError.
  void _fallo(String nombre, Object e) {
    _fallosCarga.add(nombre);
    log.w('fetchData', 'Consulta "$nombre" falló; se mantienen datos previos',
        error: e);
  }

  String? get notificationMessage => _notificationMessage;

  bool firebaseAvailable;
  bool isLoading = true;
  String? errorMessage;
  User? get user => _supabase.auth.currentUser;

  AppProvider({this.firebaseAvailable = false}) {
    _init();
  }

  void _init() {
    log.setUser(user?.email);
    cache.setScope(user?.email);
    log.i('auth', 'Provider iniciado', data: {
      'sesionPersistida': user != null,
      'email': user?.email,
      'tokenExpira': _supabase.auth.currentSession?.expiresAt,
    });
    _supabase.auth.onAuthStateChange.listen((data) async {
      log.setUser(data.session?.user.email ?? user?.email);
      log.i('auth', 'Evento de sesión: ${data.event.name}', data: {
        'email': data.session?.user.email,
        'tokenExpira': data.session?.expiresAt,
      });
      if (data.event == AuthChangeEvent.signedIn) {
        loginNotice = null;
        sessionExpired = false;
        _sesionInvalidada = false;
        cache.setScope(data.session?.user.email ?? user?.email);
        await _loadFromCache();
        fetchData();
      } else if (data.event == AuthChangeEvent.tokenRefreshed) {
        // El refresh automático funcionó: si había modal de sesión, cerrarlo.
        if (sessionExpired) {
          sessionExpired = false;
          _sesionInvalidada = false;
          notifyListeners();
          fetchData();
        }
      } else if (data.event == AuthChangeEvent.signedOut) {
        // Si el cierre lo provocó un refresh rechazado (gotrue cierra solo),
        // explicar en el login por qué.
        if (_sesionInvalidada) {
          loginNotice ??= 'Tu sesión expiró. Volvé a iniciar sesión.';
        }
        sessionExpired = false;
        _sesionInvalidada = false;
        _unsubscribeFromLiquidaciones(); // Clean up
        final empSaliente = currentEmployeeId;
        _clearData();
        await cache.clearScope();
        if (empSaliente != null) {
          await ReservasLocal.instance.limpiarEmpleado(empSaliente);
          await VehiculosLocal.instance.limpiarEmpleado(empSaliente);
          await LiquidacionesLocal.instance.limpiarEmpleado(empSaliente);
        }
        notifyListeners();
      }
    }, onError: (e, st) {
      final kind = _clasificarErrorSesion(e);
      if (kind == _SesionError.invalida) {
        // gotrue ya emitió (o va a emitir) signedOut; dejar el aviso listo.
        _sesionInvalidada = true;
        log.e('auth', 'Refresh de sesión rechazado por el servidor',
            error: e, stack: st);
      } else {
        log.w('auth', 'Refresh de sesión falló por red; se mantiene la sesión',
            error: e);
      }
    });

    if (firebaseAvailable) {
      _initNotifications();
    }

    _loadGpsPreferences();
    _checkAppVersion(); // Check for updates

    // Al recuperar internet real: refrescar datos y vaciar la cola offline.
    _wasOnline = connectivity.isOnline;
    connectivity.addListener(_onConectividadCambio);
    // Cuando la cola sube algo, refrescar la lista afectada.
    OfflineService.instance.onOperacionSubida = _onOperacionOfflineSubida;
    // Cuando termina una copia de seguridad (manual o diaria), recargar lo
    // que bajó a SQLite.
    SyncService.instance.addListener(_onSyncCambio);
    SyncService.instance.cargarPrefs();
    // Primero lo guardado (instantáneo, funciona sin red); luego verificar
    // que el token siga vigente y por último la red.
    _loadFromCache()
        .whenComplete(_verificarSesionAlArrancar)
        .whenComplete(fetchData);
  }

  bool _wasOnline = true;
  bool _syncEstabaCorriendo = false;

  void _onSyncCambio() {
    final corriendo = SyncService.instance.isRunning;
    if (_syncEstabaCorriendo && !corriendo && user != null) {
      _loadFromCache().then((_) => refreshSilent());
    }
    _syncEstabaCorriendo = corriendo;
  }

  void _onConectividadCambio() {
    final online = connectivity.isOnline;
    if (online && !_wasOnline && user != null) {
      log.i('conectividad', 'Internet recuperado: resincronizando datos');
      OfflineService.instance.flush();
      refreshSilent();
    }
    _wasOnline = online;
  }

  void _onOperacionOfflineSubida(String type, Map<String, dynamic> op) {
    switch (type) {
      case 'liquidacion':
      case 'factura':
        _fetchViaticos().then((_) => notifyListeners()).catchError((_) {});
        break;
      case 'visita_crear':
      case 'visita_inicio':
      case 'visita_waypoints':
      case 'visita_fin':
        _fetchRutas().then((_) => notifyListeners());
        break;
      case 'registro_vehiculo':
        refreshSilent();
        break;
    }
  }

  /// Limpia todo el estado de datos al cerrar sesión.
  void _clearData() {
    vehiculos = [];
    gastos = [];
    visitas = [];
    reservas = [];
    projects = [];
    myReservations = [];
    employees = [];
    personalVehicles = [];
    currentEmployeeId = null;
    currentEmployeeData = null;
    totalVehiculos = 0;
    liquidacionesPendientes = 0;
    rutasActivas = 0;
    loadError = null;
    lastSyncAt = null;
    _isWebAdmin = false;
    _isRoleAdmin = false;
    _isContabilidad = false;
    _isResponsable = false;
    _allowedViews = {};
    _sistemas = [];
  }

  Future<void> _checkAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await http.get(
        Uri.parse('https://grupomecsa.net/ops/api/check_version.php'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final config = data['data'];
          final minBuildNumber = config['min_version_code'] as int;

          log.i('app', 'Versión verificada', data: {
            'build': currentBuildNumber,
            'minBuild': minBuildNumber,
            'forceUpdate': config['force_update'],
          });
          if (currentBuildNumber < minBuildNumber) {
            _notificationMessage =
                config['message'] ?? "Hay una nueva versión disponible.";
            _updateUrl = config['update_url'];
            _forceUpdate = config['force_update'] ?? false;
            notifyListeners();
          }
        }
      } else {
        log.w('app', 'check_version respondió ${response.statusCode}');
      }
    } catch (e, st) {
      log.w('app', 'No se pudo verificar la versión', error: e);
      debugPrint("Error checking app version: $e\n$st");
    }
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
    if (!firebaseAvailable || currentEmployeeId == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
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
            .ilike('email', email)
            .maybeSingle();

        if (empRes != null && empRes['activo'] == false) {
          await _supabase.auth.signOut();
          throw "Su cuenta está pendiente de activación por un administrador.";
        }
        return true;
      }
      return false;
    } catch (e, st) {
      log.e('auth', 'Login falló', data: {'email': email}, error: e, stack: st);
      errorMessage = e.toString().contains("pendiente de activación")
          ? e.toString()
          : mensajeError(e, accion: 'iniciar sesión');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      final response = await http.post(
        Uri.parse('https://grupomecsa.net/ops/api/request_password_reset.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Reset password error: $e");
      errorMessage = mensajeError(e, accion: 'enviar el correo de recuperación');
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
    required String empresaId,
    File? photoFile,
  }) async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      // 1. Registrar en auth.users
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': "$nombre $apellido"},
      );

      if (response.user == null) throw "Error al crear usuario en Auth";
      final String userId = response.user!.id;

      // 2. Subir foto solo si se proporciona
      String? photoUrl;
      if (photoFile != null) {
        try {
          final fileExt = photoFile.path.split('.').last;
          final fileName =
              'register_${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
          final filePath = 'temp_registration/$fileName';

          await _supabase.storage.from('empleados').upload(filePath, photoFile);
          photoUrl = _supabase.storage.from('empleados').getPublicUrl(filePath);
        } catch (e) {
          debugPrint("Upload foto falló (sigo sin foto): $e");
        }
      }

      // 3. Crear el Empleado vía endpoint PHP (usa service_role para saltar RLS).
      //    NOTA: hacer el INSERT desde Flutter con el cliente del usuario recién
      //    creado falla por RLS — el JWT aún no está confirmado/autorizado para
      //    INSERT en Empleados. El endpoint corre con service_role, autorizado.
      final empResp = await http.post(
        Uri.parse('https://grupomecsa.net/ops/api/register_employee_mobile.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_user'     : userId,
          'nombre'      : nombre,
          'apellido'    : apellido,
          'email'       : email,
          'telefono'    : telefono,
          'departamento': departamentoId,
          'empresa_id'  : empresaId,
          if (photoUrl != null) 'photo': photoUrl,
        }),
      );

      Map<String, dynamic> empBody;
      try {
        empBody = jsonDecode(empResp.body) as Map<String, dynamic>;
      } catch (_) {
        empBody = {'success': false, 'error': 'Respuesta inválida del servidor'};
      }

      if (empResp.statusCode < 200 || empResp.statusCode >= 300 ||
          empBody['success'] != true) {
        // El INSERT en Empleados falló. El auth user ya está creado, pero
        // sin Empleado asociado. Cerramos sesión y reportamos el error
        // claro al usuario para que reintente o contacte soporte.
        await _supabase.auth.signOut();
        throw empBody['error']?.toString() ??
            "No se pudo crear el registro de empleado (HTTP ${empResp.statusCode})";
      }

      // 4. Cerrar sesión inmediatamente para que no entre a la App
      //    hasta que el administrador lo apruebe.
      await _supabase.auth.signOut();

      return true;
    } catch (e) {
      debugPrint("SignUp error: $e");
      errorMessage = mensajeError(e, accion: 'crear la cuenta');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _trackingService.stopTracking();
    log.i('auth', 'Cierre de sesión solicitado');
    await _supabase.auth.signOut();
    // La caché del usuario se borra en el handler de signedOut.
  }

  // Tracking Controls
  bool get isTracking => _trackingService.isTracking;

  Future<void> toggleTracking({String? activityId}) async {
    if (isTracking) {
      _trackingService.stopTracking();
    } else {
      await _trackingService.startTracking(activityId: activityId);
    }
    notifyListeners();
  }

  void setIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  /// Tiempo máximo por consulta de la carga general. Antes no había límite y
  /// con Wi-Fi cautivo o señal débil la app se quedaba "cargando" sin aviso.
  static const Duration _queryTimeout = Duration(seconds: 20);

  /// Ejecuta una consulta de fetchData con timeout y registro de duración.
  Future<T> _consulta<T>(String nombre, Future<T> Function() body) =>
      log.time('fetchData', nombre, () => body().timeout(
            _queryTimeout,
            onTimeout: () => throw TimeoutException(
                '$nombre tardó más de ${_queryTimeout.inSeconds} s'),
          ));

  /// Mensaje corto y entendible para el banner según el tipo de error.
  static String _describirError(Object e) => mensajeError(e);

  Future<void> fetchData() async {
    isLoading = true;
    errorMessage = null;
    _fallosCarga.clear();
    notifyListeners();
    final sw = Stopwatch()..start();
    log.i('fetchData', 'Inicio', data: {
      'sesion': user != null,
      'online': connectivity.isOnline,
      'enCache': hasCachedData,
    });

    try {
      // Siempre intentar cargar departamentos y empresas (necesario para registro)
      await Future.wait([
        _consulta('departamentos', fetchDepartments),
        _consulta('empresas', fetchCompanies),
      ]);

      if (user == null) return;

      // 1. Empleado (necesario para filtrar reservas/viáticos/visitas).
      //    Si ya está resuelto en memoria (sesión abierta o caché SQLite) no
      //    bloquea: se refresca en paralelo con el resto. Solo se espera
      //    cuando no hay ningún id conocido.
      final bool empleadoConocido = currentEmployeeId != null;
      if (!empleadoConocido) {
        await _consulta('empleado', _fetchCurrentEmployeeId);
        if (currentEmployeeId == null) {
          _fallo('empleado',
              'No se pudo resolver el empleado de ${user?.email}; reservas, viáticos y visitas no se cargarán');
        }
      }

      // 2. Fetch all data in parallel
      await Future.wait([
        if (empleadoConocido) _consulta('empleado', _fetchCurrentEmployeeId),
        _consulta('vehiculos', _fetchFlotilla),
        _consulta('viaticos', _fetchViaticos),
        _consulta('rutas', _fetchRutas),
        _consulta('proyectos', _fetchProjects),
        _consulta('reservas', _fetchMyReservations),
        _consulta('empleados', _fetchEmployees),
        _consulta('vehiculosPersonales', fetchPersonalVehicles),
      ]);

      // Precalentar la caché del formulario de liquidaciones (personal y
      // últimos proyectos) para poder crear liquidaciones sin conexión.
      // Corre en segundo plano; no bloquea ni cuenta como fallo de carga.
      LiquidacionesService.getEmpleados().catchError((_) => <Empleado>[]);
      LiquidacionesService.getProyectos().catchError((_) => <Proyecto>[]);

      if (_fallosCarga.isEmpty) {
        loadError = null;
        lastSyncAt = DateTime.now();
      } else {
        loadError =
            'No se pudieron actualizar: ${_fallosCarga.join(', ')}. '
            'Se muestran los datos guardados.';
        connectivity.checkInternet(force: true);
      }
      log.i('fetchData', 'Completo', data: {
        'ms': sw.elapsedMilliseconds,
        'vehiculos': vehiculos.length,
        'reservas': myReservations.length,
        'proyectos': projects.length,
        'fallos': _fallosCarga,
      });
    } catch (e, st) {
      log.e('fetchData', 'Falló la carga general',
          data: {'ms': sw.elapsedMilliseconds}, error: e, stack: st);
      if (user != null) {
        final desactivada = e.toString().contains("desactivada");
        errorMessage = desactivada ? e.toString() : mensajeError(e, accion: 'cargar los datos');
        loadError = desactivada ? e.toString() : _describirError(e);
        if (!desactivada && _detectarSesionExpirada('fetchData', e)) {
          loadError = 'La sesión expiró. Renovála o volvé a iniciar sesión.';
        } else {
          // Sondear internet para que el banner distinga "sin internet" de
          // "error del servidor".
          connectivity.checkInternet(force: true);
        }
      }
    } finally {
      isLoading = false;
      notifyListeners();
      if (user != null) _subscribeToLiquidaciones();
    }
  }

  /// Refresco SILENCIOSO (sin spinner de pantalla completa). Se llama al volver
  /// la app a primer plano para reflejar cambios hechos desde la web —p.ej. una
  /// reserva que ya fue aprobada— sin interrumpir lo que el usuario está viendo.
  Future<void> refreshSilent() async {
    if (user == null || currentEmployeeId == null) return;
    try {
      await Future.wait([
        _fetchMyReservations(),
        _fetchViaticos(),
        _fetchRutas(),
      ]);
      notifyListeners();
    } catch (e, st) {
      log.w('fetchData', 'refreshSilent falló', error: e);
      debugPrint("refreshSilent error: $e\n$st");
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
          .order('fecha_salida', ascending: false);

      // Mostrar próximas + recientes (últimos 60 días). Antes el filtro era
      // fecha_regreso > now, que ocultaba ~93% de las reservas: casi todas son
      // del mismo día y desaparecían al pasar la hora de regreso, así que los
      // usuarios "no veían las reservas hechas por ellos".
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      myReservations = List<Map<String, dynamic>>.from(res)
          .where((r) {
            final fechaRegreso = DateTime.tryParse(r['fecha_regreso'] ?? '');
            return fechaRegreso == null || fechaRegreso.isAfter(cutoff);
          })
          .toList();
      cache.put('reservas', myReservations);
      await ReservasLocal.instance.guardar(currentEmployeeId!, myReservations);

      // Post-process to ensure clean structure similar to vehicle list if needed
      // but simpler to just pass raw Map to UI.
    } catch (e, st) {
      log.w('fetchData', 'Reservas con join falló; usando fallback sin join',
          error: e);
      debugPrint("Error fetching my reservations: $e\n$st");
      // Fallback: fetch just reservations
      try {
        final res = await _supabase
            .schema('flotilla')
            .from('reservas')
            .select()
            .eq('empleado_id', currentEmployeeId!)
            .order('fecha_salida', ascending: false);
        final cutoff = DateTime.now().subtract(const Duration(days: 60));
        myReservations = List<Map<String, dynamic>>.from(res)
            .where((r) {
              final fechaRegreso = DateTime.tryParse(r['fecha_regreso'] ?? '');
              return fechaRegreso == null || fechaRegreso.isAfter(cutoff);
            })
            .toList();
        cache.put('reservas', myReservations);
        await ReservasLocal.instance.guardar(currentEmployeeId!, myReservations);
      } catch (e2, st2) {
        log.e('fetchData', 'Reservas: fallback también falló',
            error: e2, stack: st2);
        _fallo('reservas', e2);
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
      cache.put('vehiculos', vehiculos);
      // Fotos de la flotilla listas para verlas sin conexión (segundo plano).
      ImagenesCache.instance.precargar(
          vehiculos.map((v) => (v['image'] ?? '').toString()));
    } catch (e, st) {
      log.e('fetchData', 'Falló la carga de vehículos', error: e, stack: st);
      rethrow;
    }
  }

  /// Liquidaciones del ÚLTIMO MES del usuario (con sus facturas). Se guardan
  /// en SQLite (tabla `liquidaciones`) para consultarlas sin conexión.
  Future<void> _fetchViaticos() async {
    try {
      if (currentEmployeeId == null) return;

      final desde = DateTime.now().subtract(const Duration(days: 30));
      final desdeStr = desde.toIso8601String().split('T')[0];

      final res = await _supabase
          .schema('viaticos')
          .from('liquidaciones')
          .select()
          .eq('empleado_id', currentEmployeeId!)
          .gte('fecha', desdeStr)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(res);

      // Facturas de esas liquidaciones en una sola consulta.
      final ids = rows.map((r) => r['id'].toString()).toList();
      if (ids.isNotEmpty) {
        try {
          final fres = await _supabase
              .schema('viaticos')
              .from('facturas')
              .select()
              .inFilter('liquidacion_id', ids);
          final porLiq = <String, List<Map<String, dynamic>>>{};
          for (final f in List<Map<String, dynamic>>.from(fres)) {
            porLiq.putIfAbsent(f['liquidacion_id'].toString(), () => []).add(f);
          }
          for (final r in rows) {
            r['facturas'] = porLiq[r['id'].toString()] ?? [];
          }
        } catch (e) {
          log.w('fetchData', 'Facturas del último mes fallaron', error: e);
        }
      }

      liquidacionesPendientes = rows.where((e) {
        final est = (e['estado'] ?? '').toString().toLowerCase();
        return est != 'aprobada' && est != 'aprobado';
      }).length;

      gastos = rows
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
      cache.put('gastos', gastos);
      await LiquidacionesLocal.instance.guardarRemotas(currentEmployeeId!, rows);
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

      // Las creadas sin conexión (id local) se conservan al frente hasta que
      // la cola las suba y vuelvan con id real.
      final pendientes = OfflineService.instance.pendientes;
      final locales = visitas
          .where((v) =>
              esIdLocal(v['id']) &&
              pendientes.any((o) => o['localId'] == v['id'].toString()))
          .toList();
      visitas = [...locales, ...List<Map<String, dynamic>>.from(resVisitas)];

      // Conteo para el dashboard
      rutasActivas = visitas.where((v) => v['estado'] == 'en_curso').length;
      cache.put('visitas', visitas);
      ImagenesCache.instance.precargar(_fotosDeVisitas(visitas));
    } catch (e) {
      // Se mantienen las visitas previas (o de caché) en vez de vaciar.
      _fallo('visitas', e);
    }
  }

  /// URLs de todas las fotos de una lista de visitas (adjuntas, odómetros,
  /// comprobante de pago) para precargarlas en la caché de imágenes.
  static Iterable<String> _fotosDeVisitas(List<Map<String, dynamic>> lista) sync* {
    for (final v in lista) {
      final fotos = v['fotos'];
      if (fotos is List) {
        for (final f in fotos) {
          yield f is Map ? (f['url'] ?? f['path'] ?? '').toString() : f.toString();
        }
      }
      for (final k in ['foto_odometro_inicio', 'foto_odometro_fin', 'comprobante_pago']) {
        final s = (v[k] ?? '').toString();
        if (s.startsWith('http')) yield s;
      }
    }
  }

  /// Inserta (o reemplaza) una visita creada sin conexión en la lista local y
  /// la persiste en caché para que sobreviva reinicios.
  void _agregarVisitaLocal(Map<String, dynamic> v) {
    visitas.removeWhere((x) => x['id'].toString() == v['id'].toString());
    visitas.insert(0, v);
    rutasActivas = visitas.where((x) => x['estado'] == 'en_curso').length;
    cache.put('visitas', visitas);
    notifyListeners();
  }

  void _actualizarVisitaLocal(String id, Map<String, dynamic> cambios) {
    final i = visitas.indexWhere((x) => x['id'].toString() == id);
    if (i < 0) return;
    visitas[i] = {...visitas[i], ...cambios};
    rutasActivas = visitas.where((x) => x['estado'] == 'en_curso').length;
    cache.put('visitas', visitas);
    notifyListeners();
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

      // ── SIN CONEXIÓN: encolar y mostrarla localmente ──
      if (!await OfflineService.instance.hayConexion()) {
        final localId = OfflineService.instance.nuevoIdLocal();
        final fotosLocales = <String, String>{};
        final fotosRemotas = <String>[];
        for (final f in (data['fotos'] as List? ?? [])) {
          final s = f.toString();
          if (s.startsWith('http')) {
            fotosRemotas.add(s);
          } else if (s.isNotEmpty) {
            fotosLocales['foto_${fotosLocales.length}'] = s;
          }
        }
        data['fotos'] = fotosRemotas;
        await OfflineService.instance.enqueue(
          type: 'visita_crear',
          record: data,
          photos: fotosLocales,
          localId: localId,
        );
        _agregarVisitaLocal({
          ...data,
          'id': localId,
          'fotos': [...fotosRemotas, ...fotosLocales.values],
          '_pendiente': true,
        });
        return true;
      }

      await _supabase.schema('visitas').from('visitas').insert(data);
      await _fetchRutas();
      return true;
    } catch (e) {
      debugPrint("Error creating visita: $e");
      errorMessage = mensajeError(e, accion: 'registrar la visita');
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

      if (esIdLocal(id)) {
        errorMessage = "Esta visita aún no se ha subido al servidor. "
            "Podrás editarla cuando haya conexión.";
        return false;
      }

      await _supabase
          .schema('visitas')
          .from('visitas')
          .update(visitaData)
          .eq('id', id);

      await _fetchRutas();
      return true;
    } catch (e) {
      debugPrint("Error updating visita: $e");
      errorMessage = mensajeError(e, accion: 'actualizar la visita');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPersonalVehicles() async {
    try {
      if (currentEmployeeId == null) await _fetchCurrentEmployeeId();
      if (currentEmployeeId == null) return;

      final res = await _supabase
          .schema('visitas')
          .from('vehiculos_personales')
          .select()
          .eq('empleado_id', currentEmployeeId!)
          .order('alias', ascending: true);

      personalVehicles = List<Map<String, dynamic>>.from(res);
      cache.put('vehiculosPersonales', personalVehicles);
      await VehiculosLocal.instance.guardar(currentEmployeeId!, personalVehicles);
      notifyListeners();
    } catch (e) {
      _fallo('vehículos personales', e);
    }
  }

  Future<bool> registerPersonalVehicle({
    required String alias,
    required int antiguedad,
    required String tipo,
    required String combustible,
  }) async {
    try {
      if (currentEmployeeId == null) await _fetchCurrentEmployeeId();
      
      await _supabase.schema('visitas').from('vehiculos_personales').insert({
        'empleado_id': currentEmployeeId,
        'alias': alias,
        'antiguedad': antiguedad,
        'tipo': tipo,
        'combustible': combustible,
      });

      await fetchPersonalVehicles();
      return true;
    } catch (e) {
      debugPrint("Error registering personal vehicle: $e");
      errorMessage = mensajeError(e, accion: 'registrar el vehículo');
      return false;
    }
  }

  Future<String?> uploadVisitaFoto(File file) async {
    try {
      final fileName = "visita_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final path = "visitas/$fileName";

      await _supabase.storage.from('visitas_fotos').upload(
        path,
        file,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final publicUrl = _supabase.storage.from('visitas_fotos').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint("Error uploading visita photo: $e");
      return null;
    }
  }

  // --- NUEVOS MÉTODOS VISITA V2 (SUPABASE SDK) ---

  Future<String?> startVisitaV2({
    required double lat,
    required double lng,
    required String odometroInicial,
    required String vehiculoId,
    File? fotoOdometro,
  }) async {
    try {
      if (currentEmployeeId == null) await _fetchCurrentEmployeeId();

      final bool online = await OfflineService.instance.hayConexion();

      String? fotoUrl;
      if (online && fotoOdometro != null) {
        fotoUrl = await uploadVisitaFoto(fotoOdometro);
      }

      final now = DateTime.now();
      final data = {
        'empleado_id': currentEmployeeId,
        'estado': 'en_curso',
        'fecha': now.toIso8601String().split('T')[0],
        'hora_inicio': now.toIso8601String().split('T')[1].substring(0, 8),
        'lat': lat,
        'lng': lng,
        'vehiculo_id': vehiculoId,
        'odometro_inicial': double.tryParse(odometroInicial) ?? 0,
        'foto_odometro_inicio': fotoUrl,
        'cliente': 'En ruta',
        'tipo_visita': 'ruta',
        'waypoints': [],
      };

      // ── SIN CONEXIÓN: encolar inicio y trabajar con id local ──
      if (!online) {
        final localId = OfflineService.instance.nuevoIdLocal();
        await OfflineService.instance.enqueue(
          type: 'visita_inicio',
          record: data,
          photos: fotoOdometro != null ? {'odometro_inicio': fotoOdometro.path} : null,
          localId: localId,
        );
        _agregarVisitaLocal({
          ...data,
          'id': localId,
          'foto_odometro_inicio': fotoOdometro?.path,
          '_pendiente': true,
        });
        return localId;
      }

      final res = await _supabase
          .schema('visitas')
          .from('visitas')
          .insert(data)
          .select()
          .single();

      await _fetchRutas();
      return res['id']?.toString();
    } catch (e) {
      debugPrint("Error starting visita V2: $e");
      errorMessage = mensajeError(e, accion: 'iniciar el viaje');
      return null;
    }
  }

  Future<bool> updateVisitaWaypointsV2(
    String id,
    List<Map<String, dynamic>> waypoints,
  ) async {
    try {
      if (esIdLocal(id) || !await OfflineService.instance.hayConexion()) {
        // Sin red (o visita creada offline): guardar en caché local. Los
        // waypoints completos viajan con la operación de cierre.
        _actualizarVisitaLocal(id, {'waypoints': waypoints});
        return true;
      }
      await _supabase
          .schema('visitas')
          .from('visitas')
          .update({'waypoints': waypoints})
          .eq('id', id);
      return true;
    } catch (e) {
      debugPrint("Error updating waypoints V2: $e");
      _actualizarVisitaLocal(id, {'waypoints': waypoints});
      return false;
    }
  }

  Future<Map<String, dynamic>?> finishVisitaV2({
    required String id,
    required String odometroFinal,
    required String observaciones,
    required List<String> proyectosVisitados,
    required List<Map<String, dynamic>> waypoints,
    File? fotoOdometroFin,
  }) async {
    try {
      isLoading = true;
      notifyListeners();

      // Para el cálculo de kilometraje, DEBEMOS usar la API PHP que tiene la lógica del tarifario.
      // Primero subimos la foto si existe.
      // Buscamos si la visita ya tiene foto (por si es una reanudación)
      final visitaPrevia = visitas.firstWhere(
        (v) => v['id'].toString() == id,
        orElse: () => {},
      );
      String? fotoUrl = visitaPrevia['foto_odometro_fin'];

      // ── SIN CONEXIÓN (o visita aún no subida): encolar el cierre ──
      if (esIdLocal(id) || !await OfflineService.instance.hayConexion()) {
        final now = DateTime.now();
        await OfflineService.instance.enqueue(
          type: 'visita_fin',
          record: {
            'id': id,
            'odometro_final': odometroFinal,
            'observaciones': observaciones,
            'proyectos_visitados': proyectosVisitados,
            'waypoints': waypoints,
            if (fotoOdometroFin == null && fotoUrl != null) 'foto_odometro_url': fotoUrl,
          },
          photos: fotoOdometroFin != null ? {'odometro_fin': fotoOdometroFin.path} : null,
        );
        _actualizarVisitaLocal(id, {
          'estado': 'completada',
          'hora_fin': now.toIso8601String().split('T')[1].substring(0, 8),
          'odometro_final': double.tryParse(odometroFinal) ?? 0,
          'observaciones': observaciones,
          'proyectos_visitados': proyectosVisitados,
          'waypoints': waypoints,
          'foto_odometro_fin': fotoOdometroFin?.path ?? fotoUrl,
          '_pendiente': true,
        });
        return {'success': true, 'offline': true};
      }

      if (fotoOdometroFin != null) {
        fotoUrl = await uploadVisitaFoto(fotoOdometroFin);
        if (fotoUrl == null) {
          errorMessage = "No se pudo subir la foto del odómetro. Revisa tu conexión e intenta de nuevo.";
          return null;
        }
      }

      final url = Uri.parse('https://grupomecsa.net/ops/api/finish_visita.php');
      
      final body = {
        'id': id,
        'odometro_final': odometroFinal,
        'observaciones': observaciones,
        'proyectos_visitados': proyectosVisitados,
        'waypoints': waypoints,
        'foto_odometro_url': fotoUrl, 
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          await _fetchRutas();
          return Map<String, dynamic>.from(data);
        } else {
          errorMessage = data['error']?.toString() ?? 'El servidor no pudo cerrar la visita. Intenta de nuevo.';
          return null;
        }
      } else {
        errorMessage = 'El servidor no pudo cerrar la visita (código ${response.statusCode}). Intenta de nuevo en unos minutos.';
        return null;
      }
    } catch (e) {
      debugPrint("Error finishing visita via PHP: $e");
      errorMessage = mensajeError(e, accion: 'finalizar la visita');
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
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
      cache.put('proyectos', projects);
    } catch (e) {
      // No bloquea la app; se mantienen los proyectos previos (o de caché).
      _fallo('proyectos', e);
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
      cache.put('empleados', employees);
    } catch (e) {
      _fallo('empleados', e);
    }
  }

  Future<void> fetchDepartments() async {
    try {
      final res = await _supabase
          .schema('cms')
          .from('departamento')
          .select('id, nombre, id_empresa')
          .order('nombre', ascending: true);

      departments = List<Map<String, dynamic>>.from(res as List);
      cache.put('departamentos', departments);
      notifyListeners();
    } catch (e) {
      _fallo('departamentos', e);
    }
  }

  Future<void> fetchCompanies() async {
    try {
      final res = await _supabase
          .from('Empresas')
          .select('id, nombre_comercial')
          .order('nombre_comercial', ascending: true);

      companies = (res as List)
          .map((e) => {
            'id': e['id'],
            'nombre': e['nombre_comercial'] ?? 'Sin nombre',
          })
          .toList();
      cache.put('empresas', companies);
      notifyListeners();
    } catch (e) {
      _fallo('empresas', e);
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

      if (user == null) throw "Tu sesión no está activa. Vuelve a iniciar sesión."; // NEW

      // Las reservas requieren conexión: hay que validar disponibilidad y
      // choques de horario contra el servidor en el momento. Sin internet
      // no se crea nada (ni se encola).
      if (!await OfflineService.instance.hayConexion()) {
        throw "Sin conexión a internet. Las reservas solo se pueden crear "
            "con conexión.";
      }

      // Use cached ID or fetch it // NEW
      if (currentEmployeeId == null) {
        // NEW
        await _fetchCurrentEmployeeId(); // NEW
        if (currentEmployeeId == null) {
          // NEW
          throw "Tu usuario no tiene ficha de empleado asociada (${user!.email}). Contacta al administrador."; // NEW
        }
      } // NEW

      // ── BLOQUEO POR STRIKES ─────────────────────────────────────────
      // Antes de permitir la reserva, aplicar bloqueo si corresponde
      // y luego validar el flag. Esto auto-bloquea a quien acumuló 3+
      // reservas vencidas sin registro y rechaza la nueva reserva.
      //
      // IMPORTANTE: si un admin desbloqueó manualmente al empleado, se le
      // pone la etiqueta 'RESERVAS_EXCEPCION' en sistemas_acceso. En ese
      // caso NO reejecutamos el RPC (que volvería a bloquearlo por las
      // reservas viejas sin registrar). Sin este chequeo, desbloquear desde
      // la web no tenía efecto porque el mobile re-bloqueaba al instante.
      try {
        // Leer flag actual + sistemas_acceso en una sola consulta
        final empCheck = await _supabase
            .from('Empleados')
            .select('reservas_bloqueado, sistemas_acceso')
            .eq('id', currentEmployeeId as Object)
            .maybeSingle();

        final List sistemas = (empCheck?['sistemas_acceso'] as List?) ?? [];
        final bool tieneExcepcion = sistemas.contains('RESERVAS_EXCEPCION');

        if (!tieneExcepcion) {
          // Solo re-evaluar strikes si NO tiene excepción manual del admin
          await _supabase
              .schema('flotilla')
              .rpc('aplicar_bloqueo_si_corresponde',
                  params: {'p_empleado_id': currentEmployeeId});

          final recheck = await _supabase
              .from('Empleados')
              .select('reservas_bloqueado')
              .eq('id', currentEmployeeId as Object)
              .maybeSingle();

          if (recheck != null && recheck['reservas_bloqueado'] == true) {
            throw "Tu cuenta está bloqueada para hacer reservas. "
                "Acumulaste 3 o más reservas sin registrar salida. "
                "Contacta al administrador para desbloquear.";
          }
        }
        // Si tiene excepción, se le permite reservar sin re-evaluar.
      } catch (e) {
        if (e is String) rethrow;
        // Si la RPC falla por permisos u otra razón, no bloqueamos
        // creación: priorizar operatividad sobre la regla nueva.
        debugPrint("aplicar_bloqueo_si_corresponde falló (continuo): $e");
      }
      // ─────────────────────────────────────────────────────────────────

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
    } catch (e, st) {
      log.e('reservas', 'Crear reserva falló',
          data: {
            'vehiculo_id': reservationData['vehiculo_id'],
            'fecha_salida': reservationData['fecha_salida'],
            'fecha_regreso': reservationData['fecha_regreso'],
          },
          error: e,
          stack: st);
      errorMessage = mensajeError(e, accion: 'crear la reserva');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Registros de salida/entrada de una reserva. Con conexión consulta el
  /// servidor y guarda el resultado en caché; sin conexión devuelve la caché.
  /// En ambos casos agrega los registros que están en la cola offline
  /// (marcados con `_pendiente: true`) para que la pantalla sepa que la
  /// salida/entrada ya se hizo aunque todavía no haya subido.
  Future<List<Map<String, dynamic>>> getRegistrosReserva(String reservaId) async {
    final key = 'registros:$reservaId';
    List<Map<String, dynamic>> regs = [];
    bool remotoOk = false;
    if (await OfflineService.instance.hayConexion()) {
      try {
        final res = await _supabase
            .schema('flotilla')
            .from('registros_vehiculos')
            .select()
            .eq('reserva_id', reservaId)
            .timeout(const Duration(seconds: 15));
        regs = List<Map<String, dynamic>>.from(res);
        remotoOk = true;
        cache.put(key, regs);
      } catch (e) {
        log.w('reservas', 'Registros de reserva: falló remoto, usando caché',
            error: e);
      }
    }
    if (!remotoOk) {
      regs = (await cache.get(key))?.asList() ?? [];
    }
    // Pendientes en la cola (aún no subidos).
    for (final op in OfflineService.instance.pendientesDonde('reserva_id', reservaId)) {
      if (op['type'] != 'registro_vehiculo') continue;
      final rec = Map<String, dynamic>.from(op['record'] as Map);
      final tipo = rec['tipo']?.toString().toLowerCase();
      final yaSubido = regs.any((r) =>
          r['tipo'].toString().toLowerCase() == tipo &&
          r['estado']?.toString() != 'Rechazado');
      if (yaSubido) continue;
      regs.add({
        ...rec,
        'fecha_registro': op['createdAt'],
        'estado': 'Pendiente',
        '_pendiente': true,
        '_intentos': op['attempts'],
        '_error': op['lastError'],
      });
    }
    return regs;
  }

  /// Cancela una reserva propia. Solo el solicitante y solo si:
  /// - estado in (Pendiente, Aprobada)
  /// - fecha_salida es futura
  /// - no hay registro de salida todavía
  /// Las validaciones de propietario/estado se hacen aquí pero el UI debe
  /// gatear el botón para no llegar nunca a llamar esto en escenarios inválidos.
  Future<bool> cancelarReserva({
    required String reservaId,
    String motivo = '',
  }) async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      // Carga la reserva para validar estado y propietario
      final r = await _supabase
          .schema('flotilla')
          .from('reservas')
          .select('id, estado, fecha_salida, empleado_id')
          .eq('id', reservaId)
          .maybeSingle();

      if (r == null) throw "La reserva ya no existe o fue modificada. Actualiza la pantalla.";

      final String estado = (r['estado'] ?? '').toString();
      final String estadoUpper = estado.toUpperCase();
      if (estadoUpper.contains('CANCEL') ||
          estadoUpper.contains('RECHAZ') ||
          estadoUpper.contains('COMPLET')) {
        throw "Esta reserva ya está $estado";
      }

      final fechaSalida = DateTime.tryParse(r['fecha_salida']?.toString() ?? '');
      if (fechaSalida != null && fechaSalida.isBefore(DateTime.now())) {
        throw "No se puede cancelar: la salida ya pasó";
      }

      if (currentEmployeeId == null || r['empleado_id'] != currentEmployeeId) {
        throw "Solo el solicitante puede cancelar esta reserva";
      }

      // ¿Ya hay registro de salida? Si sí, no se puede cancelar.
      final regs = await _supabase
          .schema('flotilla')
          .from('registros_vehiculos')
          .select('id, tipo')
          .eq('reserva_id', reservaId);
      final tieneSalida =
          (regs as List).any((x) => (x['tipo'] ?? '').toString().toLowerCase() == 'salida');
      if (tieneSalida) {
        throw "Ya iniciaste el viaje, no se puede cancelar";
      }

      // PATCH
      await _supabase.schema('flotilla').from('reservas').update({
        'estado': 'Cancelada',
        'comentarios': motivo.isNotEmpty
            ? 'Cancelada por el solicitante: $motivo'
            : 'Cancelada por el solicitante',
      }).eq('id', reservaId);

      // Refresh
      await Future.wait([
        _fetchFlotilla(),
        _fetchMyReservations(),
      ]);

      return true;
    } catch (e) {
      debugPrint("Error cancelando reserva: $e");
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Solicita una corrección sobre un registro ya guardado (viáticos o kilometraje).
  ///
  /// El empleado NO puede editar directamente el registro; solo puede escribir
  /// qué necesita corregirse. El registro cambia de estado y el admin lo revisa
  /// en la web. Aplica a:
  ///   - schema='viaticos' + table='liquidaciones'
  ///   - schema='flotilla' + table='registros_vehiculos'
  Future<bool> solicitarCorreccion({
    required String schema,
    required String table,
    required String recordId,
    required String motivo,
  }) async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      final texto = motivo.trim();
      if (texto.isEmpty) {
        throw "Debes escribir qué necesita corregirse";
      }
      if (texto.length < 8) {
        throw "El motivo es muy corto (mínimo 8 caracteres)";
      }

      // Verificar el registro existe y no tiene ya solicitud activa
      final r = await _supabase
          .schema(schema)
          .from(table)
          .select('id, estado, solicitud_correccion, empleado_id')
          .eq('id', recordId)
          .maybeSingle();
      if (r == null) throw "El registro ya no existe. Actualiza la pantalla.";

      final estadoActual = (r['estado'] ?? '').toString();
      if (estadoActual.toLowerCase().contains('correccion solicitada') ||
          estadoActual.toLowerCase().contains('en revisi')) {
        throw "Ya hay una solicitud de corrección pendiente para este registro";
      }
      if (r['empleado_id'] != null &&
          currentEmployeeId != null &&
          r['empleado_id'] != currentEmployeeId) {
        throw "Solo el propietario del registro puede solicitar corrección";
      }

      await _supabase.schema(schema).from(table).update({
        'solicitud_correccion': texto,
        'fecha_correccion': DateTime.now().toUtc().toIso8601String(),
        'estado': 'Correccion Solicitada',
      }).eq('id', recordId);

      return true;
    } catch (e) {
      debugPrint("Error solicitando corrección: $e");
      errorMessage = e.toString();
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

      final swTotal = Stopwatch()..start();
      final ctx = {'reserva_id': reservaId, 'tipo': tipo, 'fotos': localPhotos.length};
      log.i('registro', 'Guardar registro: inicio', data: ctx);

      if (user == null) throw "Tu sesión no está activa. Vuelve a iniciar sesión.";
      if (currentEmployeeId == null) {
        await log.time('registro', 'empleado', _fetchCurrentEmployeeId, data: ctx);
      }
      if (currentEmployeeId == null) throw "No se encontró tu ficha de empleado. Actualiza la pantalla o contacta al administrador.";

      // Idempotencia (igual que el path offline _subirRegistro): si YA existe un
      // registro para esta reserva+tipo (no rechazado), NO duplicar → devolver éxito.
      // Evita registros dobles cuando se pierde la respuesta y el usuario reintenta.
      try {
        final ya = await log.time('registro', 'verificar duplicado', () => _supabase
            .schema('flotilla')
            .from('registros_vehiculos')
            .select('id')
            .eq('reserva_id', reservaId)
            .eq('tipo', tipo)
            .neq('estado', 'Rechazado')
            .limit(1)
            .timeout(const Duration(seconds: 15)), data: ctx);
        if ((ya as List).isNotEmpty) {
          log.i('registro', 'Ya existía un registro; no se duplica', data: ctx);
          return true;
        }
      } catch (_) {
        // si el chequeo falla por red, seguimos e intentamos igual (ya quedó en el log)
      }

      // 1. Upload photos in parallel
      final Map<String, String> photoUrls = {};
      final List<Future<void>> uploadFutures = [];

      for (var entry in localPhotos.entries) {
        if (entry.value != null) {
          uploadFutures.add(
            log.time('registro', 'subir foto ${entry.key}',
                () => _uploadRegisterPhoto(entry.value, entry.key, reservaId),
                data: ctx).then((url) {
              if (url != null) {
                photoUrls["foto_${entry.key}"] = url;
              }
            }),
          );
        }
      }

      if (uploadFutures.isNotEmpty) {
        await Future.wait(uploadFutures);
      }
      log.i('registro', 'Fotos subidas', data: {
        ...ctx,
        'subidas': photoUrls.length,
        'ms': swTotal.elapsedMilliseconds,
      });

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
      final swGps = Stopwatch()..start();
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        data['ubicacion'] = "${pos.latitude},${pos.longitude}";
        log.d('registro', 'Ubicación obtenida',
            data: {...ctx, 'ms': swGps.elapsedMilliseconds});
      } catch (e) {
        log.w('registro', 'Sin ubicación para el registro',
            data: {...ctx, 'ms': swGps.elapsedMilliseconds}, error: e);
      }

      await log.time('registro', 'insertar registro', () => _supabase
          .schema('flotilla')
          .from('registros_vehiculos')
          .insert(data)
          .timeout(const Duration(seconds: 30)), data: ctx);

      log.i('registro', 'Registro guardado',
          data: {...ctx, 'kilometraje': kilometraje, 'ms': swTotal.elapsedMilliseconds});

      // El registro YA quedó guardado. Refrescar en SEGUNDO PLANO (sin await):
      // fetchData() no tiene timeouts y con mala señal se colgaba, dejando la UI
      // atascada en "Subiendo" aunque la salida/entrada ya se había guardado.
      fetchData().catchError((_) {});
      return true;
    } catch (e, st) {
      log.e('registro', 'Guardar registro falló',
          data: {'reserva_id': reservaId, 'tipo': tipo}, error: e, stack: st);
      errorMessage = mensajeError(e, accion: 'guardar el registro');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Registro MANUAL de respaldo: cuando el registro normal falla o se cuelga,
  /// el empleado envía un comentario + las fotos que pudo. Queda 'Pendiente' de
  /// aprobación en la web. Best-effort: si una foto no sube, igual se envía.
  Future<bool> saveVehicleRegisterManual({
    required String reservaId,
    required String tipo,
    required String comentario,
    required Map<String, dynamic> localPhotos,
    double? kilometraje,
  }) async {
    try {
      isLoading = true;
      notifyListeners();

      if (user == null) throw "Tu sesión no está activa. Vuelve a iniciar sesión.";
      if (currentEmployeeId == null) await _fetchCurrentEmployeeId();
      if (currentEmployeeId == null) throw "No se encontró tu ficha de empleado. Actualiza la pantalla o contacta al administrador.";

      // Subir las fotos que se pueda (sin abortar si alguna falla)
      final Map<String, String> photoUrls = {};
      for (final entry in localPhotos.entries) {
        if (entry.value == null) continue;
        try {
          final url = await _uploadRegisterPhoto(entry.value, entry.key, reservaId);
          if (url != null) photoUrls["foto_${entry.key}"] = url;
        } catch (e) {
          debugPrint("Foto ${entry.key} no subió (registro manual, continúo): $e");
        }
      }

      final Map<String, dynamic> data = {
        'reserva_id': reservaId,
        'empleado_id': currentEmployeeId,
        'tipo': tipo,
        'estado': 'Pendiente',
        'es_manual': true,
        'comentario': comentario,
        if (kilometraje != null) 'kilometraje': kilometraje,
        ...photoUrls,
      };

      await _supabase
          .schema('flotilla')
          .from('registros_vehiculos')
          .insert(data)
          .timeout(const Duration(seconds: 30));

      log.i('registro', 'Registro MANUAL guardado', data: {
        'reserva_id': reservaId,
        'tipo': tipo,
        'fotos': photoUrls.length,
      });
      // Guardado OK. Refresco en segundo plano (misma razón que saveVehicleRegister:
      // evitar que fetchData() sin timeout cuelgue la UI en "Subiendo").
      fetchData().catchError((_) {});
      return true;
    } catch (e, st) {
      log.e('registro', 'Registro MANUAL falló',
          data: {'reserva_id': reservaId, 'tipo': tipo}, error: e, stack: st);
      errorMessage = mensajeError(e, accion: 'enviar el registro manual');
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
          .upload(path, file)
          .timeout(const Duration(seconds: 40)); // evita que se quede colgado

      return fileName;
    } catch (e) {
      debugPrint("Error uploading photo $name: $e");
      // Rethrow to let saveVehicleRegister catch it and abort insert if critical
      throw "No se pudo subir la foto '$name'. ${mensajeError(e)}";
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
          .eq('id', currentEmployeeId!);

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
      errorMessage = mensajeError(e, accion: 'actualizar la foto');
      notifyListeners();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile({
    required String nombre,
    required String apellido,
    required String telefono,
  }) async {
    try {
      if (currentEmployeeId == null) return false;

      isLoading = true;
      notifyListeners();

      await _supabase.from('Empleados').update({
        'nombre': nombre,
        'apellido': apellido,
        'telefono': telefono,
      }).eq('id', currentEmployeeId!);

      // Actualizar localmente
      if (currentEmployeeData != null) {
        currentEmployeeData!['nombre'] = nombre;
        currentEmployeeData!['apellido'] = apellido;
        currentEmployeeData!['telefono'] = telefono;
      }

      _notificationMessage = "Perfil actualizado correctamente";
      return true;
    } catch (e) {
      debugPrint("❌ Error updating profile: $e");
      errorMessage = mensajeError(e, accion: 'actualizar el perfil');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
