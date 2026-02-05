import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'visita_form_screen.dart';
import 'visita_detail_screen.dart';
import 'trip_nav_screen.dart';

class VisitasScreen extends StatefulWidget {
  const VisitasScreen({super.key});

  @override
  State<VisitasScreen> createState() => _VisitasScreenState();
}

class _VisitasScreenState extends State<VisitasScreen> {
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().refreshVisitas();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Consumer<AppProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading && provider.visitas.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.visitas.isEmpty) {
                    return _buildEmptyState();
                  }

                  return RefreshIndicator(
                    onRefresh: () => provider.refreshVisitas(),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.visitas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final v = provider.visitas[index];
                        final String id = v['id'].toString();
                        return _VisitaCard(
                          visita: v,
                          isSelected: _selectedIds.contains(id),
                          isSelectionMode: _isSelectionMode,
                          onLongPress: () => _toggleSelection(id),
                          onTap: () {
                            if (_isSelectionMode) {
                              _toggleSelection(id);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VisitaDetailScreen(visita: v),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Visitas',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
              Text(
                'Gestión de rutas comerciales',
                style: TextStyle(color: Colors.blueGrey[400], fontSize: 13),
              ),
            ],
          ),
          if (_selectedIds.length >= 2)
            ElevatedButton.icon(
              onPressed: () {
                final provider = context.read<AppProvider>();
                final List<Map<String, dynamic>> selectedVisitas = provider
                    .visitas
                    .where((v) => _selectedIds.contains(v['id'].toString()))
                    .toList();

                // Navegar a navegación multi-parada
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TripNavScreen(
                      entity:
                          selectedVisitas.first, // Tomamos la primera como base
                      destination: selectedVisitas.last['direccion'] ?? "",
                      waypoints: selectedVisitas
                          .sublist(0, selectedVisitas.length - 1)
                          .map((v) => v['direccion'].toString())
                          .toList(),
                      isVisita: true,
                      multiStops: selectedVisitas,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.route_rounded, size: 20),
              label: Text(
                "Ruta (${_selectedIds.length})",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VisitaFormScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                "Nueva",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            "No tienes visitas registradas",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            "Toca el botón + para agendar una",
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _VisitaCard extends StatelessWidget {
  final Map<String, dynamic> visita;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const _VisitaCard({
    required this.visita,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String estado = (visita['estado'] ?? 'programada')
        .toString()
        .toLowerCase();

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        elevation: isSelected ? 4 : 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? Colors.blue : Colors.grey,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      visita['cliente'] ?? 'Sin cliente',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  _buildStatusBadge(estado),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      visita['direccion'] ?? 'Ubicación pendiente',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        visita['fecha'] ?? '',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String estado) {
    Color color;
    switch (estado) {
      case 'completada':
        color = Colors.green;
        break;
      case 'en_curso':
        color = Colors.blue;
        break;
      case 'cancelada':
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
