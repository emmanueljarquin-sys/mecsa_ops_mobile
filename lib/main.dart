import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  await Supabase.initialize(
    url: 'https://awhuzekjpoapamijlvua.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF3aHV6ZWtqcG9hcGFtaWpsdnVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE1NzM2ODMsImV4cCI6MjA3NzE0OTY4M30.2wnEN8HG2LA3CRhDbHQdu7drrsF7-G7zg-CCt7rqkeQ',
  );

  bool firebaseAvailable = false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    firebaseAvailable = true;
    print("Firebase inicializado correctamente");
  } catch (e) {
    print("Firebase initialization failed: $e");
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
        )
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
