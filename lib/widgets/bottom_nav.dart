import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return NavigationBar(
      selectedIndex: provider.currentIndex,
      onDestinationSelected: (index) {
        provider.setIndex(index);
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Inicio',
        ),
        const NavigationDestination(
          icon: Icon(Icons.car_rental_outlined),
          selectedIcon: Icon(Icons.car_rental),
          label: 'Flotilla',
        ),
        const NavigationDestination(
          icon: Icon(Icons.monetization_on_outlined),
          selectedIcon: Icon(Icons.monetization_on),
          label: 'Viáticos',
        ),
        const NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: 'Visitas',
        ),
        // Chat CRM (WhatsApp): solo roles con acceso.
        if (provider.puedeVerChat)
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Perfil',
        ),
      ],
    );
  }
}
