// =============================================================================
// chat_detail_screen.dart — Conversación (burbujas estilo WhatsApp)
// -----------------------------------------------------------------------------
// Historial del chat con burbujas entrantes/salientes, separadores por día,
// estado (✓ ✓✓) y barra de respuesta. El envío está construido pero se
// habilita con ChatConfig.envioHabilitado (hoy apagado: muestra "próximamente").
// Sin conexión muestra el historial en caché y bloquea el envío.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../services/chat_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../utils/mensajes_error.dart';

class ChatDetailScreen extends StatefulWidget {
  final ChatResumen chat;
  const ChatDetailScreen({super.key, required this.chat});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  List<ChatMensaje> _msgs = [];
  bool _cargando = true;
  bool _enviando = false;
  String? _error;
  Timer? _poll;
  final TextEditingController _texto = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _cargar();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _cargar(silencioso: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    try {
      final l = await ChatService.instance.mensajes(widget.chat.waId);
      if (!mounted) return;
      final cambio = l.length != _msgs.length;
      setState(() {
        _msgs = l;
        _error = null;
        _cargando = false;
      });
      if (cambio) _irAlFinal();
      // Marcar leídos los entrantes pendientes (solo con red).
      for (final m in l.where((m) => m.esEntrante && m.estado != 'read' && (m.waMessageId ?? '').isNotEmpty)) {
        ChatService.instance.marcarLeido(m.waMessageId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = silencioso ? _error : mensajeError(e, accion: 'cargar la conversación');
        _cargando = false;
      });
    }
  }

  void _irAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _enviar() async {
    final t = _texto.text.trim();
    if (t.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      final m = await ChatService.instance.enviarTexto(widget.chat.waId, t);
      _texto.clear();
      if (m != null && mounted) {
        setState(() => _msgs = [..._msgs, m]);
        _irAlFinal();
      }
      _cargar(silencioso: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mensajeError(e, accion: 'enviar el mensaje')),
        backgroundColor: Colors.orange.shade800,
      ));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _diaLegible(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Hoy';
    final ayer = now.subtract(const Duration(days: 1));
    if (d.year == ayer.year && d.month == ayer.month && d.day == ayer.day) return 'Ayer';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dark = context.isDarkMode;
    final online = context.watch<ConnectivityService>().isOnline;
    final ch = widget.chat;
    final puedeEnviar = ChatConfig.envioHabilitado && online && !ch.bloqueado && !ch.optOut;

    // Fondo tipo WhatsApp.
    final Color fondo = dark ? const Color(0xFF0B141A) : const Color(0xFFECE5DD);
    final Color burbujaSal = dark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6);
    final Color burbujaEnt = dark ? const Color(0xFF202C33) : Colors.white;

    return Scaffold(
      backgroundColor: fondo,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF25D366),
              child: Text(ch.iniciales,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ch.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(
                    [
                      ch.telefono,
                      if (ch.empresa?.isNotEmpty == true) ch.empresa!,
                      ch.ventanaAbierta ? 'ventana abierta' : 'ventana cerrada',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualizar', onPressed: () => _cargar()),
        ],
      ),
      body: Column(
        children: [
          if (!online)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: const Text('Sin conexión: mostrando la conversación guardada.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7C2D12), fontWeight: FontWeight.w600)),
            ),
          if (ch.etiquetas.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                spacing: 6,
                children: ch.etiquetas
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ))
                    .toList(),
              ),
            ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _msgs.isEmpty
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
                              OutlinedButton(onPressed: () => _cargar(), child: const Text('Reintentar')),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        itemCount: _msgs.length,
                        itemBuilder: (context, i) {
                          final m = _msgs[i];
                          final prev = i > 0 ? _msgs[i - 1] : null;
                          final nuevoDia = prev == null ||
                              prev.fecha.day != m.fecha.day ||
                              prev.fecha.month != m.fecha.month ||
                              prev.fecha.year != m.fecha.year;
                          return Column(
                            children: [
                              if (nuevoDia)
                                Center(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: dark ? const Color(0xFF1F2C34) : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(_diaLegible(m.fecha),
                                        style: TextStyle(fontSize: 12, color: c.textSecondary)),
                                  ),
                                ),
                              _burbuja(m, m.esSaliente ? burbujaSal : burbujaEnt, dark),
                            ],
                          );
                        },
                      ),
          ),
          _barraEnvio(puedeEnviar, online, ch, dark),
        ],
      ),
    );
  }

  Widget _burbuja(ChatMensaje m, Color color, bool dark) {
    final c = AppColors.of(context);
    final hora = '${m.fecha.hour.toString().padLeft(2, '0')}:${m.fecha.minute.toString().padLeft(2, '0')}';
    final Color texto = dark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);
    return Align(
      alignment: m.esSaliente ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(10),
            topRight: const Radius.circular(10),
            bottomLeft: Radius.circular(m.esSaliente ? 10 : 2),
            bottomRight: Radius.circular(m.esSaliente ? 2 : 10),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 1, offset: const Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.tipo != 'text')
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconoTipo(m.tipo), size: 16, color: texto.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Flexible(child: Text(m.resumen, style: TextStyle(color: texto, fontStyle: FontStyle.italic))),
                  ],
                ),
              ),
            if ((m.cuerpo ?? '').trim().isNotEmpty && (m.tipo == 'text' || m.tipo == 'template' || m.tipo == 'interactive' || m.tipo == 'button'))
              Text(m.cuerpo!.trim(), style: TextStyle(color: texto, fontSize: 15)),
            if (m.tipo != 'text' && (m.cuerpo ?? '').trim().isNotEmpty && !(m.tipo == 'template' || m.tipo == 'interactive' || m.tipo == 'button'))
              Text(m.cuerpo!.trim(), style: TextStyle(color: texto, fontSize: 14)),
            if (m.error != null && m.error!.isNotEmpty)
              Text(m.error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hora, style: TextStyle(fontSize: 11, color: texto.withValues(alpha: 0.6))),
                if (m.esSaliente) ...[
                  const SizedBox(width: 4),
                  _tick(m.estado, c),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconoTipo(String t) {
    switch (t) {
      case 'image':
        return Icons.image;
      case 'audio':
        return Icons.mic;
      case 'video':
        return Icons.videocam;
      case 'document':
        return Icons.attach_file;
      case 'location':
        return Icons.location_on;
      case 'sticker':
        return Icons.emoji_emotions_outlined;
      default:
        return Icons.message;
    }
  }

  Widget _tick(String estado, AppColors c) {
    switch (estado) {
      case 'read':
        return const Icon(Icons.done_all, size: 15, color: Color(0xFF53BDEB));
      case 'delivered':
        return Icon(Icons.done_all, size: 15, color: c.textMuted);
      case 'sent':
        return Icon(Icons.done, size: 15, color: c.textMuted);
      case 'failed':
        return const Icon(Icons.error_outline, size: 15, color: Colors.red);
      default:
        return Icon(Icons.schedule, size: 13, color: c.textMuted);
    }
  }

  Widget _barraEnvio(bool puedeEnviar, bool online, ChatResumen ch, bool dark) {
    final c = AppColors.of(context);
    String? motivo;
    if (!ChatConfig.envioHabilitado) {
      motivo = 'Responder desde la app estará disponible próximamente. Por ahora responde desde el CRM web.';
    } else if (!online) {
      motivo = 'Sin conexión: no se pueden enviar mensajes.';
    } else if (ch.bloqueado) {
      motivo = 'Este contacto bloqueó el número del negocio.';
    } else if (ch.optOut) {
      motivo = 'Este contacto pidió no recibir mensajes.';
    } else if (!ch.ventanaAbierta) {
      motivo = 'La ventana de 24 h está cerrada: solo se pueden enviar plantillas aprobadas.';
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        color: dark ? const Color(0xFF1F2C34) : const Color(0xFFF0F2F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (motivo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: c.textMuted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(motivo, style: TextStyle(fontSize: 11, color: c.textSecondary))),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _texto,
                    enabled: puedeEnviar && !_enviando,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: puedeEnviar ? 'Escribe un mensaje' : 'Respuesta no disponible',
                      isDense: true,
                      filled: true,
                      fillColor: dark ? const Color(0xFF2A3942) : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      backgroundColor: const Color(0xFF25D366),
                      disabledBackgroundColor: c.surfaceVariant,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: puedeEnviar && !_enviando ? _enviar : null,
                    child: _enviando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
