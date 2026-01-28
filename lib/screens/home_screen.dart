import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/bottom_nav.dart';
import 'flotilla_screen.dart';
import 'viaticos_screen.dart';
import 'visitas_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    // Mapeo de pantallas (Lazy loading básico)
    final List<Widget> screens = [
      const DashboardTab(),
      const FlotillaScreen(),
      const ViaticosScreen(),
      const VisitasScreen(),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Custom Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D6EFD), // Brand Blue
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    "M",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
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
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey,
                backgroundImage: NetworkImage(
                  'https://i.pravatar.cc/150?img=11',
                ), // Dummy Avatar
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 2. Greeting
          const Text(
            "Hola, Emmanuel",
            style: TextStyle(
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
                  color: const Color(0xFF0D6EFD),
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
          const _DashboardCard(
            title: "Mis Viáticos (Oct)",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "\$5,750.50 MXN",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    _StatusBadge(
                      text: "2 pendientes",
                      color: Color(0xFFFFF3CD),
                      textColor: Color(0xFF856404),
                    ),
                    SizedBox(width: 8),
                    Text("de aprobación", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ],
            ),
            actionLabel: "Ver todo >",
            icon: Icons.trending_up, // Icono decorativo si se desea
          ),

          const SizedBox(height: 16),

          // 5. Próxima Reserva Card
          _DashboardCard(
            title: "Próxima Reserva",
            actionLabel: "Flotilla >",
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 70,
                    height: 70,
                    color: Colors.grey[300],
                    child: const Icon(
                      Icons.directions_car,
                      size: 40,
                      color: Colors.grey,
                    ), // Placeholder img
                  ),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Nissan NP300",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text("2023-11-05", style: TextStyle(color: Colors.grey)),
                    SizedBox(height: 4),
                    Text(
                      "Confirmada",
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 6. Visitas Hoy Card
          const _DashboardCard(
            title: "Visitas Hoy",
            actionLabel: "Agenda >",
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "1",
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Visitas programadas",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xFFF3E5F5), // Light purple
                  child: Icon(Icons.location_on, color: Color(0xFF9C27B0)),
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
  final Widget child;
  final IconData? icon;

  const _DashboardCard({
    required this.title,
    this.actionLabel,
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
                Text(
                  actionLabel!,
                  style: const TextStyle(
                    color: Color(0xFF0D6EFD),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
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
