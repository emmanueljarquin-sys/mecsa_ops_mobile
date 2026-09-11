// =============================================================================
// liquidaciones_historial_screen.dart — Viáticos → Historial de liquidaciones
// -----------------------------------------------------------------------------
// Búsqueda de liquidaciones pasadas, solo lectura. Un usuario normal ve las
// suyas; un administrador (rol admin) ve las de todos con el nombre del
// empleado. Filtros: texto (descripción, personal, proyecto, empleado),
// tipo, estado y rango de fechas. Paginado de 30 en 30. Sin conexión muestra
// las del último mes guardadas en SQLite (solo las propias).
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/liquidacion.dart';
import '../providers/app_provider.dart';
import '../services/connectivity_service.dart';
import '../services/liquidaciones_local.dart';
import '../theme/app_theme.dart';
import '../utils/mensajes_error.dart';
import '../widgets/offline_notice.dart';
import 'liquidacion_detail_screen.dart';

class LiquidacionesHistorialScreen extends StatefulWidget {
  const LiquidacionesHistorialScreen({super.key});

  @override
  State<LiquidacionesHistorialScreen> createState() => _LiquidacionesHistorialScreenState();
}

class _LiquidacionesHistorialScreenState extends State<LiquidacionesHistorialScreen> {
  static const int _pagina = 30;
  final _buscar = TextEditingController();
  final _scroll = ScrollController();
  List<Liquidacion> _items = [];
  bool _cargando = false;
  bool _hayMas = true;
  bool _desdeLocal = false;
  String? _error;
  String _estado = 'todos';
  String _tipo = 'todos';
  DateTimeRange? _rango;
  int _desde = 0;
  final Map<String, String> _empleadosNombre = {};
  final Map<String, String> _proyectosNombre = {};

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
        final locales = await LiquidacionesLocal.instance.listar(empleadoId);
        if (!mounted) return;
        setState(() {
          _items = _filtrarLocal(locales.where((l) => !l.esLocal).toList());
          _hayMas = false;
          _desdeLocal = true;
          _cargando = false;
        });
        return;
      }
      final sb = Supabase.instance.client;
      var q = sb.schema('viaticos').from('liquidaciones').select('*');
      if (!_esAdmin) q = q.eq('empleado_id', empleadoId);
      if (_estado != 'todos') q = q.eq('estado', _estado);
      if (_tipo != 'todos') q = q.eq('tipo', _tipo);
      if (_rango != null) {
        q = q
            .gte('fecha', _rango!.start.toIso8601String().split('T')[0])
            .lte('fecha', _rango!.end.toIso8601String().split('T')[0]);
      }
      final texto = _buscar.text.trim();
      if (texto.isNotEmpty) {
        q = q.or('descripcion.ilike.%$texto%,personal_incluido.ilike.%$texto%,tarjeta_ult4.ilike.%$texto%');
      }
      final res = await q
          .order('fecha', ascending: false)
          .order('created_at', ascending: false)
          .range(_desde, _desde + _pagina - 1)
          .timeout(const Duration(seconds: 25));
      final rows = List<Map<String, dynamic>>.from(res);

      // Nombres de empleados (admin) y proyectos, en lote.
      final empIds = rows.map((r) => r['empleado_id']?.toString()).whereType<String>().toSet()
        ..removeWhere(_empleadosNombre.containsKey);
      if (_esAdmin && empIds.isNotEmpty) {
        try {
          final emps = await sb
              .from('Empleados')
              .select('id, nombre, apellido')
              .inFilter('id', empIds.toList())
              .timeout(const Duration(seconds: 15));
          for (final e in List<Map<String, dynamic>>.from(emps)) {
            _empleadosNombre[e['id'].toString()] = '${e['nombre'] ?? ''} ${e['apellido'] ?? ''}'.trim();
          }
        } catch (_) {}
      }
      final proyIds = rows.map((r) => r['proyecto_id']).where((p) => p != null).toSet()
        ..removeWhere((p) => _proyectosNombre.containsKey(p.toString()));
      if (proyIds.isNotEmpty) {
        try {
          final ps = await sb
              .schema('proyectos')
              .from('projects')
              .select('project_id, title')
              .inFilter('project_id', proyIds.toList())
              .timeout(const Duration(seconds: 15));
          for (final p in List<Map<String, dynamic>>.from(ps)) {
            _proyectosNombre[p['project_id'].toString()] = (p['title'] ?? '').toString();
          }
        } catch (_) {}
      }
      final lista = rows.map((r) {
        final j = Map<String, dynamic>.from(r);
        final pn = _proyectosNombre[j['proyecto_id']?.toString()];
        if (pn != null) j['proyecto'] = {'nombre': pn};
        final en = _empleadosNombre[j['empleado_id']?.toString()];
        if (en != null) {
          final partes = en.split(' ');
          j['empleado'] = {'nombre': partes.first, 'apellido': partes.skip(1).join(' ')};
        }
        return Liquidacion.fromJson(j);
      }).toList();
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...lista];
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

  List<Liquidacion> _filtrarLocal(List<Liquidacion> lista) {
    final t = _buscar.text.trim().toLowerCase();
    return lista.where((l) {
      if (_estado != 'todos' && l.estado != _estado) return false;
      if (_tipo != 'todos' && l.tipo != _tipo) return false;
      if (_rango != null && (l.fecha.isBefore(_rango!.start) || l.fecha.isAfter(_rango!.end.add(const Duration(days: 1))))) {
        return false;
      }
      if (t.isEmpty) return true;
      return [l.descripcion, l.personalIncluido, l.proyectoNombre, l.tarjetaUlt4]
          .any((c) => (c ?? '').toLowerCase().contains(t));
    }).toList();
  }

  List<Liquidacion> get _visibles {
    final t = _buscar.text.trim().toLowerCase();
    if (t.isEmpty || _desdeLocal) return _items;
    return _items.where((l) => [l.descripcion, l.personalIncluido, l.proyectoNombre, l.tarjetaUlt4, l.empleadoCompleto]
        .any((c) => (c ?? '').toLowerCase().contains(t))).toList();
  }

  Future<void> _elegirRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDateRange: _rango,
      helpText: 'Fecha de la liquidación',
    );
    if (r != null) {
      setState(() => _rango = r);
      _cargar(reiniciar: true);
    }
  }

  Color _colorEstado(String e) {
    switch (e) {
      case 'aprobada':
        return Colors.green.shade700;
      case 'rechazada':
        return Colors.red.shade700;
      default:
        return Colors.orange.shade800;
    }
  }

  String _monto(double v) {
    final s = v.toStringAsFixed(0);
    return '₡${s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final admin = context.watch<AppProvider>().isRoleAdmin;
    final visibles = _visibles;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(admin ? 'Historial de liquidaciones (todas)' : 'Historial de liquidaciones'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                const OfflineNotice(
                  texto: 'Sin conexión: se muestran solo tus liquidaciones del último mes guardadas en el teléfono.',
                ),
                TextField(
                  controller: _buscar,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _cargar(reiniciar: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: admin
                        ? 'Descripción, personal, proyecto, tarjeta o empleado'
                        : 'Descripción, personal, proyecto o tarjeta',
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
                      for (final e in const ['todos', 'pendiente', 'aprobada', 'rechazada'])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(e == 'todos' ? 'Todas' : e[0].toUpperCase() + e.substring(1)),
                            selected: _estado == e,
                            onSelected: (_) {
                              setState(() => _estado = e);
                              _cargar(reiniciar: true);
                            },
                          ),
                        ),
                      const SizedBox(width: 6),
                      PopupMenuButton<String>(
                        initialValue: _tipo,
                        onSelected: (v) {
                          setState(() => _tipo = v);
                          _cargar(reiniciar: true);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'todos', child: Text('Todos los tipos')),
                          PopupMenuItem(value: 'VIATICOS', child: Text('Viáticos')),
                          PopupMenuItem(value: 'COMBUSTIBLE', child: Text('Combustible')),
                          PopupMenuItem(value: 'OTROS', child: Text('Otros')),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.category_outlined, size: 16),
                          label: Text(_tipo == 'todos' ? 'Tipo' : _tipo),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                            Text('No hay liquidaciones con esos filtros.', style: TextStyle(color: c.textSecondary)),
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
                                child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
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

  Widget _fila(Liquidacion l, bool admin) {
    final c = AppColors.of(context);
    final color = _colorEstado(l.estado);
    final fecha = '${l.fecha.day.toString().padLeft(2, '0')}/${l.fecha.month.toString().padLeft(2, '0')}/${l.fecha.year}';
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LiquidacionDetailScreen(liquidacionId: l.id, soloLectura: true),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.receipt_long, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.proyectoNombre == null || l.proyectoNombre == 'Sin Proyecto'
                                ? (l.descripcion?.isNotEmpty == true ? l.descripcion! : 'Sin proyecto')
                                : l.proyectoNombre!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(l.estadoLabel.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$fecha · ${l.tipo}${l.personalIncluido?.isNotEmpty == true ? ' · ${l.personalIncluido}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(_monto(l.totalGeneral),
                            style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary)),
                        if (l.facturas != null) ...[
                          const SizedBox(width: 8),
                          Text('${l.facturas!.length} factura(s)', style: TextStyle(fontSize: 11, color: c.textMuted)),
                        ],
                        if (admin && l.empleadoNombre != null) ...[
                          const Spacer(),
                          Icon(Icons.person, size: 12, color: c.textMuted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(l.empleadoCompleto,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: c.textSecondary)),
                          ),
                        ],
                      ],
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
