import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/auditoria.dart';
import '../../services/auditoria_service.dart';

class AuditoriaDetailScreen extends StatefulWidget {
  final Auditoria auditoria;
  const AuditoriaDetailScreen({super.key, required this.auditoria});

  @override
  State<AuditoriaDetailScreen> createState() => _AuditoriaDetailScreenState();
}

class _AuditoriaDetailScreenState extends State<AuditoriaDetailScreen> {
  static const _navy = Color(0xFF013483);
  bool _loading = true;
  List<AuditoriaItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await AuditoriaService.getItems(widget.auditoria.id!);
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, List<AuditoriaItem>> get _porCategoria {
    final map = <String, List<AuditoriaItem>>{};
    for (final it in _items) {
      map.putIfAbsent(it.categoria, () => []).add(it);
    }
    return map;
  }

  Color _colorPuntaje(double? p) {
    if (p == null) return Colors.grey;
    if (p >= 90) return Colors.green.shade600;
    if (p >= 70) return Colors.orange.shade700;
    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.auditoria;
    final veh = AuditoriaService.vehiculoInfo(a.vehiculoId);
    final vehTxt = veh == null
        ? 'Vehículo'
        : '${veh['marca'] ?? ''} ${veh['modelo'] ?? ''} · ${veh['placa'] ?? ''}';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Detalle de auditoría'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _resumen(a, vehTxt.trim()),
                const SizedBox(height: 16),
                _datosGenerales(a),
                const SizedBox(height: 16),
                ..._porCategoria.entries.map((e) => _categoria(e.key, e.value)),
                if (a.observacionesGenerales != null && a.observacionesGenerales!.isNotEmpty)
                  _bloque('Observaciones generales', a.observacionesGenerales!),
                if (a.fotos.isNotEmpty) _fotos(a.fotos),
                if (a.fotosDetalle.isNotEmpty) _fotosDetalle(a.fotosDetalle),
                _firmas(a),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _resumen(Auditoria a, String vehTxt) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white,
            child: Text(
              a.puntaje == null ? '—' : '${a.puntaje!.round()}%',
              style: TextStyle(
                  color: _colorPuntaje(a.puntaje), fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehTxt,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(DateFormat('dd/MM/yyyy').format(a.fechaAuditoria),
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Text('${a.itemsBuenos} buenos · ${a.itemsMalos} malos · ${a.itemsNa} N/A',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _datosGenerales(Auditoria a) {
    final df = DateFormat('dd/MM/yyyy');
    final rows = <List<String>>[
      if (a.kilometraje != null) ['Kilometraje', '${a.kilometraje} km'],
      if (a.numTarjetaCirculacion != null) ['N° tarjeta', a.numTarjetaCirculacion!],
      if (a.encargadoCamion != null) ['Encargado', a.encargadoCamion!],
      if (a.fechaUltimoCambioAceite != null) ['Últ. cambio aceite', df.format(a.fechaUltimoCambioAceite!)],
      if (a.fechaDekra != null) ['Venc. Dekra', df.format(a.fechaDekra!)],
      if (a.fechaVencPesoDim != null) ['Venc. peso/dim', df.format(a.fechaVencPesoDim!)],
      if (a.fechaVencExtintor != null) ['Venc. extintor', df.format(a.fechaVencExtintor!)],
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return _cardWrap(
      'Datos generales',
      Column(
        children: rows
            .map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(r[0], style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      Text(r[1], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _categoria(String cat, List<AuditoriaItem> items) {
    return _cardWrap(
      cat,
      Column(
        children: items.map((it) {
          final c = it.resultado == 'buen'
              ? Colors.green
              : it.resultado == 'mal'
                  ? Colors.red
                  : Colors.grey;
          final label = it.resultado == 'buen'
              ? 'Buen'
              : it.resultado == 'mal'
                  ? 'Mal'
                  : 'N/A';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.itemLabel, style: const TextStyle(fontSize: 14)),
                      if (it.observacion != null && it.observacion!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(it.observacion!,
                              style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
                        ),
                      if (it.fotos.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: it.fotos.map((u) => _thumb(u, 56)).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(label,
                      style: TextStyle(color: c.shade700, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _thumb(String url, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
              width: size, height: size, color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey))),
    );
  }

  Widget _fotos(List<String> urls) {
    return _cardWrap(
      'Fotos generales',
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: urls.map((u) => _thumb(u, 90)).toList(),
      ),
    );
  }

  Widget _fotosDetalle(List<FotoDetalle> fotos) {
    return _cardWrap(
      'Fotos de detalle',
      Column(
        children: fotos
            .map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _thumb(f.url, 64),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          (f.nota == null || f.nota!.isEmpty) ? 'Sin nota' : f.nota!,
                          style: TextStyle(
                              fontSize: 13,
                              color: (f.nota == null || f.nota!.isEmpty)
                                  ? Colors.grey.shade400
                                  : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _firmas(Auditoria a) {
    if ((a.firmaConductor == null || a.firmaConductor!.isEmpty) &&
        (a.firmaCoordinador == null || a.firmaCoordinador!.isEmpty)) {
      return const SizedBox.shrink();
    }
    return _cardWrap(
      'Firmas',
      Column(
        children: [
          if (a.firmaConductor != null && a.firmaConductor!.isNotEmpty)
            _kv('Conductor', a.firmaConductor!),
          if (a.firmaCoordinador != null && a.firmaCoordinador!.isNotEmpty)
            _kv('Coordinador', a.firmaCoordinador!),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );

  Widget _bloque(String titulo, String texto) => _cardWrap(titulo, Text(texto, style: const TextStyle(fontSize: 14)));

  Widget _cardWrap(String titulo, Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 13, letterSpacing: .5)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
