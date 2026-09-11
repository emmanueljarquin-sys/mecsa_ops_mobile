import 'package:flutter/material.dart';
import '../../utils/mensajes_error.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../models/auditoria.dart';
import '../../services/auditoria_service.dart';
import 'auditoria_form_screen.dart';
import 'auditoria_detail_screen.dart';

class AuditoriasListScreen extends StatefulWidget {
  const AuditoriasListScreen({super.key});

  @override
  State<AuditoriasListScreen> createState() => _AuditoriasListScreenState();
}

class _AuditoriasListScreenState extends State<AuditoriasListScreen> {
  static const _navy = Color(0xFF013483);
  bool _loading = true;
  String? _error;
  List<Auditoria> _auditorias = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = Provider.of<AppProvider>(context, listen: false);
      final data = await AuditoriaService.getMisAuditorias(
        auditorId: p.currentEmployeeId ?? '',
        verTodas: p.isRoleAdmin, // admin ve todas; el resto solo las suyas
      );
      if (mounted) setState(() => _auditorias = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _colorPuntaje(double? p) {
    if (p == null) return Colors.grey;
    if (p >= 90) return Colors.green.shade600;
    if (p >= 70) return Colors.orange.shade700;
    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Auditorías de Vehículos'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const AuditoriaFormScreen()),
          );
          if (ok == true) _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView()
                : _auditorias.isEmpty
                    ? _emptyView()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: _auditorias.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _card(_auditorias[i]),
                      ),
      ),
    );
  }

  Widget _card(Auditoria a) {
    final veh = AuditoriaService.vehiculoInfo(a.vehiculoId);
    final vehTxt = veh == null
        ? 'Vehículo'
        : '${veh['marca'] ?? ''} ${veh['modelo'] ?? ''} · ${veh['placa'] ?? ''}';
    final fecha = DateFormat('dd/MM/yyyy').format(a.fechaAuditoria);
    final completada = a.estado == 'Completada';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AuditoriaDetailScreen(auditoria: a)),
        ),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: _colorPuntaje(a.puntaje).withValues(alpha: 0.15),
          child: Text(
            a.puntaje == null ? '—' : '${a.puntaje!.round()}%',
            style: TextStyle(
              color: _colorPuntaje(a.puntaje),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        title: Text(vehTxt.trim(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.event, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(fecha, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: completada ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  a.estado,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: completada ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _emptyView() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.fact_check_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Center(
            child: Text('Sin auditorías todavía',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Tocá "Nueva" para inspeccionar un vehículo',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          ),
        ],
      );

  Widget _errorView() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Center(child: Text(mensajeError(_error, accion: 'cargar las auditorías'), textAlign: TextAlign.center)),
        ],
      );
}
