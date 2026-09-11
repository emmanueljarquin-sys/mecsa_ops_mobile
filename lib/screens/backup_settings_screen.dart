// =============================================================================
// backup_settings_screen.dart — Perfil → Copias de seguridad
// -----------------------------------------------------------------------------
// Pantalla al estilo "Copia de seguridad" de WhatsApp:
//   - Estado: última sincronización, pendientes de subir, botón "Sincronizar".
//   - Copia automática diaria: activar/desactivar, hora (por defecto 02:00).
//   - Red permitida: solo WiFi, o WiFi + datos móviles.
//   - Historial reciente de lo que ya se subió.
// Toda la lógica vive en SyncService; aquí solo hay UI.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/offline_service.dart';
import '../services/sync_service.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    SyncService.instance.cargarPrefs();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    final h = await OfflineService.instance.historial(limit: 15);
    if (mounted) setState(() => _historial = h);
  }

  String _fmtFecha(DateTime? d) {
    if (d == null) return 'Nunca';
    final now = DateTime.now();
    final diff = now.difference(d);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    bool mismoDia(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (d.isAfter(now)) {
      // Fecha futura (próxima copia).
      if (mismoDia(d, now)) return 'Hoy a las $hh:$mm';
      if (mismoDia(d, now.add(const Duration(days: 1)))) return 'Mañana a las $hh:$mm';
    } else {
      if (diff.inMinutes < 1) return 'Hace un momento';
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      if (mismoDia(d, now)) return 'Hoy a las $hh:$mm';
      if (mismoDia(d, now.subtract(const Duration(days: 1)))) return 'Ayer a las $hh:$mm';
    }
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm';
  }

  String _tipoLegible(String t) {
    switch (t) {
      case 'registro_vehiculo':
        return 'Registro de vehículo';
      case 'liquidacion':
        return 'Liquidación';
      case 'factura':
        return 'Factura';
      case 'visita_crear':
        return 'Visita';
      case 'visita_inicio':
        return 'Inicio de visita';
      case 'visita_waypoints':
        return 'Recorrido de visita';
      case 'visita_fin':
        return 'Cierre de visita';
      default:
        return t;
    }
  }

  Future<void> _sincronizarAhora() async {
    final r = await SyncService.instance.sincronizar(manual: true);
    await _cargarHistorial();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.mensaje),
      backgroundColor: r.ok ? Colors.green.shade700 : Colors.orange.shade800,
    ));
  }

  Future<void> _elegirDiaSemana(SyncService s) async {
    const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    final v = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Día de la semana'),
        children: [
          for (int i = 1; i <= 7; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Row(children: [
                Icon(i == s.weekday ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20, color: Theme.of(context).primaryColor),
                const SizedBox(width: 10),
                Text(dias[i - 1]),
              ]),
            ),
        ],
      ),
    );
    if (v != null) await s.guardarPrefs(weekday: v);
  }

  Future<void> _elegirDiaMes(SyncService s) async {
    final v = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Día del mes'),
        content: SizedBox(
          width: 320,
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            children: [
              for (int i = 1; i <= 28; i++)
                InkWell(
                  onTap: () => Navigator.pop(context, i),
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == s.monthday ? Theme.of(context).primaryColor : null,
                      ),
                      child: Text('$i',
                          style: TextStyle(color: i == s.monthday ? Colors.white : null)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (v != null) await s.guardarPrefs(monthday: v);
  }

  Future<void> _elegirHora(SyncService s) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
      helpText: 'Hora de la copia diaria',
    );
    if (t != null) await s.guardarPrefs(hour: t.hour, minute: t.minute);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SyncService>.value(
      value: SyncService.instance,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('Copias de seguridad'),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
        ),
        body: Consumer2<SyncService, OfflineService>(
          builder: (context, s, offline, _) {
            final hh = s.hour.toString().padLeft(2, '0');
            final mm = s.minute.toString().padLeft(2, '0');
            final prox = s.proximaEjecucion;
            const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Estado ───────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F1FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              s.isRunning ? Icons.sync : Icons.cloud_done_outlined,
                              color: Theme.of(context).primaryColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Última copia',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                Text(_fmtFecha(s.lastRun),
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold)),
                                if (s.lastResult != null)
                                  Text(s.lastResult!,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700])),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _fila(
                        Icons.cloud_upload_outlined,
                        'Pendientes de subir',
                        offline.pendingCount == 0
                            ? 'Nada pendiente'
                            : '${offline.pendingCount} operación(es)',
                        color: offline.pendingCount == 0
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                      _fila(
                        Icons.schedule,
                        'Próxima copia automática',
                        prox == null ? 'Desactivada' : _fmtFecha(prox),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: s.isRunning ? null : _sincronizarAhora,
                          icon: s.isRunning
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.sync),
                          label: Text(s.isRunning
                              ? (s.pasoActual ?? 'Sincronizando…')
                              : 'SINCRONIZAR AHORA'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sube lo que quedó guardado sin conexión y descarga tus reservas, liquidaciones del último mes y visitas al teléfono.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Text('Copia automática',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Se ejecuta aunque la app esté cerrada. Android puede moverla unos minutos para ahorrar batería.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                _tarjeta(children: [
                  SwitchListTile(
                    title: const Text('Copia automática'),
                    subtitle: Text(s.enabled ? s.descripcionFrecuencia : 'Desactivada'),
                    value: s.enabled,
                    onChanged: (v) => s.guardarPrefs(enabled: v),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.repeat, size: 20),
                        const SizedBox(width: 12),
                        const Text('Frecuencia'),
                        const Spacer(),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(value: 'diaria', label: Text('Diaria')),
                            ButtonSegment(value: 'semanal', label: Text('Semanal')),
                            ButtonSegment(value: 'mensual', label: Text('Mensual')),
                          ],
                          selected: {s.freq},
                          onSelectionChanged: s.enabled
                              ? (v) => s.guardarPrefs(freq: v.first)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  if (s.freq == 'semanal')
                    ListTile(
                      enabled: s.enabled,
                      leading: const Icon(Icons.calendar_view_week),
                      title: const Text('Día de la semana'),
                      subtitle: Text(dias[(s.weekday - 1).clamp(0, 6)]),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: s.enabled ? () => _elegirDiaSemana(s) : null,
                    ),
                  if (s.freq == 'mensual')
                    ListTile(
                      enabled: s.enabled,
                      leading: const Icon(Icons.calendar_month),
                      title: const Text('Día del mes'),
                      subtitle: Text('Día ${s.monthday}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: s.enabled ? () => _elegirDiaMes(s) : null,
                    ),
                  ListTile(
                    enabled: s.enabled,
                    leading: const Icon(Icons.access_time),
                    title: const Text('Hora'),
                    subtitle: Text('$hh:$mm'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: s.enabled ? () => _elegirHora(s) : null,
                  ),
                ]),

                const SizedBox(height: 24),
                const Text('Sincronizar usando',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _tarjeta(children: [
                  RadioListTile<bool>(
                    title: const Text('Solo WiFi'),
                    subtitle: const Text('Recomendado. No consume tu plan de datos.'),
                    value: true,
                    groupValue: s.wifiOnly,
                    onChanged: (v) => s.guardarPrefs(wifiOnly: true),
                  ),
                  RadioListTile<bool>(
                    title: const Text('WiFi o datos móviles'),
                    subtitle: const Text('Sube y descarga aunque no haya WiFi.'),
                    value: false,
                    groupValue: s.wifiOnly,
                    onChanged: (v) => s.guardarPrefs(wifiOnly: false),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  'La sincronización automática al recuperar conexión y el botón "Sincronizar ahora" siempre usan la red disponible.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),

                const SizedBox(height: 24),
                const Text('Pendientes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (offline.pendientes.isEmpty)
                  _tarjeta(children: const [
                    ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('Todo está subido'),
                    ),
                  ])
                else
                  _tarjeta(
                    children: offline.pendientes.map((op) {
                      final creado = DateTime.tryParse(op['createdAt']?.toString() ?? '')?.toLocal();
                      final err = op['lastError']?.toString();
                      return ListTile(
                        leading: Icon(Icons.cloud_upload_outlined,
                            color: Colors.orange.shade800),
                        title: Text(_tipoLegible(op['type'].toString())),
                        subtitle: Text([
                          'Guardado ${_fmtFecha(creado).toLowerCase()}',
                          if ((op['attempts'] ?? 0) > 0)
                            '${op['attempts']} intento(s)',
                          if (err != null && err.isNotEmpty) 'Último error: $err',
                        ].join(' · ')),
                        isThreeLine: err != null && err.isNotEmpty,
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 24),
                const Text('Subido recientemente',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_historial.isEmpty)
                  _tarjeta(children: const [
                    ListTile(
                      leading: Icon(Icons.history, color: Colors.grey),
                      title: Text('Sin subidas registradas todavía'),
                    ),
                  ])
                else
                  _tarjeta(
                    children: _historial.map((op) {
                      final ms = op['syncedMs'];
                      final fecha = ms is int
                          ? DateTime.fromMillisecondsSinceEpoch(ms)
                          : null;
                      return ListTile(
                        leading: const Icon(Icons.cloud_done, color: Colors.green),
                        title: Text(_tipoLegible(op['type'].toString())),
                        subtitle: Text('Subido ${_fmtFecha(fecha).toLowerCase()}'),
                        dense: true,
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _fila(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: color ?? const Color(0xFF212529))),
        ],
      ),
    );
  }

  Widget _tarjeta({required List<Widget> children}) {
    // Material (no Container) para que los ListTile pinten su fondo/ink.
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
