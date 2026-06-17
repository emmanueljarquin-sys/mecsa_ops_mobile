import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/mfa_service.dart';
import 'mfa_backup_codes_screen.dart';

/// Pantalla de enroll TOTP. Si [forced]=true, no muestra "más tarde".
class MfaEnrollScreen extends StatefulWidget {
  const MfaEnrollScreen({super.key, this.forced = false});
  final bool forced;

  @override
  State<MfaEnrollScreen> createState() => _MfaEnrollScreenState();
}

class _MfaEnrollScreenState extends State<MfaEnrollScreen> {
  late final MfaService _mfa = MfaService(Supabase.instance.client);
  String? _factorId;
  String? _qrSvg;
  String? _secret;
  bool _loading = true;
  String? _error;
  bool _verifying = false;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final r = await _mfa.enrollStart();
      setState(() {
        _factorId = r.factorId;
        _qrSvg = r.qrCode;
        _secret = r.secret;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _verify() async {
    if (_factorId == null) return;
    final c = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(c)) {
      setState(() => _error = "Ingresa los 6 dígitos");
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final codigos = await _mfa.enrollVerify(factorId: _factorId!, code: c);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MfaBackupCodesScreen(codigos: codigos),
        ),
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Activar 2FA"),
        backgroundColor: const Color(0xFF013483),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.forced,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.forced)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Configuración obligatoria. Activa tu segundo factor para seguir usando la app.",
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              "1. Instala una app autenticadora",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              "Google Authenticator, Microsoft Authenticator o Authy.",
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            const Text(
              "2. Escanea el QR",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Center(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: CircularProgressIndicator(),
                      )
                    : _qrSvg != null
                        ? SvgPicture.string(_qrSvg!, width: 220, height: 220)
                        : const Text("No se generó QR"),
              ),
            ),
            const SizedBox(height: 12),
            if (_secret != null)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _secret!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Clave copiada")),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.key, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _secret!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Icon(Icons.copy, size: 16),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              "3. Ingresa el código de 6 dígitos",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: const InputDecoration(
                hintText: "000000",
                counterText: "",
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _verifying ? null : _verify,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF013483),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _verifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.shield),
                label: const Text("Activar 2FA"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
