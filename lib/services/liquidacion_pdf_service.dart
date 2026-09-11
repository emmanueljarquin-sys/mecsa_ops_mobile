// =============================================================================
// liquidacion_pdf_service.dart — PDF de una liquidación con sus comprobantes
// -----------------------------------------------------------------------------
// Arma un PDF con: datos generales, tabla de facturas, totales por tipo y,
// a continuación, una página por comprobante (imagen). Los comprobantes se
// obtienen con ComprobantesService (caché local), así que también funciona
// sin conexión para los que ya se hayan visto o estén pendientes de subir.
// Los comprobantes en PDF no se incrustan; se listan como "adjunto PDF".
// =============================================================================
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/liquidacion.dart';
import 'comprobantes_service.dart';

class LiquidacionPdfService {
  LiquidacionPdfService._();

  static const PdfColor _navy = PdfColor.fromInt(0xFF013483);
  static const PdfColor _amber = PdfColor.fromInt(0xFFF29C2E);
  static const PdfColor _greyBg = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor _greyLine = PdfColor.fromInt(0xFFCBD5E1);

  static String _pad2(int n) => n.toString().padLeft(2, '0');
  static String _fecha(DateTime d) => '${_pad2(d.day)}/${_pad2(d.month)}/${d.year}';
  // "CRC" en vez de "₡": la fuente base del PDF no trae ese glifo.
  static String _monto(double v) {
    final s = v.toStringAsFixed(2);
    final partes = s.split('.');
    final entero = partes[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return 'CRC $entero.${partes[1]}';
  }

  /// Nombre de archivo sugerido.
  static String nombreArchivo(Liquidacion l) {
    final id = l.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').substring(0, l.id.length.clamp(0, 8));
    return 'liquidacion_${_fecha(l.fecha).replaceAll('/', '-')}_$id.pdf';
  }

  static Future<Uint8List> construir(Liquidacion l, {String? empresa}) async {
    final doc = pw.Document();
    final facturas = l.facturas ?? <Factura>[];
    final generado = DateTime.now();
    final generadoStr = '${_fecha(generado)} ${_pad2(generado.hour)}:${_pad2(generado.minute)}';

    // Totales por tipo (usar los del servidor si vienen; si no, calcular).
    final Map<String, double> totales = {};
    for (final f in facturas) {
      totales[f.tipoLabel] = (totales[f.tipoLabel] ?? 0) + f.monto;
    }
    final double total = l.totalGeneral > 0
        ? l.totalGeneral
        : totales.values.fold(0.0, (a, b) => a + b);

    // Comprobantes (imágenes) desde caché/descarga.
    final comprobantes = <MapEntry<Factura, pw.MemoryImage?>>[];
    for (final f in facturas) {
      final path = (f.documento != null && f.documento!.isNotEmpty)
          ? f.documento!
          : (f.localDocPath ?? '');
      if (path.isEmpty) continue;
      if (ComprobantesService.instance.esPdf(path)) {
        comprobantes.add(MapEntry(f, null));
        continue;
      }
      final bytes = await ComprobantesService.instance.bytes(path);
      pw.MemoryImage? img;
      if (bytes != null) {
        try {
          img = pw.MemoryImage(bytes);
        } catch (_) {}
      }
      comprobantes.add(MapEntry(f, img));
    }

    pw.Widget celda(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(t,
              textAlign: align,
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null)),
        );

    pw.Widget dato(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(
                width: 110,
                child: pw.Text(k,
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
            pw.Expanded(
                child: pw.Text(v,
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
          // Encabezado
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
                  pw.Text('LIQUIDACIÓN DE VIÁTICOS',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(empresa ?? 'Grupo Mecsa',
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                ]),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: _amber,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(l.estadoLabel.toUpperCase(),
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Datos generales
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _greyBg,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              dato('Empleado', l.empleadoCompleto),
              dato('Fecha', _fecha(l.fecha)),
              dato('Tipo', l.tipo),
              dato('Proyecto', l.proyectoNombre ?? 'Sin proyecto'),
              if (l.tarjetaUlt4 != null && l.tarjetaUlt4!.isNotEmpty)
                dato('Tarjeta', '**** ${l.tarjetaUlt4}'),
              if (l.personalIncluido != null && l.personalIncluido!.isNotEmpty)
                dato('Personal incluido', l.personalIncluido!),
              if (l.descripcion != null && l.descripcion!.isNotEmpty)
                dato('Descripción', l.descripcion!),
              dato('Referencia', l.id),
            ]),
          ),
          pw.SizedBox(height: 14),

          // Facturas
          pw.Text('FACTURAS (${facturas.length})',
              style: pw.TextStyle(
                  color: _navy, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: _greyLine, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.3),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.1),
              4: pw.FlexColumnWidth(1.4),
              5: pw.FlexColumnWidth(1.0),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _greyBg),
                children: [
                  celda('Tipo', bold: true),
                  celda('Proveedor', bold: true),
                  celda('N° factura', bold: true),
                  celda('Fecha', bold: true),
                  celda('Monto', bold: true, align: pw.TextAlign.right),
                  celda('Comprob.', bold: true, align: pw.TextAlign.center),
                ],
              ),
              for (int i = 0; i < facturas.length; i++)
                pw.TableRow(children: [
                  celda(facturas[i].tipoLabel),
                  celda(facturas[i].proveedor),
                  celda(facturas[i].numeroFactura),
                  celda(_fecha(facturas[i].fecha)),
                  celda(_monto(facturas[i].monto), align: pw.TextAlign.right),
                  celda(
                      (facturas[i].documento ?? facturas[i].localDocPath ?? '').isEmpty
                          ? '-'
                          : 'Anexo ${i + 1}',
                      align: pw.TextAlign.center),
                ]),
            ],
          ),
          pw.SizedBox(height: 12),

          // Totales
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 240,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _greyLine),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(children: [
                for (final e in totales.entries)
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text(e.key, style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(_monto(e.value), style: const pw.TextStyle(fontSize: 9)),
                  ]),
                pw.Divider(color: _greyLine),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('TOTAL',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_monto(total),
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy)),
                ]),
              ]),
            ),
          ),

          if (l.solicitudCorreccion != null && l.solicitudCorreccion!.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Solicitud de corrección: ${l.solicitudCorreccion}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            if (l.respuestaAdmin != null && l.respuestaAdmin!.isNotEmpty)
              pw.Text('Respuesta: ${l.respuestaAdmin}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ],
      ),
    );

    // Un comprobante por página.
    for (int i = 0; i < comprobantes.length; i++) {
      final f = comprobantes[i].key;
      final img = comprobantes[i].value;
      final idx = facturas.indexOf(f) + 1;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Anexo $idx · ${f.tipoLabel} · ${f.proveedor} · #${f.numeroFactura} · ${_monto(f.monto)}',
                  style: pw.TextStyle(
                      color: _navy, fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Container(
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: _greyLine)),
                  child: img != null
                      ? pw.Image(img, fit: pw.BoxFit.contain)
                      : pw.Text(
                          ComprobantesService.instance.esPdf(f.documento ?? '')
                              ? 'El comprobante es un archivo PDF adjunto (no se incrusta).'
                              : 'Comprobante no disponible sin conexión.',
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
