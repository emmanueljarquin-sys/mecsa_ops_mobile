import 'package:flutter/material.dart';
import '../models/liquidacion.dart';
import '../services/liquidaciones_service.dart';
import 'liquidacion_detail_screen.dart';
import 'liquidacion_form_screen.dart';

class ViaticosScreen extends StatefulWidget {
  const ViaticosScreen({super.key});

  @override
  State<ViaticosScreen> createState() => _ViaticosScreenState();
}

class _ViaticosScreenState extends State<ViaticosScreen> {
  List<Liquidacion> liquidaciones = [];
  bool isLoading = true;
  String? error;
  String selectedFilter = 'todos';
  int currentPage = 1;
  bool hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadLiquidaciones();
  }

  Future<void> _loadLiquidaciones({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        currentPage = 1;
        liquidaciones.clear();
        hasMore = true;
      });
    }

    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final String? estadoFilter = selectedFilter == 'todos'
          ? null
          : selectedFilter;

      final result = await LiquidacionesService.getLiquidaciones(
        estado: estadoFilter,
        page: currentPage,
        limit: 20,
      );

      setState(() {
        if (refresh) {
          liquidaciones = result['liquidaciones'];
        } else {
          liquidaciones.addAll(result['liquidaciones']);
        }
        hasMore = result['liquidaciones'].length >= 20;
      });
    } catch (e) {
      print('UI ERROR: $e');
      setState(() {
        error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _changeFilter(String filter) {
    if (selectedFilter != filter) {
      setState(() {
        selectedFilter = filter;
      });
      _loadLiquidaciones(refresh: true);
    }
  }

  Future<void> _navigateToForm({Liquidacion? liquidacion}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiquidacionFormScreen(liquidacion: liquidacion),
      ),
    );

    if (result == true) {
      _loadLiquidaciones(refresh: true);
    }
  }

  Future<void> _navigateToDetail(Liquidacion liquidacion) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LiquidacionDetailScreen(liquidacionId: liquidacion.id),
      ),
    );

    if (result == true) {
      _loadLiquidaciones(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Liquidaciones',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF212529),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Gestión de viáticos',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => _navigateToForm(),
                      icon: const Icon(Icons.add, color: Colors.white),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),

            // Filters
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterChip(
                    label: "Todos",
                    isSelected: selectedFilter == 'todos',
                    onTap: () => _changeFilter('todos'),
                  ),
                  _FilterChip(
                    label: "Pendientes",
                    isSelected: selectedFilter == 'pendiente',
                    onTap: () => _changeFilter('pendiente'),
                  ),
                  _FilterChip(
                    label: "Aprobadas",
                    isSelected: selectedFilter == 'aprobada',
                    onTap: () => _changeFilter('aprobada'),
                  ),
                  _FilterChip(
                    label: "Rechazadas",
                    isSelected: selectedFilter == 'rechazada',
                    onTap: () => _changeFilter('rechazada'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // List
            Expanded(
              child: error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error al cargar',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _loadLiquidaciones(refresh: true),
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    )
                  : isLoading && liquidaciones.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : liquidaciones.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No hay liquidaciones',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Crea tu primera liquidación',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadLiquidaciones(refresh: true),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: liquidaciones.length + (hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == liquidaciones.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final liquidacion = liquidaciones[index];
                          return _LiquidacionCard(
                            liquidacion: liquidacion,
                            onTap: () => _navigateToDetail(liquidacion),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).primaryColor : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.grey[300]!,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF495057),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidacionCard extends StatelessWidget {
  final Liquidacion liquidacion;
  final VoidCallback onTap;

  const _LiquidacionCard({required this.liquidacion, required this.onTap});

  Color _getStatusColor() {
    switch (liquidacion.estado) {
      case 'pendiente':
        return const Color(0xFFFFF3CD);
      case 'aprobada':
        return const Color(0xFFD1E7DD);
      case 'rechazada':
        return const Color(0xFFF8D7DA);
      default:
        return const Color(0xFFE2E3E5);
    }
  }

  Color _getStatusTextColor() {
    switch (liquidacion.estado) {
      case 'pendiente':
        return const Color(0xFF856404);
      case 'aprobada':
        return const Color(0xFF0F5132);
      case 'rechazada':
        return const Color(0xFF842029);
      default:
        return const Color(0xFF383D41);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F1FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.receipt_long,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        liquidacion.empleadoCompleto,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF212529),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        liquidacion.proyectoNombre ?? 'Sin proyecto',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${liquidacion.fecha.day}/${liquidacion.fecha.month}/${liquidacion.fecha.year}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    liquidacion.estadoLabel.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusTextColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  '₡${liquidacion.totalGeneral.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF212529),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
