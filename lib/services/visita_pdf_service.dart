// =============================================================================
// visita_pdf_service.dart — PDF de una visita con sus fotos
// -----------------------------------------------------------------------------
// Arma un PDF con los datos de la visita (cliente, fecha, proyecto, destinos,
// notas, kilometraje, duración, pago) y una página por foto (fotos adjuntas y
// odómetros). Las fotos pueden ser URLs (ya subidas) o rutas locales
// (visita creada sin conexión), así que también sirve sin red.
// =============================================================================
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'ruta_pdf_service.dart';

class VisitaPdfService {
  VisitaPdfService._();

  static const PdfColor _navy = PdfColor.fromInt(0xFF013483);
  static const PdfColor _amber = PdfColor.fromInt(0xFFF29C2E);
  static const PdfColor _greyBg = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor _greyLine = PdfColor.fromInt(0xFFCBD5E1);

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Todas las fotos de la visita, en orden y con etiqueta.
  static List<MapEntry<String, String>> fotosDe(Map<String, dynamic> v) {
    final out = <MapEntry<String, String>>[];
    String s(Object? o) => (o ?? '').toString().trim();
    final fotos = v['fotos'];
    if (fotos is List) {
      int i = 1;
      for (final f in fotos) {
        final p = f is Map ? s(f['url'] ?? f['path']) : s(f);
        if (p.isNotEmpty) out.add(MapEntry('Foto ${i++}', p));
      }
    }
    if (s(v['foto_odometro_inicio']).isNotEmpty) {
      out.add(MapEntry('Odómetro inicial', s(v['foto_odometro_inicio'])));
    }
    if (s(v['foto_odometro_fin']).isNotEmpty) {
      out.add(MapEntry('Odómetro final', s(v['foto_odometro_fin'])));
    }
    if (s(v['comprobante_pago']).isNotEmpty &&
        !s(v['comprobante_pago']).toLowerCase().endsWith('.pdf')) {
      out.add(MapEntry('Comprobante de pago', s(v['comprobante_pago'])));
    }
    return out;
  }

  /// Bytes de una foto: URL (descarga) o ruta local (archivo).
  static Future<Uint8List?> bytesDe(String path) async {
    if (path.startsWith('http')) return RutaPdfService.descargarBytes(path);
    try {
      final f = File(path);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }

  static String nombreArchivo(Map<String, dynamic> v) {
    final fecha = (v['fecha'] ?? '').toString().replaceAll(RegExp(r'[^0-9-]'), '');
    final id = (v['id'] ?? '').toString().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final corto = id.length > 8 ? id.substring(0, 8) : id;
    return 'visita_${fecha}_$corto.pdf';
  }

  static Future<Uint8List> construir(Map<String, dynamic> v) async {
    final doc = pw.Document();
    String s(Object? o) => (o ?? '').toString().trim();
    final generado = DateTime.now();
    final generadoStr =
        '${_pad2(generado.day)}/${_pad2(generado.month)}/${generado.year} '
        '${_pad2(generado.hour)}:${_pad2(generado.minute)}';

    final fotos = fotosDe(v);
    final imagenes = <MapEntry<String, pw.MemoryImage?>>[];
    for (final f in fotos) {
      final b = await bytesDe(f.value);
      pw.MemoryImage? img;
      if (b != null) {
        try {
          img = pw.MemoryImage(b);
        } catch (_) {}
      }
      imagenes.add(MapEntry(f.key, img));
    }

    final destinos = (v['destinos'] is List)
        ? (v['destinos'] as List)
            .map((d) => d is Map ? s(d['direccion'] ?? d['address'] ?? d['nombre']) : s(d))
            .where((x) => x.isNotEmpty)
            .toList()
        : <String>[];
    final waypoints = (v['waypoints'] is List) ? (v['waypoints'] as List).length : 0;
    final estado = s(v['estado']).isEmpty ? 'programada' : s(v['estado']);
    final kmIni = s(v['odometro_inicial']).isEmpty ? s(v['km_inicial']) : s(v['odometro_inicial']);
    final kmFin = s(v['odometro_final']).isEmpty ? s(v['km_final']) : s(v['odometro_final']);
    final kmRec = s(v['km_recorridos']);
    final dur = s(v['duracion_minutos']).isEmpty ? s(v['duracion']) : s(v['duracion_minutos']);
    final proyecto = v['proyecto'] is Map ? s((v['proyecto'] as Map)['nombre']) : s(v['proyecto_id']);

    pw.Widget dato(String k, String val) => val.isEmpty
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(
                  width: 110,
                  child: pw.Text(k,
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
              pw.Expanded(
                  child: pw.Text(val,
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            ]),
          );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Grupo Mecsa · MecsaOPS · Generado el $generadoStr · Página ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(color: PdfColors.grey, fontSize: 8),
          ),
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('REPORTE DE VISITA',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(s(v['cliente']).isEmpty ? 'Grupo Mecsa' : s(v['cliente']),
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                ]),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: _amber,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(estado.toUpperCase().replaceAll('_', ' '),
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _greyBg,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              dato('Fecha', s(v['fecha'])),
              dato('Hora inicio', s(v['hora_inicio'])),
              dato('Hora fin', s(v['hora_fin'])),
              dato('Cliente', s(v['cliente'])),
              dato('Tipo', s(v['tipo_visita']).toUpperCase()),
              dato('Proyecto', proyecto),
              dato('Dirección', s(v['direccion'])),
              if (destinos.isNotEmpty) dato('Destinos', destinos.join('\n')),
              dato('Referencia', s(v['id'])),
            ]),
          ),
          pw.SizedBox(height: 12),
          if (s(v['notas']).isNotEmpty || s(v['observaciones']).isNotEmpty) ...[
            pw.Text('NOTAS',
                style: pw.TextStyle(color: _navy, fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _greyLine)),
              child: pw.Text(
                  s(v['notas']).isNotEmpty ? s(v['notas']) : s(v['observaciones']),
                  style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.SizedBox(height: 12),
          ],
          pw.Text('RECORRIDO',
              style: pw.TextStyle(color: _navy, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _greyLine)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              dato('Odómetro inicial', kmIni.isEmpty ? '' : '$kmIni km'),
              dato('Odómetro final', kmFin.isEmpty ? '' : '$kmFin km'),
              dato('Km recorridos', kmRec.isEmpty ? '' : '$kmRec km'),
              dato('Duración', dur.isEmpty ? '' : '$dur min'),
              dato('Puntos GPS', waypoints == 0 ? '' : '$waypoints registros'),
              dato('Pago kilometraje',
                  v['pago_kilometraje'] == true
                      ? 'Pagado${s(v['fecha_pago']).isEmpty ? '' : ' el ${s(v['fecha_pago'])}'}'
                      : (s(v['monto_pago_km']).isEmpty ? '' : 'Pendiente · CRC ${s(v['monto_pago_km'])}')),
            ]),
          ),
          pw.SizedBox(height: 12),
          pw.Text('FOTOS (${fotos.length})',
              style: pw.TextStyle(color: _navy, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
              fotos.isEmpty
                  ? 'Sin fotos adjuntas.'
                  : 'Las fotos se anexan en las páginas siguientes.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );

    for (final e in imagenes) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('${e.key} · ${s(v['cliente'])} · ${s(v['fecha'])}',
                  style: pw.TextStyle(color: _navy, fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Container(
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: _greyLine)),
                  child: e.value != null
                      ? pw.Image(e.value!, fit: pw.BoxFit.contain)
                      : pw.Text('Foto no disponible (sin conexión o archivo no encontrado).',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }
}
