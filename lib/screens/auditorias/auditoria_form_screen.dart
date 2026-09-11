import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/mensajes_error.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../models/auditoria.dart';
import '../../services/auditoria_service.dart';

class AuditoriaFormScreen extends StatefulWidget {
  const AuditoriaFormScreen({super.key});

  @override
  State<AuditoriaFormScreen> createState() => _AuditoriaFormScreenState();
}

class _AuditoriaFormScreenState extends State<AuditoriaFormScreen> {
  static const _navy = Color(0xFF013483);
  final _picker = ImagePicker();

  int _step = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Catálogo + selección
  List<RubricaItem> _rubrica = [];
  List<Map<String, dynamic>> _vehiculos = [];
  final List<AuditoriaItem> _items = [];

  // Paso 1 — datos generales
  String? _vehiculoId;
  bool _esPesado = false;
  final _kmCtrl = TextEditingController();
  final _tarjetaCtrl = TextEditingController();
  final _encargadoCtrl = TextEditingController();
  DateTime _fechaAuditoria = DateTime.now();
  DateTime? _fechaAceite;
  DateTime? _fechaDekra;
  DateTime? _fechaPesoDim;
  DateTime? _fechaExtintor;

  // Fotos por ítem del checklist (clave = itemSlug)
  final Map<String, List<File>> _itemFotos = {};

  // Paso 3 — cierre
  final _obsCtrl = TextEditingController();
  final _conductorCtrl = TextEditingController();
  final _coordinadorCtrl = TextEditingController();
  final List<File> _fotos = [];               // generales
  final List<_DetalleFotoInput> _detalleFotos = []; // detalle con nota

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kmCtrl.dispose();
    _tarjetaCtrl.dispose();
    _encargadoCtrl.dispose();
    _obsCtrl.dispose();
    _conductorCtrl.dispose();
    _coordinadorCtrl.dispose();
    for (final d in _detalleFotos) {
      d.nota.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await AuditoriaService.getRubrica();
      final v = await AuditoriaService.getVehiculos();
      if (!mounted) return;
      setState(() {
        _rubrica = r;
        _vehiculos = v;
        _rebuildItems();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Reconstruye la lista de ítems según es_pesado (oculta ítems solo-pesados
  /// si el vehículo no es pesado), preservando resultados ya marcados.
  void _rebuildItems() {
    final prev = {for (final it in _items) it.itemSlug: it};
    _items.clear();
    for (final r in _rubrica) {
      if (r.soloPesados && !_esPesado) continue;
      final existing = prev[r.itemSlug];
      _items.add(existing ?? AuditoriaItem.fromRubrica(r));
    }
  }

  // Ítems agrupados por categoría, respetando el orden de la rúbrica
  Map<String, List<AuditoriaItem>> get _porCategoria {
    final map = <String, List<AuditoriaItem>>{};
    for (final it in _items) {
      map.putIfAbsent(it.categoria, () => []).add(it);
    }
    return map;
  }

  // Resultado en vivo (% ítems buenos sobre evaluados; N/A excluido)
  double? get _puntajePreview {
    final evaluados = _items.where((i) => i.resultado != 'na').length;
    if (evaluados == 0) return null;
    final buenos = _items.where((i) => i.resultado == 'buen').length;
    return (buenos / evaluados) * 100;
  }

  Future<void> _pickFecha(DateTime? actual, ValueChanged<DateTime> onPick) async {
    final d = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (d != null) onPick(d);
  }

  Future<void> _addFoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (x != null) setState(() => _fotos.add(File(x.path)));
  }

  Future<void> _addItemFoto(String slug) async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (x != null) {
      setState(() => (_itemFotos[slug] ??= []).add(File(x.path)));
    }
  }

  Future<void> _addDetalleFoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (x != null) {
      setState(() => _detalleFotos.add(_DetalleFotoInput(File(x.path))));
    }
  }

  bool _validarPaso1() {
    if (_vehiculoId == null) {
      _snack('Seleccioná un vehículo');
      return false;
    }
    return true;
  }

  void _next() {
    if (_step == 0 && !_validarPaso1()) return;
    setState(() => _step++);
  }

  void _back() => setState(() => _step--);

  Future<void> _guardar() async {
    setState(() => _saving = true);
    try {
      final p = Provider.of<AppProvider>(context, listen: false);

      // 1) Fotos generales
      List<String> urls = [];
      if (_fotos.isNotEmpty) {
        urls = await AuditoriaService.subirFotos(_fotos);
      }

      // 2) Fotos por ítem → set item.fotos con las URLs
      for (final it in _items) {
        final files = _itemFotos[it.itemSlug];
        if (files != null && files.isNotEmpty) {
          it.fotos = await AuditoriaService.subirFotos(files);
        }
      }

      // 3) Fotos de detalle con nota
      final List<FotoDetalle> detalle = [];
      if (_detalleFotos.isNotEmpty) {
        final detUrls =
            await AuditoriaService.subirFotos(_detalleFotos.map((d) => d.file).toList());
        for (var i = 0; i < detUrls.length; i++) {
          final nota = _detalleFotos[i].nota.text.trim();
          detalle.add(FotoDetalle(url: detUrls[i], nota: nota.isEmpty ? null : nota));
        }
      }

      final cab = Auditoria(
        vehiculoId: _vehiculoId,
        auditorId: p.currentEmployeeId,
        fechaAuditoria: _fechaAuditoria,
        kilometraje: int.tryParse(_kmCtrl.text.trim()),
        fechaUltimoCambioAceite: _fechaAceite,
        fechaDekra: _fechaDekra,
        fechaVencPesoDim: _fechaPesoDim,
        fechaVencExtintor: _fechaExtintor,
        numTarjetaCirculacion: _tarjetaCtrl.text.trim().isEmpty ? null : _tarjetaCtrl.text.trim(),
        encargadoCamion: _encargadoCtrl.text.trim().isEmpty ? null : _encargadoCtrl.text.trim(),
        tipoVehiculo: _vehSel?['type']?.toString(),
        esPesado: _esPesado,
        estado: 'Completada',
        observacionesGenerales: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
        firmaConductor: _conductorCtrl.text.trim().isEmpty ? null : _conductorCtrl.text.trim(),
        firmaCoordinador: _coordinadorCtrl.text.trim().isEmpty ? null : _coordinadorCtrl.text.trim(),
        fotos: urls,
        fotosDetalle: detalle,
      );

      await AuditoriaService.crearAuditoria(cabecera: cab, items: _items);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auditoría guardada'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(mensajeError(e, accion: 'guardar la auditoría'), error: true);
      }
    }
  }

  Map<String, dynamic>? get _vehSel {
    if (_vehiculoId == null) return null;
    for (final v in _vehiculos) {
      if (v['id'].toString() == _vehiculoId) return v;
    }
    return null;
  }

  void _snack(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: error ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: const Text('Nueva auditoría'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(mensajeError(_error, accion: 'cargar la auditoría')))
              : Column(
                  children: [
                    _stepIndicator(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _step == 0
                            ? _paso1()
                            : _step == 1
                                ? _paso2()
                                : _paso3(),
                      ),
                    ),
                    _bottomBar(),
                  ],
                ),
    );
  }

  // ── Indicador de pasos ──────────────────────────────────────────────────
  Widget _stepIndicator() {
    const labels = ['Datos', 'Inspección', 'Cierre'];
    return Container(
      color: AppColors.of(context).surface,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: List.generate(3, (i) {
          final active = i == _step;
          final done = i < _step;
          return Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: active || done ? _navy : AppColors.of(context).surfaceVariant,
                  child: done
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : Text('${i + 1}',
                          style: TextStyle(
                              color: active ? Colors.white : AppColors.of(context).textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Text(labels[i],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        color: active ? _navy : AppColors.of(context).textSecondary)),
                if (i < 2)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: done ? _navy : AppColors.of(context).surfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── PASO 1: datos generales ─────────────────────────────────────────────
  Widget _paso1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Vehículo'),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.of(context).surfaceVariant)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              initialValue: _vehiculoId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Seleccioná el vehículo *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.directions_car),
              ),
              items: _vehiculos.map((v) {
                return DropdownMenuItem(
                  value: v['id'].toString(),
                  child: Text(
                    '${v['marca'] ?? ''} ${v['modelo'] ?? ''} · ${v['placa'] ?? ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _vehiculoId = val;
                  final v = _vehSel;
                  if (v != null && v['km_actual'] != null && _kmCtrl.text.isEmpty) {
                    _kmCtrl.text = v['km_actual'].toString();
                  }
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _esPesado,
          activeThumbColor: _navy,
          contentPadding: EdgeInsets.zero,
          title: const Text('¿Es vehículo pesado?'),
          subtitle: const Text('Habilita ítems extra (pito de reversa, caja cerrada)'),
          onChanged: (v) => setState(() { _esPesado = v; _rebuildItems(); }),
        ),
        const Divider(height: 28),
        _sectionTitle('Datos generales'),
        _textField(_kmCtrl, 'Kilometraje actual', Icons.speed, number: true),
        _textField(_tarjetaCtrl, 'N° tarjeta de circulación', Icons.badge),
        _textField(_encargadoCtrl, 'Encargado del vehículo', Icons.person),
        const SizedBox(height: 8),
        _sectionTitle('Fechas'),
        _dateTile('Fecha de auditoría', _fechaAuditoria, (d) => setState(() => _fechaAuditoria = d)),
        _dateTile('Último cambio de aceite', _fechaAceite, (d) => setState(() => _fechaAceite = d)),
        _dateTile('Vencimiento Dekra (RTV)', _fechaDekra, (d) => setState(() => _fechaDekra = d)),
        _dateTile('Vencimiento peso y dimensiones', _fechaPesoDim, (d) => setState(() => _fechaPesoDim = d)),
        _dateTile('Vencimiento del extintor', _fechaExtintor, (d) => setState(() => _fechaExtintor = d)),
      ],
    );
  }

  // ── PASO 2: checklist por categoría ─────────────────────────────────────
  Widget _paso2() {
    final grupos = _porCategoria;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _resultadoBanner(),
        const SizedBox(height: 12),
        ...grupos.entries.map((e) => _categoriaCard(e.key, e.value)),
      ],
    );
  }

  Widget _categoriaCard(String categoria, List<AuditoriaItem> items) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.of(context).surfaceVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Text(categoria.toUpperCase(),
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: _navy, fontSize: 13, letterSpacing: .5)),
          ),
          ...items.map(_itemRow),
        ],
      ),
    );
  }

  Widget _itemRow(AuditoriaItem it) {
    final rub = _rubrica.firstWhere((r) => r.itemSlug == it.itemSlug,
        orElse: () => RubricaItem(id: '', categoria: '', itemSlug: '', itemLabel: it.itemLabel));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(it.itemLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          if (rub.ayuda != null && rub.ayuda!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(rub.ayuda!, style: TextStyle(fontSize: 12, color: AppColors.of(context).textMuted)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _estadoBtn(it, 'buen', 'Buen', Colors.green),
              const SizedBox(width: 6),
              _estadoBtn(it, 'mal', 'Mal', Colors.red),
              const SizedBox(width: 6),
              _estadoBtn(it, 'na', 'N/A', Colors.grey),
            ],
          ),
          if (it.resultado == 'mal')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Observación (opcional)',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (v) => it.observacion = v,
              ),
            ),
          _itemFotoStrip(it.itemSlug),
          const Divider(height: 18),
        ],
      ),
    );
  }

  // Tarjeta de foto de detalle: miniatura + nota + eliminar
  Widget _detalleFotoCard(int index, _DetalleFotoInput d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.of(context).surfaceVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(d.file, width: 70, height: 70, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: d.nota,
              decoration: InputDecoration(
                hintText: 'Nota (ej: golpe puerta trasera)',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
            onPressed: () => setState(() {
              d.nota.dispose();
              _detalleFotos.removeAt(index);
            }),
          ),
        ],
      ),
    );
  }

  // Miniaturas de fotos del ítem + botón para agregar
  Widget _itemFotoStrip(String slug) {
    final fotos = _itemFotos[slug] ?? [];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          ...fotos.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(e.value, width: 54, height: 54, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: GestureDetector(
                        onTap: () => setState(() => fotos.removeAt(e.key)),
                        child: Container(
                          decoration: BoxDecoration(color: AppColors.of(context).textSecondary, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          OutlinedButton.icon(
            onPressed: () => _addItemFoto(slug),
            icon: const Icon(Icons.add_a_photo, size: 16, color: _navy),
            label: Text(fotos.isEmpty ? 'Foto del detalle' : 'Otra',
                style: const TextStyle(color: _navy, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: BorderSide(color: AppColors.of(context).surfaceVariant),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoBtn(AuditoriaItem it, String value, String label, MaterialColor color) {
    final sel = it.resultado == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => it.resultado = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: sel ? color.shade600 : color.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? color.shade700 : color.shade100),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: sel ? Colors.white : color.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ),
      ),
    );
  }

  Widget _resultadoBanner() {
    final p = _puntajePreview;
    final color = p == null
        ? Colors.grey
        : p >= 90
            ? Colors.green
            : p >= 70
                ? Colors.orange
                : Colors.red;
    final malos = _items.where((i) => i.resultado == 'mal').length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics, color: color.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p == null
                  ? 'Marcá los ítems para ver el resultado'
                  : 'Resultado en vivo: ${p.toStringAsFixed(0)}%  ·  $malos en mal estado',
              style: TextStyle(fontWeight: FontWeight.bold, color: color.shade900),
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 3: cierre (fotos, firmas, observaciones) ───────────────────────
  Widget _paso3() {
    final p = _puntajePreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Fotos generales (opcional)'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ..._fotos.asMap().entries.map((e) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(e.value, width: 90, height: 90, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _fotos.removeAt(e.key)),
                        child: Container(
                          decoration: BoxDecoration(color: AppColors.of(context).textSecondary, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                )),
            GestureDetector(
              onTap: _addFoto,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.of(context).surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.of(context).surfaceVariant),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo, color: _navy),
                    SizedBox(height: 4),
                    Text('Foto', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 28),
        _sectionTitle('Fotos de detalle (con nota)'),
        Text('Para daños o detalles específicos no listados (golpes, rayas, etc.)',
            style: TextStyle(fontSize: 12, color: AppColors.of(context).textMuted)),
        const SizedBox(height: 10),
        ..._detalleFotos.asMap().entries.map((e) => _detalleFotoCard(e.key, e.value)),
        OutlinedButton.icon(
          onPressed: _addDetalleFoto,
          icon: const Icon(Icons.add_a_photo, size: 18, color: _navy),
          label: const Text('Agregar foto de detalle', style: TextStyle(color: _navy)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            side: const BorderSide(color: _navy),
          ),
        ),
        const Divider(height: 28),
        _sectionTitle('Observaciones generales'),
        TextField(
          controller: _obsCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Condiciones inseguras, defectos adicionales…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('Firmas'),
        _textField(_conductorCtrl, 'Nombre del conductor', Icons.person_outline),
        _textField(_coordinadorCtrl, 'Nombre del coordinador', Icons.person_pin),
        const Divider(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              const Text('RESULTADO FINAL',
                  style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(p == null ? '—' : '${p.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
              Text(
                '${_items.where((i) => i.resultado == 'buen').length} buenos · '
                '${_items.where((i) => i.resultado == 'mal').length} malos · '
                '${_items.where((i) => i.resultado == 'na').length} N/A',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Barra inferior de navegación ────────────────────────────────────────
  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        boxShadow: [BoxShadow(color: AppColors.of(context).shadow, blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : _back,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: _navy),
                ),
                child: const Text('Anterior', style: TextStyle(color: _navy)),
              ),
            ),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _saving ? null : (_step < 2 ? _next : _guardar),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_step < 2 ? 'Siguiente' : 'Guardar auditoría',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers de UI ───────────────────────────────────────────────────────
  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(children: [
          Container(width: 4, height: 18, color: _navy),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _navy)),
        ]),
      );

  Widget _textField(TextEditingController c, String label, IconData icon, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: _navy),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateTile(String label, DateTime? value, ValueChanged<DateTime> onPick) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppColors.of(context).surfaceVariant)),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.event, color: _navy),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: Text(
          value == null ? 'Elegir' : DateFormat('dd/MM/yyyy').format(value),
          style: TextStyle(
              color: value == null ? Colors.grey : _navy, fontWeight: FontWeight.w600),
        ),
        onTap: () => _pickFecha(value, onPick),
      ),
    );
  }
}

/// Entrada de foto de detalle en el formulario: archivo local + controlador de nota.
class _DetalleFotoInput {
  final File file;
  final TextEditingController nota = TextEditingController();
  _DetalleFotoInput(this.file);
}
