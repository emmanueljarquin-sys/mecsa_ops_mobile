// =============================================================================
// chat.dart — Modelos del chat CRM (Wapi / WhatsApp)
// =============================================================================

/// Un mensaje de WhatsApp (entrante o saliente).
class ChatMensaje {
  final String id;
  final String? waMessageId;
  /// 'inbound' | 'outbound'
  final String direccion;
  final String de;
  final String para;
  /// text | image | audio | document | location | ...
  final String tipo;
  final String? cuerpo;
  /// pending | sent | delivered | read | failed | received
  final String estado;
  final DateTime fecha;
  final String? mediaMime;
  final String? mediaNombre;
  final String? error;
  final double? lat;
  final double? lng;

  const ChatMensaje({
    required this.id,
    this.waMessageId,
    required this.direccion,
    required this.de,
    required this.para,
    required this.tipo,
    this.cuerpo,
    required this.estado,
    required this.fecha,
    this.mediaMime,
    this.mediaNombre,
    this.error,
    this.lat,
    this.lng,
  });

  bool get esEntrante => direccion == 'inbound';
  bool get esSaliente => !esEntrante;

  /// Texto para mostrar en la lista (o descripción del adjunto).
  String get resumen {
    final c = (cuerpo ?? '').trim();
    if (c.isNotEmpty) return c;
    switch (tipo) {
      case 'image':
        return '📷 Foto';
      case 'audio':
        return '🎤 Audio';
      case 'video':
        return '🎬 Video';
      case 'document':
        return '📎 ${mediaNombre ?? 'Documento'}';
      case 'location':
        return '📍 Ubicación';
      case 'sticker':
        return '🙂 Sticker';
      case 'template':
        return 'Plantilla';
      default:
        return tipo;
    }
  }

  static const _dirs = ['inbound', 'outbound'];
  static const _estados = ['pending', 'sent', 'delivered', 'read', 'failed', 'received'];

  /// Acepta los dos formatos de Wapi: el historial por contacto (enums en
  /// texto, campos en camelCase) y la lista de la cuenta (enums numéricos).
  factory ChatMensaje.fromJson(Map<String, dynamic> j) {
    String s(Object? o) => (o ?? '').toString();
    String enumStr(Object? v, List<String> nombres) {
      if (v is int) return (v >= 0 && v < nombres.length) ? nombres[v] : s(v);
      final t = s(v).toLowerCase();
      final n = int.tryParse(t);
      if (n != null && n >= 0 && n < nombres.length) return nombres[n];
      return t;
    }
    return ChatMensaje(
      id: s(j['id']),
      waMessageId: j['waMessageId']?.toString(),
      direccion: enumStr(j['direction'], _dirs),
      de: s(j['from']),
      para: s(j['to']),
      tipo: s(j['type']).isEmpty ? 'text' : s(j['type']).toLowerCase(),
      cuerpo: j['body']?.toString(),
      estado: enumStr(j['status'], _estados),
      fecha: DateTime.tryParse(s(j['createdAt']))?.toLocal() ?? DateTime.now(),
      mediaMime: j['mediaMimeType']?.toString(),
      mediaNombre: j['mediaFilename']?.toString(),
      error: j['errorMessage']?.toString(),
      lat: (j['locationLatitude'] as num?)?.toDouble(),
      lng: (j['locationLongitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'waMessageId': waMessageId,
        'direction': direccion,
        'from': de,
        'to': para,
        'type': tipo,
        'body': cuerpo,
        'status': estado,
        'createdAt': fecha.toUtc().toIso8601String(),
        'mediaMimeType': mediaMime,
        'mediaFilename': mediaNombre,
        'errorMessage': error,
        'locationLatitude': lat,
        'locationLongitude': lng,
      };
}

/// Un chat (contacto de WhatsApp) en la lista.
class ChatResumen {
  final String waId;
  final String nombre;
  final String? empresa;
  final List<String> etiquetas;
  final bool ventanaAbierta;
  final bool bloqueado;
  final bool optOut;
  final ChatMensaje? ultimoMensaje;
  final int noLeidos;
  final DateTime ultimaActividad;

  const ChatResumen({
    required this.waId,
    required this.nombre,
    this.empresa,
    this.etiquetas = const [],
    this.ventanaAbierta = false,
    this.bloqueado = false,
    this.optOut = false,
    this.ultimoMensaje,
    this.noLeidos = 0,
    required this.ultimaActividad,
  });

  /// Número legible: +506 8888 8888 a partir de "50688888888".
  String get telefono {
    final d = waId.replaceAll(RegExp(r'\D'), '');
    if (d.length <= 8) return d;
    final cc = d.substring(0, d.length - 8);
    final local = d.substring(d.length - 8);
    return '+$cc ${local.substring(0, 4)} ${local.substring(4)}';
  }

  String get iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '#';
    final a = partes.first[0];
    final b = partes.length > 1 ? partes.last[0] : '';
    final ini = (a + b).toUpperCase();
    return RegExp(r'^[A-ZÁÉÍÓÚÑ]+$').hasMatch(ini) ? ini : '#';
  }

  factory ChatResumen.fromContacto(Map<String, dynamic> c,
      {ChatMensaje? ultimo, int noLeidos = 0}) {
    String s(Object? o) => (o ?? '').toString();
    final waId = s(c['waId']);
    final lastSeen = DateTime.tryParse(s(c['lastSeenAt']))?.toLocal();
    final act = [
      if (lastSeen != null) lastSeen,
      if (ultimo != null) ultimo.fecha,
    ];
    return ChatResumen(
      waId: waId,
      nombre: s(c['name']).isEmpty ? waId : s(c['name']),
      empresa: c['company']?.toString(),
      etiquetas: (c['tags'] as List? ?? []).map((e) => e.toString()).toList(),
      ventanaAbierta: c['windowOpen'] == true,
      bloqueado: c['blocked'] == true,
      optOut: c['optedOut'] == true,
      ultimoMensaje: ultimo,
      noLeidos: noLeidos,
      ultimaActividad: act.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : act.reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  factory ChatResumen.fromJson(Map<String, dynamic> j) => ChatResumen(
        waId: (j['waId'] ?? '').toString(),
        nombre: (j['nombre'] ?? j['waId'] ?? '').toString(),
        empresa: j['empresa']?.toString(),
        etiquetas: (j['etiquetas'] as List? ?? []).map((e) => e.toString()).toList(),
        ventanaAbierta: j['ventanaAbierta'] == true,
        bloqueado: j['bloqueado'] == true,
        optOut: j['optOut'] == true,
        ultimoMensaje: j['ultimoMensaje'] is Map
            ? ChatMensaje.fromJson(Map<String, dynamic>.from(j['ultimoMensaje']))
            : null,
        noLeidos: (j['noLeidos'] as num?)?.toInt() ?? 0,
        ultimaActividad: DateTime.tryParse((j['ultimaActividad'] ?? '').toString())?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'waId': waId,
        'nombre': nombre,
        'empresa': empresa,
        'etiquetas': etiquetas,
        'ventanaAbierta': ventanaAbierta,
        'bloqueado': bloqueado,
        'optOut': optOut,
        'ultimoMensaje': ultimoMensaje?.toJson(),
        'noLeidos': noLeidos,
        'ultimaActividad': ultimaActividad.toUtc().toIso8601String(),
      };
}
