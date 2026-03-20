import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import '../widgets/bottom_nav.dart';
import 'flotilla_screen.dart';
import 'viaticos_screen.dart';
import 'visitas_screen.dart';
import 'profile_screen.dart'; // Import nuevo perfil

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate();
    });
  }

  void _checkUpdate() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.updateUrl != null) {
      _showUpdateDialog(provider);
    }
  }

  void _showUpdateDialog(AppProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: !provider.forceUpdate,
      builder: (context) => WillPopScope(
        onWillPop: () async => !provider.forceUpdate,
        child: AlertDialog(
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
            if (!provider.forceUpdate)
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    // Mapeo de pantallas (Lazy loading básico)
    final List<Widget> screens = [
      const DashboardTab(),
      const FlotillaScreen(),
      const ViaticosScreen(),
      const VisitasScreen(),
      const ProfileScreen(), // Nueva pantalla
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: provider.currentIndex, children: screens),
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
      // Asumimos que vienen ordenadas por fecha desde la API
      nextReservation = provider.myReservations.first;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Custom Header
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/logo_mecsa_ops.jpg',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                "MecsaOPS",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Color(0xFF212529),
                ),
              ),
              const Spacer(),
              Stack(
                children: [
                  const Icon(
                    Icons.notifications_outlined,
                    size: 28,
                    color: Colors.grey,
                  ),
                  if (pendientes > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
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
                          backgroundColor: Colors.grey[200],
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
                  backgroundColor: Colors.grey[200],
                  backgroundImage: emp?['photo'] != null
                      ? NetworkImage(emp!['photo'])
                      : const NetworkImage('https://i.pravatar.cc/150?img=11'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 2. Greeting
          Text(
            "Hola, $fullName",
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212529),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Aquí tienes tu resumen de operaciones.",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),

          const SizedBox(height: 24),

          // 3. Main Action Buttons
          Row(
            children: [
              Expanded(
                child: _MainActionButton(
                  icon: Icons.location_on,
                  label: "Registrar Visita",
                  color: Theme.of(context).primaryColor,
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
                  color: Colors.white,
                  textColor: const Color(0xFF212529),
                  borderColor: Colors.grey[200],
                  onTap: () {
                    // Nav to Viaticos
                    provider.setIndex(2);
                  },
                ),
              ),
            ],
          ),

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
                      color: Colors.grey[300],
                      child:
                          nextReservation['vehiculos'] != null &&
                              nextReservation['vehiculos']['foto'] != null
                          ? Image.network(
                              nextReservation['vehiculos']['foto']
                                      .toString()
                                      .startsWith('http')
                                  ? nextReservation['vehiculos']['foto']
                                  : Supabase.instance.client.storage
                                        .from('flotilla')
                                        .getPublicUrl(
                                          nextReservation['vehiculos']['foto'],
                                        ),
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, _, __) => const Icon(
                                Icons.directions_car,
                                size: 40,
                                color: Colors.grey,
                              ),
                            )
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
                      Text("Versión App: 1.0.0"),
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
                  backgroundColor: Colors.grey[200],
                  backgroundImage: emp?['photo'] != null
                      ? NetworkImage(emp!['photo'])
                      : const NetworkImage('https://i.pravatar.cc/150?img=11'),
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
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
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
              color: Colors.black.withOpacity(0.05),
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
                color: Colors.white.withOpacity(
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF495057),
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
