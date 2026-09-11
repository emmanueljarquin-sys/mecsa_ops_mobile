import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/mensajes_error.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/liquidacion.dart';
import '../services/liquidaciones_service.dart';
import '../services/liquidaciones_local.dart';
import '../services/offline_service.dart';
import 'liquidacion_detail_screen.dart';
import 'liquidacion_form_screen.dart';
import 'liquidaciones_historial_screen.dart';

class ViaticosScreen extends StatefulWidget {
  const ViaticosScreen({super.key});

  @override
  State<ViaticosScreen> createState() => _ViaticosScreenState();
}

class _ViaticosScreenState extends State<ViaticosScreen> {
  List<Liquidacion> liquidaciones = [];
  // true cuando la lista viene de SQLite porque no hubo red.
  bool desdeLocal = false;
  bool isLoading = false;
  String? error;
  String selectedFilter = 'todos';
  int currentPage = 1;
  bool hasMore = true;

  @override
  void initState() {
    super.initState();
    // No cargamos aquí directamente, dejaremos que didChangeDependencies o un check inicial lo haga
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    // Disparar carga si tenemos el ID y no hay datos/errores previos
    if (provider.currentEmployeeId != null && liquidaciones.isEmpty && error == null) {
      // Solo si no estamos ya en proceso de carga real (no el de espera)
      _loadLiquidaciones();
    }
  }

  Future<void> _loadLiquidaciones({bool refresh = false}) async {
    if (isLoading && !refresh) return;

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
      final provider = Provider.of<AppProvider>(context, listen: false);
      
      // Esperar si el provider está cargando datos iniciales
      if (provider.isLoading && provider.currentEmployeeId == null) {
        setState(() => isLoading = true);
        return;
      }

      final empleadoId = provider.currentEmployeeId;

      if (empleadoId == null) {
        print('UI DEBUG: No se puede cargar liquidaciones sin empleadoId');
        setState(() {
          isLoading = false;
          error = "No se encontró tu perfil de empleado. Por favor, reintenta o contacta a soporte.";
        });
        return;
      }

      final String? estadoFilter = selectedFilter == 'todos'
          ? null
          : selectedFilter;

      // Creadas sin conexión (todavía en la cola): siempre arriba, página 1.
      final pendientesLocales = (currentPage == 1 &&
              (estadoFilter == null || estadoFilter == 'pendiente'))
          ? await LiquidacionesLocal.instance
              .listar(empleadoId, soloLocales: true)
          : <Liquidacion>[];

      List<Liquidacion> remotas;
      bool masPaginas;
      bool local = false;
      try {
        if (!await OfflineService.instance.hayConexion()) {
          throw Exception('sin conexión');
        }
        final result = await LiquidacionesService.getLiquidaciones(
          empleadoId: empleadoId,
          estado: estadoFilter,
          page: currentPage,
          limit: 20,
        );
        remotas = List<Liquidacion>.from(result['liquidaciones']);
        masPaginas = remotas.length >= 20;
      } catch (e) {
        // Sin red o servidor caído: mostrar lo guardado en SQLite (último mes).
        if (currentPage != 1) rethrow;
        remotas = (await LiquidacionesLocal.instance
                .listar(empleadoId, estado: estadoFilter))
            .where((l) => !l.esLocal)
            .toList();
        masPaginas = false;
        local = true;
      }

      if (!mounted) return;
      setState(() {
        desdeLocal = local;
        if (refresh || currentPage == 1) {
          liquidaciones = [...pendientesLocales, ...remotas];
        } else {
          liquidaciones.addAll(remotas);
        }
        hasMore = masPaginas;
      });
    } catch (e) {
      print('UI ERROR: $e');
      if (!mounted) return;
      setState(() {
        error = mensajeError(e, accion: 'cargar las liquidaciones');
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

  /// Liquidación creada sin conexión: aún no tiene id en el servidor, así que
  /// no se puede abrir el detalle remoto. Se muestra un resumen local.
  void _mostrarPendienteLocal(Liquidacion l) {
    final facturas = l.facturas ?? [];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload_outlined, color: Colors.orange.shade800),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Pendiente de subir',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Esta liquidación se guardó sin conexión. Se subirá automáticamente cuando haya internet.',
              style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text('Fecha: ${l.fecha.toIso8601String().split('T').first}'),
            Text('Tipo: ${l.tipo}'),
            if (l.descripcion != null && l.descripcion!.isNotEmpty)
              Text('Descripción: ${l.descripcion}'),
            const SizedBox(height: 12),
            Text('Facturas (${facturas.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            ...facturas.map((f) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt),
                  title: Text('${f.proveedor} · ${f.tipoLabel}'),
                  subtitle: Text('#${f.numeroFactura}'),
                  trailing: Text('₡${f.monto.toStringAsFixed(0)}'),
                )),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Total: ₡${l.totalGeneral.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToDetail(Liquidacion liquidacion) async {
    if (liquidacion.esLocal) {
      _mostrarPendienteLocal(liquidacion);
      return;
    }
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
      backgroundColor: AppColors.of(context).background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Liquidaciones',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.of(context).textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Gestión de viáticos',
                        style: TextStyle(fontSize: 14, color: AppColors.of(context).textSecondary),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LiquidacionesHistorialScreen()),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          side: BorderSide(color: Theme.of(context).colorScheme.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('Historial', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _navigateToForm(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nueva', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ],
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

            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Provider.of<AppProvider>(context, listen: false).fetchData();
                  await _loadLiquidaciones(refresh: true);
                },
                child: error != null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
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
                                    color: AppColors.of(context).textSecondary,
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
                          ),
                        ],
                      )
                    : isLoading && liquidaciones.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : liquidaciones.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.6,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.description_outlined,
                                          size: 64,
                                          color: AppColors.of(context).textMuted,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No hay liquidaciones',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.of(context).textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Crea tu primera liquidación',
                                          style: TextStyle(color: AppColors.of(context).textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: liquidaciones.length + (hasMore ? 1 : 0) + (desdeLocal ? 1 : 0),
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  if (desdeLocal) {
                                    if (index == 0) {
                                      return Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.of(context).surfaceVariant,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.wifi_off, size: 18, color: AppColors.of(context).textSecondary),
                                            const SizedBox(width: 8),
                                            const Expanded(
                                              child: Text(
                                                'Sin conexión: mostrando liquidaciones guardadas (último mes).',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    index -= 1;
                                  }
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
              color: isSelected ? Theme.of(context).primaryColor : AppColors.of(context).surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : AppColors.of(context).surfaceVariant!,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.of(context).textSecondary,
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
          color: AppColors.of(context).surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.of(context).shadow,
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
                    color: liquidacion.esLocal
                        ? Colors.orange.shade50
                        : const Color(0xFFE7F1FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    liquidacion.esLocal
                        ? Icons.cloud_upload_outlined
                        : Icons.receipt_long,
                    color: liquidacion.esLocal
                        ? Colors.orange.shade800
                        : Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        liquidacion.empleadoCompleto,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.of(context).textPrimary,
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.of(context).textPrimary,
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
