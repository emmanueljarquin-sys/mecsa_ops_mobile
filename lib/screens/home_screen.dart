import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_image.dart';
import '../widgets/animated_tabs.dart';
import '../services/notificaciones_service.dart';
import 'notifications_screen.dart';
import 'chat_list_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../providers/app_provider.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/connection_banner.dart';
import 'flotilla_screen.dart';
import 'viaticos_screen.dart';
import 'visitas_screen.dart';
import 'visita_detail_screen.dart';
import 'profile_screen.dart';
import 'live_map_screen.dart';
import 'admin/admin_hub_screen.dart';
import 'auditorias/auditorias_list_screen.dart';
import '../services/offline_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _didShowOptionalUpdate = false;
  bool _sessionDialogShowing = false;

  /// Modal de sesión expirada: "Renovar sesión" (usa el refresh token) o
  /// "Cerrar sesión". Se muestra cuando provider.sessionExpired pasa a true y
  /// se cierra solo cuando vuelve a false (renovación OK o cierre forzado).
  void _syncSessionDialog(AppProvider provider) {
    if (provider.sessionExpired && !_sessionDialogShowing) {
      _sessionDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: Consumer<AppProvider>(
              builder: (ctx, p, _) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                icon: const Icon(Icons.lock_clock_outlined,
                    size: 40, color: Colors.orange),
                title: const Text('Tu sesión expiró'),
                content: const Text(
                  'El servidor ya no acepta la sesión guardada en este teléfono. '
                  'Podés intentar renovarla sin volver a escribir la contraseña. '
                  'Si no se puede, tendrás que iniciar sesión de nuevo.',
                ),
                actionsAlignment: MainAxisAlignment.spaceBetween,
                actions: [
                  TextButton(
                    onPressed: p.renovandoSesion
                        ? null
                        : () async {
                            await p.signOut();
                          },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('CERRAR SESIÓN'),
                  ),
                  ElevatedButton.icon(
                    onPressed: p.renovandoSesion
                        ? null
                        : () async {
                            final ok = await p.renovarSesion();
                            if (!mounted) return;
                            final messenger = ScaffoldMessenger.of(context);
                            if (ok) {
                              messenger.showSnackBar(
                                const SnackBar(
                                    content: Text('Sesión renovada'),
                                    backgroundColor: Colors.green),
                              );
                            } else if (p.user != null) {
                              // Falló por red: seguimos en el modal.
                              messenger.showSnackBar(
                                SnackBar(
                                    content: Text(p.errorMessage ??
                                        'No se pudo renovar la sesión'),
                                    backgroundColor: Colors.orange),
                              );
                            }
                          },
                    icon: p.renovandoSesion
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh),
                    label: const Text('RENOVAR SESIÓN'),
                  ),
                ],
              ),
            ),
          ),
        );
        _sessionDialogShowing = false;
      });
    } else if (!provider.sessionExpired && _sessionDialogShowing) {
      // Renovación OK o sesión cerrada: quitar el modal.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sessionDialogShowing) {
          Navigator.of(context, rootNavigator: true)
              .popUntil((r) => r.isFirst || !_sessionDialogShowing);
          _sessionDialogShowing = false;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // La inicialización se hace después del primer frame para tener acceso al provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      if (provider.firebaseAvailable) {
        _initFCMListeners();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Al volver a primer plano, refrescar en silencio para reflejar cambios
    // hechos desde la web (p. ej. una reserva ya aprobada).
    if (state == AppLifecycleState.resumed && mounted) {
      Provider.of<AppProvider>(context, listen: false).refreshSilent();
    }
  }

  void _initFCMListeners() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.firebaseAvailable) return;

    // Notificación recibida con app EN PRIMER PLANO
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      // Guardar en la campana (centro de notificaciones).
      NotificacionesService.instance.agregar(
        titulo: message.notification?.title ??
            (data['tipo'] == 'pago_kilometraje' ? 'Pago de kilometraje confirmado' : 'Notificación'),
        cuerpo: message.notification?.body ??
            (data['tipo'] == 'pago_kilometraje'
                ? 'Tu pago de kilometraje fue confirmado. Revisa el comprobante en tu visita.'
                : data.toString()),
        tipo: data['tipo'] == 'pago_kilometraje' ? 'visita' : 'info',
        data: Map<String, dynamic>.from(data),
      );
      if (data['tipo'] == 'pago_kilometraje' && mounted) {
        _showPagoBanner(data['visita_id']);
      }
    });

    // Usuario tocó la notificación con app en segundo plano
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final data = message.data;
      if (data['tipo'] == 'pago_kilometraje' && mounted) {
        _navigateToVisitaFromNotification(data['visita_id']);
      }
    });

    // App abierta desde notificación (app estaba cerrada)
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null && mounted) {
        final data = message.data;
        if (data['tipo'] == 'pago_kilometraje') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateToVisitaFromNotification(data['visita_id']);
          });
        }
      }
    });
  }

  void _showPagoBanner(String? visitaId) {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: const Color(0xFFEFF6FF),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        leading: const Icon(Icons.check_circle, color: Color(0xFF1D4ED8), size: 28),
        content: Text(
          '¡Tu pago de kilometraje fue confirmado! Ver comprobante en tu visita.',
          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.of(context).textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _navigateToVisitaFromNotification(visitaId);
            },
            child: const Text('VER', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }

  void _navigateToVisitaFromNotification(String? visitaId) {
    // Navegar a la tab de visitas
    final provider = context.read<AppProvider>();
    provider.setIndex(3);
    // Si tenemos el ID, buscamos la visita y abrimos el detalle
    if (visitaId != null && visitaId.isNotEmpty) {
      final visita = provider.visitas.firstWhere(
        (v) => v['id'].toString() == visitaId,
        orElse: () => {},
      );
      if (visita.isNotEmpty && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VisitaDetailScreen(visita: visita),
          ),
        );
      }
    }
  }

  void _showUpdateDialog(AppProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Colors.blue),
            SizedBox(width: 10),
            Text("Actualización"),
          ],
        ),
        content: Text(
          provider.notificationMessage ??
              "Hay una nueva versión de MecsaOPS disponible con mejoras importantes.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("DESPUÉS"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final urlString = provider.updateUrl ?? "https://grupomecsa.net/ops/";
              final url = Uri.parse(urlString);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text("ACTUALIZAR AHORA"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    // Bloqueo total si la actualización es forzosa
    if (provider.forceUpdate && provider.updateUrl != null) {
      return Scaffold(
        backgroundColor: AppColors.of(context).surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update_alt, size: 80, color: Colors.blue),
                const SizedBox(height: 24),
                Text(
                  "Actualización Requerida",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.of(context).textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  provider.notificationMessage ?? "Debes actualizar a la última versión para continuar.",
                  style: TextStyle(fontSize: 16, color: AppColors.of(context).textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      final url = Uri.parse(provider.updateUrl!);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: const Text(
                      "ACTUALIZAR EN PLAY STORE",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Modal de sesión expirada (renovar / cerrar sesión)
    _syncSessionDialog(provider);

    // Modal opcional si hay una update pero no es forzosa
    if (provider.updateUrl != null && !provider.forceUpdate && !_didShowOptionalUpdate) {
      _didShowOptionalUpdate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showUpdateDialog(provider);
      });
    }

    // Mapeo de pantallas (Lazy loading básico)
    // Chat CRM solo para roles con acceso (se inserta antes de Perfil).
    final List<Widget> screens = [
      const DashboardTab(),
      const FlotillaScreen(),
      const ViaticosScreen(),
      const VisitasScreen(),
      if (provider.puedeVerChat) const ChatListScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Aviso global: sin internet o carga fallida (datos desde caché).
            const ConnectionBanner(),
            Expanded(
              // Cambio de pestaña animado (desliza + desvanece) conservando
              // el estado de cada pantalla como hacía IndexedStack.
              child: AnimatedTabs(index: provider.currentIndex, children: screens),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNav(),
    );
  }
}

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Usamos valores del Provider o Dummys para matchear la imagen
    final provider = Provider.of<AppProvider>(context);

    // --- Lógica de Datos ---
    final emp = provider.currentEmployeeData; // Datos reales

    // 1. Nombre de Usuario
    String fullName = "Usuario";
    if (emp != null) {
      final n = emp['nombre'] ?? '';
      final a = emp['apellido'] ?? '';
      if (n.isNotEmpty || a.isNotEmpty) {
        fullName = "$n $a".trim();
      } else if (emp['nombre_completo'] != null) {
        fullName = emp['nombre_completo'];
      }
    } else if (provider.user?.email != null) {
      fullName = provider.user!.email!.split('@')[0];
      fullName = fullName[0].toUpperCase() + fullName.substring(1);
    }

    // 2. Viáticos Stats
    final double totalViaticos = provider.gastos.fold(
      0.0,
      (sum, item) => sum + (double.tryParse(item['monto'].toString()) ?? 0.0),
    );
    final int pendientes = provider.liquidacionesPendientes;

    // 3. Próxima Reserva
    Map<String, dynamic>? nextReservation;
    if (provider.myReservations.isNotEmpty) {
      // Asumimos que vienen ordenadas por fecha desde la API (ascendente)
      // Buscamos la primera que no esté cancelada, rechazada o completada
      try {
        nextReservation = provider.myReservations.firstWhere((r) {
          final estado = (r['estado'] ?? '').toString().toUpperCase();
          return !estado.contains('CANCEL') &&
              !estado.contains('RECHAZ') &&
              !estado.contains('COMPLET');
        });
      } catch (_) {
        nextReservation = null;
      }
    }

    return RefreshIndicator(
      onRefresh: () => provider.fetchData(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Custom Header
            Row(
              children: [
                SvgPicture.asset(
                  'assets/images/ops_icon_color.svg',
                  width: 40,
                  height: 40,
                ),
                const SizedBox(width: 12),
                Text(
                  "MecsaOPS",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppColors.of(context).textPrimary,
                  ),
                ),
                const Spacer(),
                // Botón Administración (solo si tiene alguna función admin)
                if (provider.hasAdminAccess) ...[
                  IconButton(
                    tooltip: 'Administración',
                    icon: Icon(Icons.admin_panel_settings,
                        size: 26, color: Theme.of(context).primaryColor),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminHubScreen()),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Consumer<NotificacionesService>(
                  builder: (context, notif, _) => IconButton(
                    tooltip: 'Notificaciones',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    ),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          notif.noLeidas > 0 ? Icons.notifications_active : Icons.notifications_outlined,
                          size: 28,
                          color: notif.noLeidas > 0
                              ? Theme.of(context).colorScheme.primary
                              : AppColors.of(context).textSecondary,
                        ),
                        if (notif.noLeidas > 0 || pendientes > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              constraints: const BoxConstraints(minWidth: 16),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                              ),
                              child: Text(
                                notif.noLeidas > 0 ? '${notif.noLeidas}' : '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                PopupMenuButton<String>(
                  offset: const Offset(0, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  onSelected: (value) {
                    if (value == 'logout') {
                      provider.signOut();
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'profile',
                      enabled: false,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.of(context).surfaceVariant,
                            child: const Icon(
                              Icons.person,
                              size: 20,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provider.user?.email ?? 'Usuario',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const Text(
                                "Empleado",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            "Cerrar Sesión",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.of(context).surfaceVariant,
                    backgroundImage: emp?['photo'] != null
                        ? NetworkImage(() {
                            final raw = emp!['photo'];
                            if (raw is String) return raw;
                            if (raw is Map) return (raw['url'] ?? raw['path'] ?? '').toString();
                            return '';
                          }())
                        : null,
                    onBackgroundImageError: emp?['photo'] != null ? (_, __) {} : null,
                    child: emp?['photo'] == null
                        ? const Icon(Icons.person, color: Colors.grey)
                        : null,
                  ),
                ),
              ],
            ),
  
            const SizedBox(height: 24),
  
            // 2. Greeting
            Text(
              "Hola, $fullName",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.of(context).textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Aquí tienes tu resumen de operaciones.",
              style: TextStyle(fontSize: 16, color: AppColors.of(context).textSecondary),
            ),
  
            const SizedBox(height: 24),

            // Pendientes de sincronizar (offline)
            Consumer<OfflineService>(
              builder: (_, offline, __) {
                if (offline.pendingCount == 0) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(offline.isFlushing ? Icons.sync : Icons.cloud_upload_outlined,
                          color: Colors.orange.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          offline.isFlushing
                              ? 'Subiendo ${offline.pendingCount} pendiente(s)…'
                              : '${offline.pendingCount} pendiente(s) de subir (sin conexión)',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                        ),
                      ),
                      if (offline.isFlushing)
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        TextButton(onPressed: () => offline.flush(), child: const Text('Sincronizar')),
                    ],
                  ),
                );
              },
            ),

            // 3. Main Action Buttons
            Row(
              children: [
                Expanded(
                  child: _MainActionButton(
                    icon: Icons.location_on,
                    label: "Registrar Visita",
                    color: Theme.of(context).colorScheme.primary,
                    textColor: Colors.white,
                    onTap: () {
                      // Nav to Visitas or Form
                      provider.setIndex(3); // Navigate to Visitas Tab
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _MainActionButton(
                    icon: Icons.camera_alt_outlined,
                    label: "Subir Factura",
                    color: AppColors.of(context).surface,
                    textColor: AppColors.of(context).textPrimary,
                    borderColor: AppColors.of(context).surfaceVariant,
                    onTap: () {
                      // Nav to Viaticos
                      provider.setIndex(2);
                    },
                  ),
                ),
              ],
            ),

            // 3.1 Auditoría de Vehículo (solo con permiso al módulo 'auditorias')
            if (provider.canAudit) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MainActionButton(
                      icon: Icons.fact_check_outlined,
                      label: "Auditoría de Vehículo",
                      color: AppColors.of(context).surface,
                      textColor: AppColors.of(context).textPrimary,
                      borderColor: AppColors.of(context).surfaceVariant,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AuditoriasListScreen()),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // 4. Mis Viáticos Card
            _DashboardCard(
              title: "Mis Viáticos",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "₡${totalViaticos.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatusBadge(
                        text: "$pendientes pendientes",
                        color: const Color(0xFFFFF3CD),
                        textColor: const Color(0xFF856404),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "de aprobación",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              actionLabel: "Ver todo >",
              onActionTap: () => provider.setIndex(2),
              icon: Icons.trending_up,
            ),
  
            const SizedBox(height: 16),
  
            // 5. Próxima Reserva Card
            if (nextReservation != null)
              _DashboardCard(
                title: "Próxima Reserva",
                actionLabel: "Flotilla >",
                onActionTap: () => provider.setIndex(1),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 70,
                        height: 70,
                        color: AppColors.of(context).surfaceVariant,
                        child: nextReservation['vehiculos'] != null &&
                                nextReservation['vehiculos']['foto'] != null
                            ? Builder(builder: (ctx) {
                                // foto puede ser String o Map<String, dynamic>
                                final dynamic rawFoto =
                                    nextReservation!['vehiculos']['foto'];
                                String fotoUrl = '';
                                if (rawFoto is String) {
                                  fotoUrl = rawFoto;
                                } else if (rawFoto is Map) {
                                  fotoUrl = (rawFoto['url'] ?? rawFoto['path'] ?? '').toString();
                                }
                                if (fotoUrl.isEmpty) {
                                  return const Icon(Icons.directions_car, size: 40, color: Colors.grey);
                                }
                                final String finalUrl = fotoUrl.startsWith('http')
                                    ? fotoUrl
                                    : Supabase.instance.client.storage
                                        .from('flotilla')
                                        .getPublicUrl(fotoUrl);
                                return CachedImage(
                                  finalUrl,
                                  fit: BoxFit.cover,
                                  fallbackIcon: Icons.directions_car,
                                  fallbackSize: 40,
                                );
                              })
                            : const Icon(
                                Icons.directions_car,
                                size: 40,
                                color: Colors.grey,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nextReservation['vehiculos'] != null
                                ? "${nextReservation['vehiculos']['marca'] ?? ''} ${nextReservation['vehiculos']['modelo'] ?? ''}"
                                : "Vehículo Reservado",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Salida: ${nextReservation['fecha_salida']?.substring(0, 10) ?? 'N/A'}",
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            nextReservation['estado'] ?? 'Confirmada',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              const _DashboardCard(
                title: "Próxima Reserva",
                child: Text("No tienes reservas activas."),
                icon: Icons.directions_car,
              ),
  
            const SizedBox(height: 16),
  
            // 6. Mi Perfil Card (Reemplaza Visitas)
            _DashboardCard(
              title: "Mi Perfil",
              actionLabel: "Ver detalles >",
              onActionTap: () {
                // Mostrar dialog o navegar a perfil si existiera pantalla
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Información de Perfil"),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Email: ${provider.user?.email ?? 'N/A'}"),
                        const SizedBox(height: 8),
                        Text(
                          "ID Empleado: ${provider.currentEmployeeId ?? 'N/A'}",
                        ),
                        const SizedBox(height: 8),
                        Text("Versión App: 1.1.2"),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cerrar"),
                      ),
                    ],
                  ),
                );
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.of(context).surfaceVariant,
                    backgroundImage: emp?['photo'] != null
                        ? NetworkImage(() {
                            final raw = emp!['photo'];
                            if (raw is String) return raw;
                            if (raw is Map) return (raw['url'] ?? raw['path'] ?? '').toString();
                            return '';
                          }())
                        : null,
                    onBackgroundImageError: emp?['photo'] != null ? (_, __) {} : null,
                    child: emp?['photo'] == null
                        ? const Icon(Icons.person, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          provider.getDepartmentName(emp?['departamento']),
                          style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: emp?['activo'] == true
                                ? Colors.green[50]
                                : Colors.blue[50], // Light blue
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color:
                                  (emp?['activo'] == true
                                          ? Colors.green
                                          : Colors.blue)
                                      .withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            emp?['rol'] ?? "Empleado Activo",
                            style: TextStyle(
                              color: emp?['activo'] == true
                                  ? Colors.green[800]
                                  : Colors.blue[800],
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
  
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// --- Widgets Locales Dashboard ---

class _MainActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final Color? borderColor;
  final VoidCallback onTap;

  const _MainActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: borderColor != null ? Border.all(color: borderColor!) : null,
          boxShadow: [
            BoxShadow(
              color: AppColors.of(context).shadow,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.of(context).surface.withOpacity(
                  0.2,
                ), // Subtle overlay for icon bg
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: textColor),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final Widget child;
  final IconData? icon;

  const _DashboardCard({
    required this.title,
    this.actionLabel,
    this.onActionTap,
    required this.child,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.of(context).shadow,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
              if (actionLabel != null)
                InkWell(
                  onTap: onActionTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      actionLabel!,
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _StatusBadge({
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
