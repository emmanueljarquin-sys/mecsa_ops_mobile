// =============================================================================
// sync_service.dart — Copia de seguridad / sincronización con el servidor
// -----------------------------------------------------------------------------
// Equivalente a la "copia de seguridad" de WhatsApp:
//
//   1. Sube todo lo pendiente de la cola offline (OfflineService.flush).
//   2. Vuelve a bajar reservas, liquidaciones (último mes) y visitas del
//      usuario y las guarda en SQLite (sobrescribe con lo que diga el API).
//   3. Muestra una notificación "Sincronizando con el servidor…" mientras
//      corre y "Sincronización completa" al terminar.
//
// Se ejecuta:
//   - A mano desde Perfil → Copias de seguridad → "Sincronizar ahora".
//   - Automáticamente todos los días a la hora configurada (por defecto
//     02:00) con WorkManager, aunque la app esté cerrada. Android puede
//     moverla unos minutos según batería/Doze; no es un reloj exacto.
//
// Preferencias (SharedPreferences):
//   backup_enabled     bool   copia automática activada (default true)
//   backup_freq        String 'diaria' | 'semanal' | 'mensual' (default diaria)
//   backup_weekday     int    1=lunes … 7=domingo (semanal, default 1)
//   backup_monthday    int    1..28 (mensual, default 1)
//   backup_hour/minute int    hora local (default 02:00)
//
// WorkManager solo garantiza periodicidad aproximada, así que la tarea de
// fondo corre TODOS los días a la hora elegida y `tocaHoy()` decide si según
// la frecuencia (semanal/mensual) hoy corresponde hacer la copia.
//   backup_wifi_only   bool   solo WiFi (default true) o WiFi + datos
//   backup_last_run_ms int    última ejecución
//   backup_last_result String resumen de la última ejecución
// =============================================================================
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

// NOTA: el callback de WorkManager (`syncCallbackDispatcher`) vive en
// main.dart porque el isolate de fondo arranca vacío y necesita inicializar
// Supabase, logger y cola con las mismas claves que la app.

import 'app_logger.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';
import 'liquidaciones_local.dart';
import 'liquidaciones_service.dart';
import 'offline_service.dart';
import 'reservas_local.dart';

/// Nombre de la tarea periódica (WorkManager).
const String kSyncTaskUnique = 'mecsa_backup_diario';
const String kSyncTaskName = 'mecsa_backup_diario_task';

class SyncResumen {
  final bool ok;
  final String mensaje;
  final int subidas;
  final int pendientes;
  final DateTime fecha;
  const SyncResumen({
    required this.ok,
    required this.mensaje,
    required this.subidas,
    required this.pendientes,
    required this.fecha,
  });
}

class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const int _notifId = 9101;
  static const String _canal = 'channel_sync';

  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  bool _notifListo = false;

  bool _corriendo = false;
  String? _paso;
  bool enabled = true;
  /// 'diaria' | 'semanal' | 'mensual'
  String freq = 'diaria';
  /// 1 = lunes … 7 = domingo (solo semanal).
  int weekday = DateTime.monday;
  /// 1..28 (solo mensual).
  int monthday = 1;
  int hour = 2;
  int minute = 0;
  bool wifiOnly = true;
  DateTime? lastRun;
  String? lastResult;
  bool _prefsCargadas = false;

  bool get isRunning => _corriendo;
  String? get pasoActual => _paso;

  // ── Preferencias ────────────────────────────────────────────────────────
  Future<void> cargarPrefs() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('backup_enabled') ?? true;
    freq = p.getString('backup_freq') ?? 'diaria';
    weekday = p.getInt('backup_weekday') ?? DateTime.monday;
    monthday = p.getInt('backup_monthday') ?? 1;
    hour = p.getInt('backup_hour') ?? 2;
    minute = p.getInt('backup_minute') ?? 0;
    wifiOnly = p.getBool('backup_wifi_only') ?? true;
    final ms = p.getInt('backup_last_run_ms');
    lastRun = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    lastResult = p.getString('backup_last_result');
    _prefsCargadas = true;
    notifyListeners();
  }

  Future<void> guardarPrefs({
    bool? enabled,
    String? freq,
    int? weekday,
    int? monthday,
    int? hour,
    int? minute,
    bool? wifiOnly,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (enabled != null) {
      this.enabled = enabled;
      await p.setBool('backup_enabled', enabled);
    }
    if (freq != null) {
      this.freq = freq;
      await p.setString('backup_freq', freq);
    }
    if (weekday != null) {
      this.weekday = weekday;
      await p.setInt('backup_weekday', weekday);
    }
    if (monthday != null) {
      this.monthday = monthday.clamp(1, 28);
      await p.setInt('backup_monthday', this.monthday);
    }
    if (hour != null) {
      this.hour = hour;
      await p.setInt('backup_hour', hour);
    }
    if (minute != null) {
      this.minute = minute;
      await p.setInt('backup_minute', minute);
    }
    if (wifiOnly != null) {
      this.wifiOnly = wifiOnly;
      await p.setBool('backup_wifi_only', wifiOnly);
    }
    notifyListeners();
    await programar();
  }

  Future<void> _guardarResultado(SyncResumen r) async {
    lastRun = r.fecha;
    lastResult = r.mensaje;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('backup_last_run_ms', r.fecha.millisecondsSinceEpoch);
      await p.setString('backup_last_result', r.mensaje);
    } catch (_) {}
    notifyListeners();
  }

  // ── Programación diaria (WorkManager) ───────────────────────────────────
  /// Registra (o cancela) la tarea diaria según las preferencias.
  Future<void> programar() async {
    if (!_prefsCargadas) await cargarPrefs();
    try {
      if (!enabled) {
        await Workmanager().cancelByUniqueName(kSyncTaskUnique);
        log.i('sync', 'Copia automática desactivada');
        return;
      }
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, hour, minute);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      final delay = next.difference(now);
      await Workmanager().registerPeriodicTask(
        kSyncTaskUnique,
        kSyncTaskName,
        frequency: const Duration(hours: 24),
        initialDelay: delay,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(
          networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 15),
      );
      log.i('sync', 'Copia automática programada', data: {
        'frecuencia': freq,
        'primerChequeo': next.toIso8601String(),
        'proximaCopia': proximaEjecucion?.toIso8601String(),
        'enMinutos': delay.inMinutes,
        'soloWifi': wifiOnly,
      });
    } catch (e, st) {
      log.e('sync', 'No se pudo programar la copia automática',
          error: e, stack: st);
    }
  }

  /// ¿Corresponde hacer la copia en la fecha [d] según la frecuencia?
  bool tocaEnFecha(DateTime d) {
    switch (freq) {
      case 'semanal':
        return d.weekday == weekday;
      case 'mensual':
        return d.day == monthday;
      default:
        return true;
    }
  }

  /// Próxima copia automática real (respetando frecuencia).
  DateTime? get proximaEjecucion {
    if (!enabled) return null;
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    for (int i = 0; i < 62; i++) {
      if (tocaEnFecha(next)) return next;
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  String get descripcionFrecuencia {
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    switch (freq) {
      case 'semanal':
        return 'Cada ${dias[(weekday - 1).clamp(0, 6)]} a las $hh:$mm';
      case 'mensual':
        return 'El día $monthday de cada mes a las $hh:$mm';
      default:
        return 'Todos los días a las $hh:$mm';
    }
  }

  /// Llamado por la tarea diaria de WorkManager: solo sincroniza si hoy
  /// corresponde según la frecuencia (y no se hizo ya hoy).
  Future<SyncResumen?> sincronizarSiToca() async {
    if (!_prefsCargadas) await cargarPrefs();
    final hoy = DateTime.now();
    if (!enabled) return null;
    if (!tocaEnFecha(hoy)) {
      log.i('sync', 'Hoy no toca copia automática', data: {'frecuencia': freq});
      return null;
    }
    final lr = lastRun;
    if (lr != null && lr.year == hoy.year && lr.month == hoy.month && lr.day == hoy.day && freq != 'diaria') {
      log.i('sync', 'Copia automática ya hecha hoy');
      return null;
    }
    return sincronizar();
  }

  // ── Notificaciones ──────────────────────────────────────────────────────
  Future<void> _initNotif() async {
    if (_notifListo) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _notif.initialize(settings);
      _notifListo = true;
    } catch (e) {
      log.w('sync', 'Notificaciones no disponibles', error: e);
    }
  }

  Future<void> _notificarProgreso(String texto) async {
    if (!_notifListo) return;
    try {
      const android = AndroidNotificationDetails(
        _canal,
        'Sincronización',
        channelDescription: 'Progreso de la copia de seguridad con el servidor',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        onlyAlertOnce: true,
        showProgress: true,
        indeterminate: true,
        autoCancel: false,
      );
      await _notif.show(_notifId, 'Sincronizando con el servidor…', texto,
          const NotificationDetails(android: android));
    } catch (_) {}
  }

  Future<void> _notificarFin(SyncResumen r) async {
    if (!_notifListo) return;
    try {
      final android = AndroidNotificationDetails(
        _canal,
        'Sincronización',
        channelDescription: 'Progreso de la copia de seguridad con el servidor',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: false,
        autoCancel: true,
        timeoutAfter: 60000,
        icon: r.ok ? null : '@mipmap/ic_launcher',
      );
      await _notif.show(
        _notifId,
        r.ok ? 'Sincronización completa' : 'Sincronización incompleta',
        r.mensaje,
        NotificationDetails(android: android),
      );
    } catch (_) {}
  }

  // ── Ejecución ───────────────────────────────────────────────────────────
  /// [manual] = lanzada por el usuario: ignora la restricción "solo WiFi".
  Future<SyncResumen> sincronizar({bool manual = false}) async {
    if (_corriendo) {
      return SyncResumen(
        ok: false,
        mensaje: 'Ya hay una sincronización en curso.',
        subidas: 0,
        pendientes: OfflineService.instance.pendingCount,
        fecha: DateTime.now(),
      );
    }
    if (!_prefsCargadas) await cargarPrefs();
    await _initNotif();
    _corriendo = true;
    _paso = 'Verificando conexión…';
    notifyListeners();
    final sw = Stopwatch()..start();
    final pendAntes = OfflineService.instance.pendingCount;
    log.i('sync', 'Sincronización iniciada',
        data: {'manual': manual, 'pendientes': pendAntes});

    SyncResumen resumen;
    try {
      // 1) Red
      final tipos = await Connectivity().checkConnectivity();
      final hayRed = tipos.any((t) => t != ConnectivityResult.none);
      final esWifi = tipos.contains(ConnectivityResult.wifi) ||
          tipos.contains(ConnectivityResult.ethernet);
      if (!hayRed) {
        throw 'Sin conexión de red.';
      }
      if (wifiOnly && !esWifi && !manual) {
        throw 'Esperando WiFi (la copia está configurada solo con WiFi).';
      }
      if (!await ConnectivityService.instance.checkInternet(force: true)) {
        throw 'La red no tiene salida a internet.';
      }

      // 2) Subir pendientes
      _paso = 'Subiendo $pendAntes pendiente(s)…';
      notifyListeners();
      await _notificarProgreso(_paso!);
      await OfflineService.instance.flush();
      final pendDespues = OfflineService.instance.pendingCount;
      final subidas = pendAntes - pendDespues;

      // 3) Bajar datos frescos
      _paso = 'Descargando reservas, liquidaciones y visitas…';
      notifyListeners();
      await _notificarProgreso(_paso!);
      final bajadas = await _refrescarDatos();

      final partes = <String>[
        if (subidas > 0) '$subidas subida(s)',
        if (pendDespues > 0) '$pendDespues aún pendiente(s)',
        '$bajadas registro(s) actualizados',
      ];
      resumen = SyncResumen(
        ok: pendDespues == 0,
        mensaje: partes.join(' · '),
        subidas: subidas,
        pendientes: pendDespues,
        fecha: DateTime.now(),
      );
    } catch (e, st) {
      log.w('sync', 'Sincronización falló', error: e);
      debugPrint('$st');
      resumen = SyncResumen(
        ok: false,
        mensaje: e is String ? e : 'No se pudo completar. Se reintentará.',
        subidas: 0,
        pendientes: OfflineService.instance.pendingCount,
        fecha: DateTime.now(),
      );
    } finally {
      _corriendo = false;
      _paso = null;
    }
    await _guardarResultado(resumen);
    await _notificarFin(resumen);
    log.i('sync', 'Sincronización terminada', data: {
      'ok': resumen.ok,
      'mensaje': resumen.mensaje,
      'ms': sw.elapsedMilliseconds,
    });
    notifyListeners();
    return resumen;
  }

  /// Baja reservas, liquidaciones del último mes y visitas del usuario y las
  /// guarda en SQLite/caché. Devuelve cuántas filas se actualizaron.
  Future<int> _refrescarDatos() async {
    final sb = Supabase.instance.client;
    final email = sb.auth.currentUser?.email;
    if (email == null) return 0;
    cache.setScope(email);
    final perfil = (await cache.get('perfil'))?.asMap();
    final empleadoId = perfil?['empleado']?['id']?.toString();
    if (empleadoId == null || empleadoId.isEmpty) return 0;

    int total = 0;

    // Reservas (con join de vehículo; si falla, sin join).
    try {
      List<Map<String, dynamic>> rows;
      try {
        final res = await sb
            .schema('flotilla')
            .from('reservas')
            .select('*, vehiculos(*)')
            .eq('empleado_id', empleadoId)
            .order('fecha_salida', ascending: false)
            .timeout(const Duration(seconds: 30));
        rows = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        final res = await sb
            .schema('flotilla')
            .from('reservas')
            .select()
            .eq('empleado_id', empleadoId)
            .order('fecha_salida', ascending: false)
            .timeout(const Duration(seconds: 30));
        rows = List<Map<String, dynamic>>.from(res);
      }
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      rows = rows.where((r) {
        final f = DateTime.tryParse(r['fecha_regreso']?.toString() ?? '');
        return f == null || f.isAfter(cutoff);
      }).toList();
      await cache.put('reservas', rows);
      await ReservasLocal.instance.guardar(empleadoId, rows);
      total += rows.length;
    } catch (e) {
      log.w('sync', 'Reservas no se pudieron bajar', error: e);
    }

    // Liquidaciones del último mes + facturas.
    try {
      final desde = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .split('T')[0];
      final res = await sb
          .schema('viaticos')
          .from('liquidaciones')
          .select()
          .eq('empleado_id', empleadoId)
          .gte('fecha', desde)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 30));
      final rows = List<Map<String, dynamic>>.from(res);
      final ids = rows.map((r) => r['id'].toString()).toList();
      if (ids.isNotEmpty) {
        try {
          final fres = await sb
              .schema('viaticos')
              .from('facturas')
              .select()
              .inFilter('liquidacion_id', ids)
              .timeout(const Duration(seconds: 30));
          final porLiq = <String, List<Map<String, dynamic>>>{};
          for (final f in List<Map<String, dynamic>>.from(fres)) {
            porLiq.putIfAbsent(f['liquidacion_id'].toString(), () => []).add(f);
          }
          for (final r in rows) {
            r['facturas'] = porLiq[r['id'].toString()] ?? [];
          }
        } catch (_) {}
      }
      await LiquidacionesLocal.instance.guardarRemotas(empleadoId, rows);
      total += rows.length;
    } catch (e) {
      log.w('sync', 'Liquidaciones no se pudieron bajar', error: e);
    }

    // Personal y últimos proyectos para el formulario de liquidaciones.
    try {
      await LiquidacionesService.getEmpleados();
      await LiquidacionesService.getProyectos();
    } catch (e) {
      log.w('sync', 'Caché del formulario de liquidaciones falló', error: e);
    }

    // Visitas.
    try {
      final res = await sb
          .schema('visitas')
          .from('visitas')
          .select()
          .eq('empleado_id', empleadoId)
          .order('fecha', ascending: false)
          .timeout(const Duration(seconds: 30));
      final rows = List<Map<String, dynamic>>.from(res);
      // Conservar las creadas offline que sigan pendientes.
      final previas = (await cache.get('visitas'))?.asList() ?? [];
      final pend = OfflineService.instance.pendientes;
      final locales = previas.where((v) =>
          esIdLocal(v['id']) &&
          pend.any((o) => o['localId'] == v['id'].toString()));
      await cache.put('visitas', [...locales, ...rows]);
      total += rows.length;
    } catch (e) {
      log.w('sync', 'Visitas no se pudieron bajar', error: e);
    }

    return total;
  }
}

