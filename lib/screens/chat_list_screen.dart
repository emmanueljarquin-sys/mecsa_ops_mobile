// =============================================================================
// chat_list_screen.dart — Pestaña "Chat" (CRM WhatsApp), estilo WhatsApp
// -----------------------------------------------------------------------------
// Lista de conversaciones con avatar de iniciales, nombre, último mensaje,
// hora y contador de no leídos. Buscar, deslizar para refrescar, banner sin
// conexión (muestra lo cacheado) y aviso cuando el chat no está configurado.
// Solo visible para roles con acceso (AppProvider.puedeVerChat).
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../services/chat_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../utils/mensajes_error.dart';
import '../widgets/offline_notice.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatResumen> _chats = [];
  bool _cargando = true;
  String? _error;
  String _filtro = '';
  Timer? _poll;
  final TextEditingController _buscar = TextEditingController();

  @override
  void initState() {
    super.initState();
    ChatConfig.instance.addListener(_onConfig);
    _cargar();
    // Refresco silencioso cada 20 s mientras la pestaña esté montada.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _cargar(silencioso: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _buscar.dispose();
    ChatConfig.instance.removeListener(_onConfig);
    super.dispose();
  }

  void _onConfig() => _cargar();

  Future<void> _cargar({bool silencioso = false, bool forzar = false}) async {
    if (!silencioso && mounted) setState(() => _cargando = _chats.isEmpty);
    try {
      final l = await ChatService.instance.listarChats(forzarRed: forzar);
      if (!mounted) return;
      setState(() {
        _chats = l;
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mensajeError(e, accion: 'cargar los chats');
        _cargando = false;
      });
    }
  }

  String _hora(DateTime d) {
    final now = DateTime.now();
    final hh = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return hh;
    final ayer = now.subtract(const Duration(days: 1));
    if (d.year == ayer.year && d.month == ayer.month && d.day == ayer.day) return 'Ayer';
    if (now.difference(d).inDays < 7) {
      const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      return dias[d.weekday - 1];
    }
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year % 100}';
  }

  Color _colorAvatar(String semilla) {
    const paleta = [
      Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFF8B5CF6),
      Color(0xFFEF4444), Color(0xFF14B8A6), Color(0xFFF97316), Color(0xFF6366F1),
    ];
    return paleta[semilla.hashCode.abs() % paleta.length];
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cfg = context.watch<ChatConfig>();
    final online = context.watch<ConnectivityService>().isOnline;
    final filtrados = _filtro.isEmpty
        ? _chats
        : _chats.where((ch) {
            final f = _filtro.toLowerCase();
            return ch.nombre.toLowerCase().contains(f) ||
                ch.waId.contains(f) ||
                (ch.empresa ?? '').toLowerCase().contains(f) ||
                (ch.ultimoMensaje?.resumen.toLowerCase().contains(f) ?? false);
          }).toList();
    final noLeidosTotal = _chats.fold<int>(0, (a, b) => a + b.noLeidos);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Chat CRM',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          noLeidosTotal > 0
                              ? '$noLeidosTotal mensaje(s) sin leer'
                              : 'Conversaciones de WhatsApp',
                          style: TextStyle(fontSize: 14, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _cargar(forzar: true),
                  ),
                ],
              ),
            ),
            // Buscador
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _buscar,
                onChanged: (v) => setState(() => _filtro = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, número o mensaje',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filtro.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _buscar.clear();
                            setState(() => _filtro = '');
                          },
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OfflineNotice(
                margin: const EdgeInsets.only(bottom: 8),
                texto: 'Sin conexión: se muestran las conversaciones guardadas. No se pueden enviar mensajes.',
              ),
            ),
            if (!cfg.configurado)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.blue.withValues(alpha: 0.18) : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.settings_suggest, color: Colors.blue.shade800),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'El chat no está configurado. Un administrador debe indicar la URL, la cuenta y la clave de Wapi en Perfil → Chat CRM.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0C4A6E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _chats.isEmpty
                      ? _vacio(Icons.cloud_off, _error!, accion: () => _cargar(forzar: true))
                      : filtrados.isEmpty
                          ? _vacio(
                              Icons.chat_bubble_outline,
                              _filtro.isEmpty
                                  ? (cfg.configurado
                                      ? 'No hay conversaciones todavía.'
                                      : 'Configura el chat para ver las conversaciones.')
                                  : 'Sin resultados para "$_filtro".',
                            )
                          : RefreshIndicator(
                              onRefresh: () => _cargar(forzar: true),
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: filtrados.length,
                                separatorBuilder: (_, __) =>
                                    Divider(height: 1, indent: 82, color: c.border),
                                itemBuilder: (context, i) => _fila(filtrados[i], online),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vacio(IconData icon, String texto, {VoidCallback? accion}) {
    final c = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: c.textMuted),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
            if (accion != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: accion, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fila(ChatResumen ch, bool online) {
    final c = AppColors.of(context);
    final u = ch.ultimoMensaje;
    final preview = u == null
        ? (ch.empresa?.isNotEmpty == true ? ch.empresa! : ch.telefono)
        : (u.esSaliente ? 'Tú: ${u.resumen}' : u.resumen);
    final negrita = ch.noLeidos > 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _colorAvatar(ch.waId),
            child: Text(ch.iniciales,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (ch.ventanaAbierta)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366),
                  shape: BoxShape.circle,
                  border: Border.all(color: c.background, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              ch.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: negrita ? FontWeight.bold : FontWeight.w600,
                fontSize: 16,
                color: c.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            u == null ? '' : _hora(u.fecha),
            style: TextStyle(
              fontSize: 12,
              color: negrita ? const Color(0xFF25D366) : c.textMuted,
              fontWeight: negrita ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            if (u != null && u.esSaliente) ...[
              _ticks(u.estado, c),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: negrita ? c.textPrimary : c.textSecondary,
                  fontWeight: negrita ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (ch.noLeidos > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
                child: Text('${ch.noLeidos}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              )
            else if (ch.bloqueado || ch.optOut)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(ch.bloqueado ? Icons.block : Icons.do_not_disturb_on_outlined,
                    size: 16, color: c.textMuted),
              ),
          ],
        ),
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatDetailScreen(chat: ch)),
        );
        _cargar(silencioso: true);
      },
    );
  }

  static Widget _ticks(String estado, AppColors c) {
    switch (estado) {
      case 'read':
        return const Icon(Icons.done_all, size: 16, color: Color(0xFF34B7F1));
      case 'delivered':
        return Icon(Icons.done_all, size: 16, color: c.textMuted);
      case 'sent':
        return Icon(Icons.done, size: 16, color: c.textMuted);
      case 'failed':
        return const Icon(Icons.error_outline, size: 16, color: Colors.red);
      default:
        return Icon(Icons.schedule, size: 14, color: c.textMuted);
    }
  }
}
