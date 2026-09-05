import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Genera el PDF de un registro de ruta (salida + entrada) con los datos de la
/// visita y las fotos, y también permite bajar las fotos originales al carrete.
///
/// No depende de Flutter (solo de `pdf` + `http`), así se puede testear/usar
/// desde cualquier pantalla.
class RutaPdfService {
  RutaPdfService._();

  // Colores de marca OPS.
  static const PdfColor _navy = PdfColor.fromInt(0xFF013483);
  static const PdfColor _amber = PdfColor.fromInt(0xFFF29C2E);
  static const PdfColor _greyBg = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor _greyLine = PdfColor.fromInt(0xFFCBD5E1);

  /// Orden y etiqueta legible de cada foto guardada en `registros_vehiculos`.
  static const List<MapEntry<String, String>> fotoCampos = [
    MapEntry('foto_frente', 'Frente'),
    MapEntry('foto_lateral_der', 'Lateral derecho'),
    MapEntry('foto_lateral_izq', 'Lateral izquierdo'),
    MapEntry('foto_trasera', 'Trasera'),
    MapEntry('foto_kilometraje', 'Kilometraje'),
  ];

  /// Junta todas las URLs de fotos (salida + entrada), en orden, sin nulos.
  static List<String> urlsDeFotos(
    Map<String, dynamic> regSalida,
    Map<String, dynamic> regEntrada,
  ) {
    final out = <String>[];
    for (final reg in [regSalida, regEntrada]) {
      for (final campo in fotoCampos) {
        final v = reg[campo.key];
        if (v is String && v.trim().isNotEmpty) out.add(v.trim());
      }
    }
    return out;
  }

  /// Descarga pública de bytes (para guardar fotos al carrete).
  static Future<Uint8List?> descargarBytes(String? url) => _download(url);

  static Future<Uint8List?> _download(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    try {
      final r = await http
          .get(Uri.parse(url.trim()))
          .timeout(const Duration(seconds: 25));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// Descarga las fotos de un registro que existan, como imágenes del PDF.
  static Future<List<_Foto>> _fotosDe(Map<String, dynamic> reg) async {
    final fotos = <_Foto>[];
    for (final campo in fotoCampos) {
      final bytes = await _download(reg[campo.key]?.toString());
      if (bytes != null) {
        try {
          fotos.add(_Foto(campo.value, pw.MemoryImage(bytes)));
        } catch (_) {}
      }
    }
    return fotos;
  }

  /// Arma el PDF completo. Devuelve los bytes listos para compartir/guardar.
  static Future<Uint8List> construirPdf({
    required String vehiculo,
    required String placa,
    required String destino,
    String? conductor,
    required String fechaSalida,
    required String fechaRegreso,
    required String motivo,
    required String reservaId,
    required double kmSalida,
    required double kmEntrada,
    required double kmTotal,
    required String duracion,
    required String horaSalida,
    required String horaEntrada,
    required Map<String, dynamic> regSalida,
    required Map<String, dynamic> regEntrada,
  }) async {
    final doc = pw.Document();
    final fotosSalida = await _fotosDe(regSalida);
    final fotosEntrada = await _fotosDe(regEntrada);
    final generado = DateTime.now();
    final generadoStr =
        '${_pad2(generado.day)}/${_pad2(generado.month)}/${generado.year} '
        '${_pad2(generado.hour)}:${_pad2(generado.minute)}';

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        ),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text('Registro de ruta · $placa',
                    style: pw.TextStyle(color: _navy, fontSize: 9)),
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
          _titulo(vehiculo, placa),
          pw.SizedBox(height: 14),
          _seccion('DATOS DE LA VISITA'),
          pw.SizedBox(height: 6),
          _tablaDatos({
            'Vehículo': vehiculo,
            'Placa': placa,
            if (conductor != null && conductor.trim().isNotEmpty)
              'Conductor': conductor,
            'Destino': destino,
            'Salida': fechaSalida,
            'Regreso': fechaRegreso,
            'N° de reserva': reservaId,
            'Motivo': motivo,
          }),
          pw.SizedBox(height: 16),
          _seccion('RESUMEN DE KILOMETRAJE'),
          pw.SizedBox(height: 6),
          _resumenKm(
            kmSalida: kmSalida,
            kmEntrada: kmEntrada,
            kmTotal: kmTotal,
            duracion: duracion,
            horaSalida: horaSalida,
            horaEntrada: horaEntrada,
          ),
          pw.SizedBox(height: 16),
          _bloqueFotos('FOTOS · SALIDA', fotosSalida),
          pw.SizedBox(height: 12),
          _bloqueFotos('FOTOS · ENTRADA (REGRESO)', fotosEntrada),
        ],
      ),
    );

    return doc.save();
  }

  // ---- Piezas del PDF ----

  static pw.Widget _titulo(String vehiculo, String placa) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const pw.BoxDecoration(color: _navy),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('COMPROBANTE DE VIAJE',
                    style: pw.TextStyle(
                        color: _amber,
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1)),
                pw.SizedBox(height: 2),
                pw.Text(vehiculo,
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                  color: _amber,
                  borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text(placa,
                  style: pw.TextStyle(
                      color: _navy,
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      );

  static pw.Widget _seccion(String txt) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        color: _greyBg,
        child: pw.Text(txt,
            style: pw.TextStyle(
                color: _navy,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.5)),
      );

  static pw.Widget _tablaDatos(Map<String, String> datos) {
    final entries = datos.entries.toList();
    return pw.Table(
      border: pw.TableBorder.all(color: _greyLine, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(120),
        1: pw.FlexColumnWidth(),
      },
      children: [
        for (final e in entries)
          pw.TableRow(children: [
            pw.Container(
              color: _greyBg,
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(e.key,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(e.value, style: const pw.TextStyle(fontSize: 9)),
            ),
          ]),
      ],
    );
  }

  static pw.Widget _resumenKm({
    required double kmSalida,
    required double kmEntrada,
    required double kmTotal,
    required String duracion,
    required String horaSalida,
    required String horaEntrada,
  }) {
    pw.Widget celda(String label, String valor, {bool destacado = false}) =>
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: pw.BoxDecoration(
              color: destacado ? _navy : _greyBg,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(children: [
              pw.Text(valor,
                  style: pw.TextStyle(
                      color: destacado ? _amber : _navy,
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(label,
                  style: pw.TextStyle(
                      color: destacado ? PdfColors.white : PdfColors.grey700,
                      fontSize: 8)),
            ]),
          ),
        );

    return pw.Column(children: [
      pw.Row(children: [
        celda('Salida (km)', kmSalida.toStringAsFixed(0)),
        pw.SizedBox(width: 6),
        celda('Entrada (km)', kmEntrada.toStringAsFixed(0)),
        pw.SizedBox(width: 6),
        celda('Total recorrido', '${kmTotal.toStringAsFixed(1)} km',
            destacado: true),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        celda('Hora de salida', horaSalida),
        pw.SizedBox(width: 6),
        celda('Hora de entrada', horaEntrada),
        pw.SizedBox(width: 6),
        celda('Duración', duracion),
      ]),
    ]);
  }

  static pw.Widget _bloqueFotos(String titulo, List<_Foto> fotos) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _seccion(titulo),
        pw.SizedBox(height: 6),
        if (fotos.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Sin fotos registradas.',
                style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                    fontStyle: pw.FontStyle.italic)),
          )
        else
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in fotos)
                pw.Container(
                  width: 160,
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _greyLine, width: 0.5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.ClipRect(
                        child: pw.Container(
                          height: 120,
                          alignment: pw.Alignment.center,
                          child: pw.Image(f.image, fit: pw.BoxFit.cover),
                        ),
                      ),
                      pw.Container(
                        color: _greyBg,
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 4, vertical: 3),
                        child: pw.Text(f.label,
                            style: pw.TextStyle(
                                fontSize: 8,
                                color: _navy,
                                fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}

class _Foto {
  final String label;
  final pw.MemoryImage image;
  _Foto(this.label, this.image);
}
