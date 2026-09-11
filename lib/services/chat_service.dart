// =============================================================================
// chat_service.dart — Chat CRM (WhatsApp) vía API de Wapi
// -----------------------------------------------------------------------------
// El chat del CRM no vive en Supabase: lo sirve la plataforma Wapi (API .NET
// de WhatsApp de Grupo Mecsa). Este servicio consume esos endpoints en modo
// lectura y deja listo el envío:
//
//   GET  /api/accounts/{cuenta}/contacts?take=..            lista de chats
//   GET  /api/accounts/{cuenta}/messages?take=200           últimos mensajes de la cuenta
//   GET  /api/accounts/{cuenta}/contacts/{waId}/messages    historial de un chat
//   POST /api/accounts/{cuenta}/messages/text               responder (texto)
//   POST /api/accounts/{cuenta}/messages/{waMessageId}/read marcar leído
//
// Autenticación: header `X-Api-Key` con una clave de integración del tenant.
// La URL base, la cuenta y la clave se configuran en Perfil → Chat CRM
// (ChatConfig, guardado en SharedPreferences) o por --dart-define.
//
// Sin conexión: la lista y el historial se leen de la caché (tabla `cache`),
// así que los chats ya vistos se pueden consultar sin red. No se encola el
// envío: responder requiere conexión (ventana de 24 h de WhatsApp).
// =============================================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';
import 'app_logger.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

/// Configuración de acceso a Wapi. Valores por defecto vía `--dart-define`
/// (WAPI_BASE_URL, WAPI_ACCOUNT_ID, WAPI_API_KEY); el usuario admin puede
/// sobrescribirlos desde Perfil.
class ChatConfig extends ChangeNotifier {
  ChatConfig._();
  static final ChatConfig instance = ChatConfig._();

  static const String _defBase = String.fromEnvironment('WAPI_BASE_URL', defaultValue: '');
  static const String _defAccount = String.fromEnvironment('WAPI_ACCOUNT_ID', defaultValue: '');
  static const String _defKey = String.fromEnvironment('WAPI_API_KEY', defaultValue: '');

  /// Enviar respuestas desde la app. De momento apagado a propósito: la UI
  /// está construida, pero el botón muestra "próximamente".
  static const bool envioHabilitado = bool.fromEnvironment('WAPI_ENVIO', defaultValue: false);

  String baseUrl = _defBase;
  String accountId = _defAccount;
  String apiKey = _defKey;
  bool _cargada = false;

  bool get configurado =>
      baseUrl.trim().isNotEmpty && accountId.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  Future<void> cargar() async {
    if (_cargada) return;
    try {
      final p = await SharedPreferences.getInstance();
      baseUrl = p.getString('chat_base_url') ?? _defBase;
      accountId = p.getString('chat_account_id') ?? _defAccount;
      apiKey = p.getString('chat_api_key') ?? _defKey;
    } catch (_) {}
    _cargada = true;
    notifyListeners();
  }

  Future<void> guardar({String? baseUrl, String? accountId, String? apiKey}) async {
    final p = await SharedPreferences.getInstance();
    if (baseUrl != null) {
      this.baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      await p.setString('chat_base_url', this.baseUrl);
    }
    if (accountId != null) {
      this.accountId = accountId.trim();
      await p.setString('chat_account_id', this.accountId);
    }
    if (apiKey != null) {
      this.apiKey = apiKey.trim();
      await p.setString('chat_api_key', this.apiKey);
    }
    notifyListeners();
  }
}

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  static const Duration _timeout = Duration(seconds: 20);

  ChatConfig get _cfg => ChatConfig.instance;

  Uri _uri(String path, [Map<String, String>? q]) => Uri.parse(
        '${_cfg.baseUrl}/api/accounts/${_cfg.accountId}/$path',
      ).replace(queryParameters: q);

  Map<String, String> get _headers => {
        'X-Api-Key': _cfg.apiKey,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<dynamic> _get(String path, [Map<String, String>? q]) async {
    final r = await http.get(_uri(path, q), headers: _headers).timeout(_timeout);
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw 'La clave del chat no es válida o no tiene permiso.';
    }
    if (r.statusCode == 404) throw 'La cuenta de WhatsApp configurada no existe.';
    if (r.statusCode >= 400) throw 'El servidor del chat respondió ${r.statusCode}.';
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw 'La clave del chat no es válida o no tiene permiso.';
    }
    if (r.statusCode >= 400) {
      String msg = 'El servidor del chat respondió ${r.statusCode}.';
      try {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw msg;
    }
    return r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Prueba de conexión (Perfil → Chat CRM → Probar).
  Future<String> probar() async {
    if (!_cfg.configurado) throw 'Falta configurar URL, cuenta o clave.';
    final j = await _get('contacts', {'take': '1'});
    final total = (j is Map ? j['total'] : null) ?? '?';
    return 'Conexión correcta. Contactos en la cuenta: $total';
  }

  /// Lista de chats: contactos ordenados por actividad, con el último
  /// mensaje de cada uno (tomado de los últimos 200 mensajes de la cuenta).
  Future<List<ChatResumen>> listarChats({bool forzarRed = false}) async {
    if (!_cfg.configurado) return _chatsDeCache();
    final online = await connectivity.checkInternet(force: forzarRed);
    if (!online) return _chatsDeCache();
    try {
      final results = await Future.wait([
        _get('contacts', {'take': '100'}),
        _get('messages', {'take': '200'}),
      ]);
      final contactos = List<Map<String, dynamic>>.from(
          ((results[0] as Map)['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
      final mensajes = List<Map<String, dynamic>>.from(
          (results[1] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

      // Último mensaje y no leídos por contacto.
      final ultimo = <String, ChatMensaje>{};
      final noLeidos = <String, int>{};
      for (final raw in mensajes) {
        final m = ChatMensaje.fromJson(raw);
        final waId = m.esEntrante ? m.de : m.para;
        if (waId.isEmpty) continue;
        final prev = ultimo[waId];
        if (prev == null || m.fecha.isAfter(prev.fecha)) ultimo[waId] = m;
        if (m.esEntrante && m.estado != 'read') {
          noLeidos[waId] = (noLeidos[waId] ?? 0) + 1;
        }
      }

      final lista = contactos.map((c) {
        final waId = (c['waId'] ?? '').toString();
        return ChatResumen.fromContacto(c, ultimo: ultimo[waId], noLeidos: noLeidos[waId] ?? 0);
      }).toList();
      // Contactos con mensajes recientes que no vinieron en la primera página.
      for (final e in ultimo.entries) {
        if (!lista.any((x) => x.waId == e.key)) {
          lista.add(ChatResumen(
            waId: e.key,
            nombre: e.key,
            ultimoMensaje: e.value,
            noLeidos: noLeidos[e.key] ?? 0,
            ultimaActividad: e.value.fecha,
          ));
        }
      }
      lista.sort((a, b) => b.ultimaActividad.compareTo(a.ultimaActividad));
      await cache.put('chat_lista', lista.map((e) => e.toJson()).toList());
      return lista;
    } catch (e) {
      log.w('chat', 'No se pudo listar chats; usando caché', error: e);
      final c = await _chatsDeCache();
      if (c.isEmpty) rethrow;
      return c;
    }
  }

  Future<List<ChatResumen>> _chatsDeCache() async {
    final hit = await cache.get('chat_lista');
    return (hit?.asList() ?? []).map(ChatResumen.fromJson).toList();
  }

  /// Historial de un chat (más antiguo → más reciente).
  Future<List<ChatMensaje>> mensajes(String waId, {int take = 100}) async {
    final key = 'chat_msgs:$waId';
    if (!_cfg.configurado || !await connectivity.checkInternet()) {
      return _mensajesDeCache(key);
    }
    try {
      final j = await _get('contacts/$waId/messages', {'take': '$take'});
      final items = List<Map<String, dynamic>>.from(
          ((j as Map)['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
      final lista = items.map(ChatMensaje.fromJson).toList()
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

  Future<List<ChatMensaje>> _mensajesDeCache(String key) async {
    final hit = await cache.get(key);
    return (hit?.asList() ?? []).map(ChatMensaje.fromJson).toList();
  }

  /// Responder con texto. Requiere conexión; el servidor valida la ventana
  /// de 24 h de WhatsApp y devuelve el mensaje creado.
  Future<ChatMensaje?> enviarTexto(String waId, String texto) async {
    if (!ChatConfig.envioHabilitado) {
      throw 'Responder desde la app estará disponible próximamente.';
    }
    if (!_cfg.configurado) throw 'El chat no está configurado.';
    if (!await connectivity.checkInternet(force: true)) {
      throw 'Sin conexión a internet. Necesitas red para enviar mensajes.';
    }
    final j = await _post('messages/text', {'to': waId, 'text': texto});
    log.i('chat', 'Mensaje enviado', data: {'to': waId});
    if (j is Map) {
      try {
        return ChatMensaje.fromJson(Map<String, dynamic>.from(j));
      } catch (_) {}
    }
    return null;
  }

  Future<void> marcarLeido(String waMessageId) async {
    if (!_cfg.configurado || waMessageId.isEmpty) return;
    try {
      await _post('messages/$waMessageId/read', {});
    } catch (e) {
      log.d('chat', 'marcarLeido falló', data: {'id': waMessageId, 'error': e.toString()});
    }
  }
}
