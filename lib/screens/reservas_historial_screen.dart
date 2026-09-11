// =============================================================================
// reservas_historial_screen.dart — Flotilla → Historial de reservas
// -----------------------------------------------------------------------------
// Búsqueda de reservas pasadas. Un usuario normal ve solo las suyas; un
// administrador (rol admin) ve las de todos y puede filtrar por empleado.
// Filtros: texto (placa, vehículo, destino, motivo, empleado), estado y
// rango de fechas. Paginado de 30 en 30. Sin conexión muestra lo que hay
// en SQLite (solo las propias).
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/app_provider.dart';
import '../services/connectivity_service.dart';
import '../services/reservas_local.dart';
import '../theme/app_theme.dart';
import '../utils/mensajes_error.dart';
import '../widgets/cached_image.dart';
import '../widgets/offline_notice.dart';
import 'reservation_detail_screen.dart';

class ReservasHistorialScreen extends StatefulWidget {
  const ReservasHistorialScreen({super.key});

  @override
  State<ReservasHistorialScreen> createState() => _ReservasHistorialScreenState();
}

class _ReservasHistorialScreenState extends State<ReservasHistorialScreen> {
  static const int _pagina = 30;
  final _buscar = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _items = [];
  bool _cargando = false;
  bool _hayMas = true;
  bool _desdeLocal = false;
  String? _error;
  String _estado = 'todos';
  DateTimeRange? _rango;
  int _desde = 0;
  Map<String, String> _empleadosNombre = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300 && !_cargando && _hayMas) {
        _cargar();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar(reiniciar: true));
  }

  @override
  void dispose() {
    _buscar.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _esAdmin => context.read<AppProvider>().isRoleAdmin;

  Future<void> _cargar({bool reiniciar = false}) async {
    if (_cargando) return;
    final provider = context.read<AppProvider>();
    final empleadoId = provider.currentEmployeeId;
    if (empleadoId == null) return;
    if (reiniciar) {
      setState(() {
        _items = [];
        _desde = 0;
        _hayMas = true;
        _error = null;
      });
    }
    setState(() => _cargando = true);
    try {
      final online = await connectivity.checkInternet();
      if (!online) {
        // Sin red: solo las propias guardadas en SQLite.
        final locales = await ReservasLocal.instance.listar(empleadoId);
        if (!mounted) return;
        setState(() {
          _items = _filtrarLocal(locales);
          _hayMas = false;
          _desdeLocal = true;
          _cargando = false;
        });
        return;
      }
      final sb = Supabase.instance.client;
      var q = sb.schema('flotilla').from('reservas').select('*, vehiculos(*)');
      if (!_esAdmin) q = q.eq('empleado_id', empleadoId);
      if (_estado != 'todos') q = q.eq('estado', _estado);
      if (_rango != null) {
        q = q
            .gte('fecha_salida', _rango!.start.toIso8601String())
            .lte('fecha_salida', _rango!.end.add(const Duration(days: 1)).toIso8601String());
      }
      final texto = _buscar.text.trim();
      if (texto.isNotEmpty) {
        // Búsqueda por destino/motivo en la reserva; placa y modelo se filtran
        // en memoria sobre la página (el join no admite ilike directo).
        q = q.or('ubicacion.ilike.%$texto%,motivo.ilike.%$texto%,personal_incluido.ilike.%$texto%');
      }
      final res = await q
          .order('fecha_salida', ascending: false)
          .range(_desde, _desde + _pagina - 1)
          .timeout(const Duration(seconds: 25));
      var rows = List<Map<String, dynamic>>.from(res);

      // Nombres de empleados para el modo admin.
      if (_esAdmin) {
        final ids = rows.map((r) => r['empleado_id']?.toString()).whereType<String>().toSet()
          ..removeWhere(_empleadosNombre.containsKey);
        if (ids.isNotEmpty) {
          try {
            final emps = await sb
                .from('Empleados')
                .select('id, nombre, apellido')
                .inFilter('id', ids.toList())
                .timeout(const Duration(seconds: 15));
            for (final e in List<Map<String, dynamic>>.from(emps)) {
              _empleadosNombre[e['id'].toString()] = '${e['nombre'] ?? ''} ${e['apellido'] ?? ''}'.trim();
            }
          } catch (_) {}
        }
      }
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...rows];
        _desde += rows.length;
        _hayMas = rows.length == _pagina;
        _desdeLocal = false;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mensajeError(e, accion: 'cargar el historial');
        _cargando = false;
      });
    }
  }

  List<Map<String, dynamic>> _filtrarLocal(List<Map<String, dynamic>> lista) {
    final t = _buscar.text.trim().toLowerCase();
    return lista.where((r) {
      if (_estado != 'todos' && (r['estado'] ?? '').toString() != _estado) return false;
      final fs = DateTime.tryParse(r['fecha_salida']?.toString() ?? '');
      if (_rango != null && fs != null) {
        if (fs.isBefore(_rango!.start) || fs.isAfter(_rango!.end.add(const Duration(days: 1)))) return false;
      }
      if (t.isEmpty) return true;
      final v = r['vehiculos'] is Map ? r['vehiculos'] as Map : {};
      final campos = [r['ubicacion'], r['motivo'], r['personal_incluido'], v['placa'], v['marca'], v['modelo']];
      return campos.any((c) => (c ?? '').toString().toLowerCase().contains(t));
    }).toList();
  }

  /// Filtro en memoria por placa/modelo sobre lo ya cargado (complemento
  /// a la búsqueda del servidor por destino/motivo).
  List<Map<String, dynamic>> get _visibles {
    final t = _buscar.text.trim().toLowerCase();
    if (t.isEmpty || _desdeLocal) return _items;
    return _items.where((r) {
      final v = r['vehiculos'] is Map ? r['vehiculos'] as Map : {};
      final campos = [r['ubicacion'], r['motivo'], r['personal_incluido'], v['placa'], v['marca'], v['modelo'],
        _empleadosNombre[r['empleado_id']?.toString()]];
      return campos.any((c) => (c ?? '').toString().toLowerCase().contains(t));
    }).toList();
  }

  Future<void> _elegirRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _rango,
      helpText: 'Fechas de salida',
    );
    if (r != null) {
      setState(() => _rango = r);
      _cargar(reiniciar: true);
    }
  }

  Color _colorEstado(String e) {
    switch (e.toLowerCase()) {
      case 'aprobada':
      case 'confirmada':
        return Colors.green.shade700;
      case 'pendiente':
        return Colors.orange.shade800;
      case 'rechazada':
      case 'cancelada':
        return Colors.red.shade700;
      case 'completada':
        return Colors.blue.shade700;
      default:
        return Colors.grey;
    }
  }

  String _fecha(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final admin = context.watch<AppProvider>().isRoleAdmin;
    final visibles = _visibles;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(admin ? 'Historial de reservas (todas)' : 'Historial de reservas'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                OfflineNotice(
                  texto: 'Sin conexión: se muestran solo tus reservas guardadas en el teléfono.',
                ),
                TextField(
                  controller: _buscar,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _cargar(reiniciar: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: admin
                        ? 'Placa, vehículo, destino, motivo o empleado'
                        : 'Placa, vehículo, destino o motivo',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscar.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _buscar.clear();
                              _cargar(reiniciar: true);
                            },
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final e in const ['todos', 'Pendiente', 'Aprobada', 'Completada', 'Rechazada', 'Cancelada'])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(e == 'todos' ? 'Todas' : e),
                            selected: _estado == e,
                            onSelected: (_) {
                              setState(() => _estado = e);
                              _cargar(reiniciar: true);
                            },
                          ),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.date_range, size: 16),
                        label: Text(_rango == null
                            ? 'Fechas'
                            : '${_rango!.start.day}/${_rango!.start.month} – ${_rango!.end.day}/${_rango!.end.month}'),
                        onPressed: _elegirRango,
                      ),
                      if (_rango != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Quitar fechas',
                          onPressed: () {
                            setState(() => _rango = null);
                            _cargar(reiniciar: true);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null && _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off, size: 56, color: c.textMuted),
                          const SizedBox(height: 10),
                          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
                          const SizedBox(height: 10),
                          OutlinedButton(onPressed: () => _cargar(reiniciar: true), child: const Text('Reintentar')),
                        ],
                      ),
                    ),
                  )
                : visibles.isEmpty && !_cargando
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history, size: 56, color: c.textMuted),
                            const SizedBox(height: 10),
                            Text('No hay reservas con esos filtros.', style: TextStyle(color: c.textSecondary)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _cargar(reiniciar: true),
                        child: ListView.separated(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: visibles.length + (_cargando || _hayMas ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            if (i >= visibles.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            return _fila(visibles[i], admin);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _fila(Map<String, dynamic> r, bool admin) {
    final c = AppColors.of(context);
    final v = r['vehiculos'] is Map ? Map<String, dynamic>.from(r['vehiculos'] as Map) : <String, dynamic>{};
    final nombre = '${v['marca'] ?? ''} ${v['modelo'] ?? ''}'.trim();
    final placa = (v['placa'] ?? '').toString();
    final estado = (r['estado'] ?? 'Pendiente').toString();
    final foto = v['foto'];
    final fotoUrl = foto is String
        ? foto
        : foto is Map
            ? (foto['url'] ?? foto['path'] ?? '').toString()
            : '';
    final destino = () {
      final u = (r['ubicacion'] ?? '').toString();
      if (u.isEmpty) return 'Sin destino';
      final p = u.split('|');
      return p.length > 1 ? p[1] : u;
    }();
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReservationDetailScreen(reservation: r)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedImage(fotoUrl, bucket: 'flotilla', width: 64, height: 64,
                    fallbackIcon: Icons.directions_car),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(nombre.isEmpty ? 'Vehículo' : nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _colorEstado(estado).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(estado.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _colorEstado(estado))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('$placa · $destino',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 12, color: c.textMuted),
                        const SizedBox(width: 4),
                        Text('${_fecha(r['fecha_salida'])} → ${_fecha(r['fecha_regreso'])}',
                            style: TextStyle(fontSize: 11, color: c.textMuted)),
                      ],
                    ),
                    if (admin && _empleadosNombre[r['empleado_id']?.toString()] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 12, color: c.textMuted),
                            const SizedBox(width: 4),
                            Text(_empleadosNombre[r['empleado_id'].toString()]!,
                                style: TextStyle(fontSize: 11, color: c.textSecondary)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
