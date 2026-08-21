// =============================================================================
// auditoria.dart — Modelos de Auditoría de Vehículos
// Rúbrica editable (catálogo en BD flotilla.auditoria_rubrica) + cabecera
// (flotilla.auditorias) + resultado por ítem (flotilla.auditoria_items).
// =============================================================================

/// Un ítem del catálogo maestro de la rúbrica.
class RubricaItem {
  final String id;
  final String categoria;
  final String itemSlug;
  final String itemLabel;
  final String? ayuda;
  final bool soloPesados;
  final int orden;

  RubricaItem({
    required this.id,
    required this.categoria,
    required this.itemSlug,
    required this.itemLabel,
    this.ayuda,
    this.soloPesados = false,
    this.orden = 0,
  });

  factory RubricaItem.fromJson(Map<String, dynamic> j) => RubricaItem(
        id: j['id'].toString(),
        categoria: (j['categoria'] ?? '').toString(),
        itemSlug: (j['item_slug'] ?? '').toString(),
        itemLabel: (j['item_label'] ?? '').toString(),
        ayuda: j['ayuda']?.toString(),
        soloPesados: j['solo_pesados'] == true,
        orden: (j['orden'] is int) ? j['orden'] : int.tryParse('${j['orden']}') ?? 0,
      );
}

/// Resultado de un ítem dentro de una auditoría: buen | mal | na + nota + fotos.
class AuditoriaItem {
  final String rubricaId;
  final String itemSlug;
  final String itemLabel;
  final String categoria;
  String resultado; // buen | mal | na
  String? observacion;
  List<String> fotos; // URLs de fotos del ítem (subidas al guardar)

  AuditoriaItem({
    required this.rubricaId,
    required this.itemSlug,
    required this.itemLabel,
    required this.categoria,
    this.resultado = 'na',
    this.observacion,
    List<String>? fotos,
  }) : fotos = fotos ?? [];

  factory AuditoriaItem.fromRubrica(RubricaItem r) => AuditoriaItem(
        rubricaId: r.id,
        itemSlug: r.itemSlug,
        itemLabel: r.itemLabel,
        categoria: r.categoria,
      );

  factory AuditoriaItem.fromJson(Map<String, dynamic> j) => AuditoriaItem(
        rubricaId: (j['rubrica_id'] ?? '').toString(),
        itemSlug: (j['item_slug'] ?? '').toString(),
        itemLabel: (j['item_label'] ?? '').toString(),
        categoria: (j['categoria'] ?? '').toString(),
        resultado: (j['resultado'] ?? 'na').toString(),
        observacion: j['observacion']?.toString(),
        fotos: (j['fotos'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );

  Map<String, dynamic> toInsert(String auditoriaId) => {
        'auditoria_id': auditoriaId,
        'rubrica_id': rubricaId,
        'item_slug': itemSlug,
        'item_label': itemLabel,
        'categoria': categoria,
        'resultado': resultado,
        'observacion': (observacion?.trim().isEmpty ?? true) ? null : observacion!.trim(),
        'fotos': fotos,
      };
}

/// Foto de detalle con nota (para daños no listados en la rúbrica).
class FotoDetalle {
  final String url;
  final String? nota;
  FotoDetalle({required this.url, this.nota});

  factory FotoDetalle.fromJson(Map<String, dynamic> j) =>
      FotoDetalle(url: (j['url'] ?? '').toString(), nota: j['nota']?.toString());

  Map<String, dynamic> toJson() => {'url': url, if (nota != null && nota!.isNotEmpty) 'nota': nota};
}

/// Cabecera de auditoría con datos generales y resultado.
class Auditoria {
  final String? id;
  final String? vehiculoId;
  final String? auditorId;
  final DateTime fechaAuditoria;
  final int? kilometraje;
  final DateTime? fechaUltimoCambioAceite;
  final DateTime? fechaDekra;
  final DateTime? fechaVencPesoDim;
  final DateTime? fechaVencExtintor;
  final String? numTarjetaCirculacion;
  final String? encargadoCamion;
  final String? tipoVehiculo;
  final bool esPesado;
  final String estado; // Borrador | Completada
  final double? puntaje;
  final int totalItems;
  final int itemsBuenos;
  final int itemsMalos;
  final int itemsNa;
  final String? observacionesGenerales;
  final String? firmaConductor;
  final String? firmaCoordinador;
  final List<String> fotos;
  final List<FotoDetalle> fotosDetalle;

  Auditoria({
    this.id,
    this.vehiculoId,
    this.auditorId,
    required this.fechaAuditoria,
    this.kilometraje,
    this.fechaUltimoCambioAceite,
    this.fechaDekra,
    this.fechaVencPesoDim,
    this.fechaVencExtintor,
    this.numTarjetaCirculacion,
    this.encargadoCamion,
    this.tipoVehiculo,
    this.esPesado = false,
    this.estado = 'Borrador',
    this.puntaje,
    this.totalItems = 0,
    this.itemsBuenos = 0,
    this.itemsMalos = 0,
    this.itemsNa = 0,
    this.observacionesGenerales,
    this.firmaConductor,
    this.firmaCoordinador,
    this.fotos = const [],
    this.fotosDetalle = const [],
  });

  static String? _d(DateTime? d) => d?.toIso8601String().split('T').first;
  static DateTime? _pd(dynamic v) =>
      (v == null || '$v'.isEmpty) ? null : DateTime.tryParse('$v');

  Map<String, dynamic> toInsert() => {
        if (vehiculoId != null) 'vehiculo_id': vehiculoId,
        if (auditorId != null) 'auditor_id': auditorId,
        'fecha_auditoria': _d(fechaAuditoria),
        'kilometraje': kilometraje,
        'fecha_ultimo_cambio_aceite': _d(fechaUltimoCambioAceite),
        'fecha_dekra': _d(fechaDekra),
        'fecha_venc_peso_dim': _d(fechaVencPesoDim),
        'fecha_venc_extintor': _d(fechaVencExtintor),
        'num_tarjeta_circulacion': numTarjetaCirculacion,
        'encargado_camion': encargadoCamion,
        'tipo_vehiculo': tipoVehiculo,
        'es_pesado': esPesado,
        'estado': estado,
        'observaciones_generales': observacionesGenerales,
        'firma_conductor': firmaConductor,
        'firma_coordinador': firmaCoordinador,
        'fotos': fotos,
        'fotos_detalle': fotosDetalle.map((f) => f.toJson()).toList(),
      };

  factory Auditoria.fromJson(Map<String, dynamic> j) => Auditoria(
        id: j['id']?.toString(),
        vehiculoId: j['vehiculo_id']?.toString(),
        auditorId: j['auditor_id']?.toString(),
        fechaAuditoria: _pd(j['fecha_auditoria']) ?? DateTime.now(),
        kilometraje: j['kilometraje'] is int
            ? j['kilometraje']
            : int.tryParse('${j['kilometraje'] ?? ''}'),
        fechaUltimoCambioAceite: _pd(j['fecha_ultimo_cambio_aceite']),
        fechaDekra: _pd(j['fecha_dekra']),
        fechaVencPesoDim: _pd(j['fecha_venc_peso_dim']),
        fechaVencExtintor: _pd(j['fecha_venc_extintor']),
        numTarjetaCirculacion: j['num_tarjeta_circulacion']?.toString(),
        encargadoCamion: j['encargado_camion']?.toString(),
        tipoVehiculo: j['tipo_vehiculo']?.toString(),
        esPesado: j['es_pesado'] == true,
        estado: (j['estado'] ?? 'Borrador').toString(),
        puntaje: j['puntaje'] == null ? null : double.tryParse('${j['puntaje']}'),
        totalItems: j['total_items'] ?? 0,
        itemsBuenos: j['items_buenos'] ?? 0,
        itemsMalos: j['items_malos'] ?? 0,
        itemsNa: j['items_na'] ?? 0,
        observacionesGenerales: j['observaciones_generales']?.toString(),
        firmaConductor: j['firma_conductor']?.toString(),
        firmaCoordinador: j['firma_coordinador']?.toString(),
        fotos: (j['fotos'] as List?)?.map((e) => e.toString()).toList() ?? [],
        fotosDetalle: (j['fotos_detalle'] as List?)
                ?.map((e) => FotoDetalle.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
      );
}
