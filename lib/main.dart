import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'services/app_logger.dart';
import 'services/connectivity_service.dart';
import 'services/offline_service.dart';
import 'services/sync_service.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

const String kSupabaseUrl = 'https://awhuzekjpoapamijlvua.supabase.co';
const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF3aHV6ZWtqcG9hcGFtaWpsdnVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE1NzM2ODMsImV4cCI6MjA3NzE0OTY4M30.2wnEN8HG2LA3CRhDbHQdu7drrsF7-G7zg-CCt7rqkeQ';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

/// Punto de entrada de WorkManager: corre en un isolate de fondo (la app
/// puede estar cerrada) todos los días a la hora configurada en
/// Perfil → Copias de seguridad. Inicializa lo mínimo y delega en SyncService.
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      try {
        await AppLogger.instance.init(appVersion: 'bg');
      } catch (_) {}
      log.i('sync', 'Tarea de fondo iniciada', data: {'task': taskName});
      await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
      await ConnectivityService.instance.init(
          probeUrl: '$kSupabaseUrl/rest/v1/', headers: {'apikey': kSupabaseAnonKey});
      await OfflineService.instance.init();
      final r = await SyncService.instance.sincronizarSiToca();
      return r == null || r.ok || r.pendientes == 0;
    } catch (e, st) {
      log.e('sync', 'Tarea de fondo falló', error: e, stack: st);
      return false;
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  // Registro de actividad local (SQLite). No bloquear el arranque si falla.
  String appVersion = '?';
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {}
  try {
    await AppLogger.instance.init(appVersion: appVersion);
  } catch (e) {
    print("AppLogger init failed: $e");
  }
  log.i('app', 'Arranque', data: {
    'version': appVersion,
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
  });
  // Errores no capturados (Flutter y Dart) quedan en el registro.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.e('app', 'Error de Flutter no capturado',
        error: details.exceptionAsString(), stack: details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.e('app', 'Error no capturado', error: error, stack: stack);
    return false; // dejar que el manejo por defecto continúe
  };

  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);

  // Estado de conexión con verificación de internet real (sondeo al backend).
  // No bloquear el arranque: el sondeo inicial corre en segundo plano.
  ConnectivityService.instance
      .init(probeUrl: '$kSupabaseUrl/rest/v1/', headers: {'apikey': kSupabaseAnonKey})
      .catchError((e) => log.w('conectividad', 'init falló', error: e));

  bool firebaseAvailable = false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    firebaseAvailable = true;
    log.i('app', 'Firebase inicializado');
  } catch (e, st) {
    log.w('app', 'Firebase no disponible', error: e);
    print("Firebase initialization failed: $e\n$st");
  }

  // Cola de sincronización offline (no bloquear el arranque si falla)
  try {
    await OfflineService.instance.init();
  } catch (e, st) {
    log.e('offline', 'OfflineService no pudo iniciar', error: e, stack: st);
  }

  // Copia de seguridad diaria (WorkManager). No bloquear el arranque.
  try {
    await Workmanager().initialize(syncCallbackDispatcher);
    SyncService.instance.programar();
  } catch (e, st) {
    log.w('sync', 'WorkManager no pudo iniciar', error: e);
    print('$st');
  }

  runApp(MecsaOpsApp(firebaseAvailable: firebaseAvailable));
}

class MecsaOpsApp extends StatelessWidget {
  final bool firebaseAvailable;
  const MecsaOpsApp({super.key, required this.firebaseAvailable});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppProvider(firebaseAvailable: firebaseAvailable),
        ),
        ChangeNotifierProvider<OfflineService>.value(
          value: OfflineService.instance,
        ),
        ChangeNotifierProvider<ConnectivityService>.value(
          value: ConnectivityService.instance,
        ),
        ChangeNotifierProvider<SyncService>.value(
          value: SyncService.instance,
        ),
      ],
      child: MaterialApp(
        title: 'MecsaOPS Mobile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Consumer<AppProvider>(
          builder: (context, provider, _) {
            // If user is logged in, show Home, else Login
            if (provider.user != null) {
              return const HomeScreen();
            }
            return const LoginScreen();
          },
        ),
      ),
    );
  }
}
