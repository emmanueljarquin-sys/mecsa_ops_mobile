// =============================================================================
// chat_service.dart — Chat CRM (WhatsApp) sobre Supabase, esquema `waba_crm`
// -----------------------------------------------------------------------------
// ESTADO: PENDIENTE DE CONECTAR. La interfaz (pestaña Chat, lista y
// conversación) está terminada y este servicio ya consulta `waba_crm`, pero
// hoy el rol `authenticated` no tiene permiso de lectura sobre ese esquema
// (Postgres responde "permission denied"), así que la pestaña muestra un
// aviso de "pendiente de conexión" hasta que:
//
//   1. Se exponga `waba_crm` en la API de Supabase y se dé SELECT a
//      `authenticated` sobre conversations, conversation_events, queues y
//      queue_members (con RLS: admin ve todo; los demás solo lo asignado).
//   2. Se confirmen los nombres de columna en [WabaCrm] (abajo) y se compile
//      con --dart-define=WABA_CHAT=true (o se cambie el valor por defecto).
//
// Tablas detectadas en el esquema: conversations, conversation_events
// (mensajes), conversation_notes, queues, queue_members.
//
// Regla de visibilidad (AppProvider.puedeVerChat decide quién ve la pestaña):
//   - admin: todas las conversaciones.
//   - vendedor / ventas / asesor / chat_role: solo las asignadas a él
//     (conversations.<asignadoA> = su empleado) o a una cola de la que es
//     miembro (queue_members).
//
// Sin conexión: lista e historial se leen de la caché (tabla `cache`).
// =============================================================================
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat.dart';
import 'app_logger.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

/// Nombres de tablas y columnas de `waba_crm`. Se ajustan aquí cuando se
/// confirme la estructura real; el resto del código no cambia.
class WabaCrm {
  static const String schema = 'waba_crm';

  // Tablas
  static const String tConversaciones = 'conversations';
  static const String tEventos = 'conversation_events';
  static const String tNotas = 'conversation_notes';
  static const String tColas = 'queues';
  static const String tMiembros = 'queue_members';

  // conversations
  static const String cId = 'id';
  static const String cWaId = 'wa_id'; // número del contacto (E.164 sin '+')
  static const String cNombre = 'contact_name';
  static const String cEmpresa = 'company';
  static const String cEstado = 'status'; // open | pending | closed
  static const String cAsignadoA = 'assigned_to'; // empleado/agente responsable
  static const String cCola = 'queue_id';
  static const String cNoLeidos = 'unread_count';
  static const String cUltimoMensaje = 'last_message';
  static const String cUltimaActividad = 'last_message_at';
  static const String cVentanaHasta = 'window_expires_at';
  static const String cEtiquetas = 'tags';

  // conversation_events (mensajes)
  static const String eId = 'id';
  static const String eConversacion = 'conversation_id';
  static const String eWaMessageId = 'wa_message_id';
  static const String eDireccion = 'direction'; // inbound | outbound
  static const String eTipo = 'type'; // text | image | audio | document | ...
  static const String eCuerpo = 'body';
  static const String eEstado = 'status'; // sent | delivered | read | failed
  static const String eFecha = 'created_at';
  static const String eMediaMime = 'media_mime_type';
  static const String eMediaNombre = 'media_filename';

  // queue_members
  static const String mCola = 'queue_id';
  static const String mMiembro = 'member_id'; // id de empleado / usuario
}

/// Interruptores del chat. Se cambian por --dart-define sin tocar código.
class ChatConfig extends ChangeNotifier {
  ChatConfig._();
  static final ChatConfig instance = ChatConfig._();

  /// Conexión con `waba_crm` activada. Apagado hasta que existan los permisos.
  static const bool conectado = bool.fromEnvironment('WABA_CHAT', defaultValue: false);

  /// Responder desde la app. Apagado a propósito: la barra de respuesta está
  /// construida pero informa que se responde desde el CRM web.
  static const bool envioHabilitado = bool.fromEnvironment('WABA_ENVIO', defaultValue: false);

  /// Compatibilidad con la UI: "configurado" = conexión activada.
  bool get configurado => conectado;

  Future<void> cargar() async {}
}

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  SupabaseClient get _sb => Supabase.instance.client;
  static const Duration _timeout = Duration(seconds: 20);

  /// Conversaciones visibles para el usuario. [empleadoId] y [esAdmin]
  /// aplican la regla de asignación.
  Future<List<ChatResumen>> listarChats({
    bool forzarRed = false,
    String? empleadoId,
    bool esAdmin = false,
  }) async {
    if (!ChatConfig.conectado) return _chatsDeCache();
    final online = await connectivity.checkInternet(force: forzarRed);
    if (!online) return _chatsDeCache();
    try {
      var q = _sb.schema(WabaCrm.schema).from(WabaCrm.tConversaciones).select('*');
      if (!esAdmin && empleadoId != null) {
        // Asignadas directamente o por cola de la que es miembro.
        final colas = await _sb
            .schema(WabaCrm.schema)
            .from(WabaCrm.tMiembros)
            .select(WabaCrm.mCola)
            .eq(WabaCrm.mMiembro, empleadoId)
            .timeout(_timeout);
        final colaIds = List<Map<String, dynamic>>.from(colas)
            .map((r) => r[WabaCrm.mCola]?.toString())
            .whereType<String>()
            .toList();
        final filtros = <String>[
          '${WabaCrm.cAsignadoA}.eq.$empleadoId',
          if (colaIds.isNotEmpty) '${WabaCrm.cCola}.in.(${colaIds.join(',')})',
        ];
        q = q.or(filtros.join(','));
      }
      final res = await q
          .order(WabaCrm.cUltimaActividad, ascending: false, nullsFirst: false)
          .limit(200)
          .timeout(_timeout);
      final lista = List<Map<String, dynamic>>.from(res).map(_resumenDeFila).toList();
      await cache.put('chat_lista', lista.map((e) => e.toJson()).toList());
      return lista;
    } catch (e) {
      log.w('chat', 'No se pudo listar chats; usando caché', error: e);
      final c = await _chatsDeCache();
      if (c.isEmpty) rethrow;
      return c;
    }
  }

  ChatResumen _resumenDeFila(Map<String, dynamic> r) {
    String s(Object? o) => (o ?? '').toString();
    final act = DateTime.tryParse(s(r[WabaCrm.cUltimaActividad]))?.toLocal();
    final ventana = DateTime.tryParse(s(r[WabaCrm.cVentanaHasta]))?.toLocal();
    final waId = s(r[WabaCrm.cWaId]);
    final ultimoTexto = s(r[WabaCrm.cUltimoMensaje]);
    return ChatResumen(
      waId: waId,
      conversacionId: s(r[WabaCrm.cId]),
      nombre: s(r[WabaCrm.cNombre]).isEmpty ? waId : s(r[WabaCrm.cNombre]),
      empresa: r[WabaCrm.cEmpresa]?.toString(),
      etiquetas: (r[WabaCrm.cEtiquetas] as List? ?? []).map((e) => e.toString()).toList(),
      ventanaAbierta: ventana != null && ventana.isAfter(DateTime.now()),
      asignadoA: r[WabaCrm.cAsignadoA]?.toString(),
      estado: s(r[WabaCrm.cEstado]),
      ultimoMensaje: ultimoTexto.isEmpty || act == null
          ? null
          : ChatMensaje(
              id: '',
              direccion: 'inbound',
              de: waId,
              para: '',
              tipo: 'text',
              cuerpo: ultimoTexto,
              estado: 'received',
              fecha: act,
            ),
      noLeidos: (r[WabaCrm.cNoLeidos] as num?)?.toInt() ?? 0,
      ultimaActividad: act ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<List<ChatResumen>> _chatsDeCache() async {
    final hit = await cache.get('chat_lista');
    return (hit?.asList() ?? []).map(ChatResumen.fromJson).toList();
  }

  /// Historial de una conversación (más antiguo → más reciente).
  Future<List<ChatMensaje>> mensajes(ChatResumen chat, {int take = 100}) async {
    final key = 'chat_msgs:${chat.conversacionId ?? chat.waId}';
    if (!ChatConfig.conectado || !await connectivity.checkInternet()) {
      return _mensajesDeCache(key);
    }
    try {
      final res = await _sb
          .schema(WabaCrm.schema)
          .from(WabaCrm.tEventos)
          .select('*')
          .eq(WabaCrm.eConversacion, chat.conversacionId ?? '')
          .order(WabaCrm.eFecha, ascending: false)
          .limit(take)
          .timeout(_timeout);
      final lista = List<Map<String, dynamic>>.from(res).map(_mensajeDeFila).toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
      await cache.put(key, lista.map((m) => m.toJson()).toList());
      return lista;
    } catch (e) {
      log.w('chat', 'No se pudo cargar el historial; usando caché', error: e);
      final c = await _mensajesDeCache(key);
      if (c.isEmpty) rethrow;
      return c;
    }
  }

  ChatMensaje _mensajeDeFila(Map<String, dynamic> r) {
    String s(Object? o) => (o ?? '').toString();
    final dir = s(r[WabaCrm.eDireccion]).toLowerCase();
    return ChatMensaje(
      id: s(r[WabaCrm.eId]),
      waMessageId: r[WabaCrm.eWaMessageId]?.toString(),
      direccion: dir == 'outbound' || dir == 'out' || dir == 'sent' ? 'outbound' : 'inbound',
      de: '',
      para: '',
      tipo: s(r[WabaCrm.eTipo]).isEmpty ? 'text' : s(r[WabaCrm.eTipo]).toLowerCase(),
      cuerpo: r[WabaCrm.eCuerpo]?.toString(),
      estado: s(r[WabaCrm.eEstado]).toLowerCase(),
      fecha: DateTime.tryParse(s(r[WabaCrm.eFecha]))?.toLocal() ?? DateTime.now(),
      mediaMime: r[WabaCrm.eMediaMime]?.toString(),
      mediaNombre: r[WabaCrm.eMediaNombre]?.toString(),
    );
  }

  Future<List<ChatMensaje>> _mensajesDeCache(String key) async {
    final hit = await cache.get(key);
    return (hit?.asList() ?? []).map(ChatMensaje.fromJson).toList();
  }

  /// Responder con texto. Preparado: inserta un evento saliente en
  /// `conversation_events`; el envío real a WhatsApp lo hace el backend del
  /// CRM al detectar el evento. Apagado hasta que se habilite.
  Future<ChatMensaje?> enviarTexto(ChatResumen chat, String texto) async {
    if (!ChatConfig.envioHabilitado) {
      throw 'Responder desde la app estará disponible próximamente.';
    }
    if (!ChatConfig.conectado) throw 'El chat aún no está conectado.';
    if (!await connectivity.checkInternet(force: true)) {
      throw 'Sin conexión a internet. Necesitas red para enviar mensajes.';
    }
    final res = await _sb
        .schema(WabaCrm.schema)
        .from(WabaCrm.tEventos)
        .insert({
          WabaCrm.eConversacion: chat.conversacionId,
          WabaCrm.eDireccion: 'outbound',
          WabaCrm.eTipo: 'text',
          WabaCrm.eCuerpo: texto,
          WabaCrm.eEstado: 'pending',
        })
        .select()
        .single()
        .timeout(_timeout);
    log.i('chat', 'Mensaje enviado', data: {'conversacion': chat.conversacionId});
    return _mensajeDeFila(Map<String, dynamic>.from(res));
  }

  /// Marcar leído: pendiente de definir en el esquema (columna o evento).
  Future<void> marcarLeido(String waMessageId) async {}
}
