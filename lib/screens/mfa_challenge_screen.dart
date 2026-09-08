import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/mfa_service.dart';
import 'home_screen.dart';

/// Tras login con password, pide el código TOTP (o backup) para completar AAL2.
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  late final MfaService _mfa = MfaService(Supabase.instance.client);
  final _code = TextEditingController();
  final _backup = TextEditingController();
  bool _useBackup = false;
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _backup.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      if (_useBackup) {
        final c = _backup.text.trim().toUpperCase();
        if (!RegExp(r'^[A-F0-9]{4}-[A-F0-9]{4}$').hasMatch(c)) {
          throw "Formato: XXXX-XXXX";
        }
        await _mfa.backupCodeVerify(backupCode: c);
      } else {
        final c = _code.text.trim();
        if (!RegExp(r'^\d{6}$').hasMatch(c)) {
          throw "6 dígitos";
        }
        await _mfa.challengeVerify(code: c);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
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
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF013483).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.security,
                          color: Color(0xFF013483), size: 28),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Verificación en dos pasos",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF013483)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _useBackup
                          ? "Ingresa un código de respaldo"
                          : "Ingresa el código de tu app autenticadora",
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(email,
                        style: const TextStyle(
                            color: Colors.black38, fontSize: 11)),
                    const SizedBox(height: 20),
                    if (_useBackup)
                      TextField(
                        controller: _backup,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            letterSpacing: 4),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: "XXXX-XXXX",
                          border: OutlineInputBorder(),
                        ),
                      )
                    else
                      TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 10),
                        decoration: const InputDecoration(
                          hintText: "000000",
                          counterText: "",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
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
                            : const Icon(Icons.check),
                        label: const Text("Verificar"),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() {
                        _useBackup = !_useBackup;
                        _error = null;
                      }),
                      child: Text(
                        _useBackup
                            ? "Volver al código TOTP"
                            : "¿Perdiste tu dispositivo? Usar código de respaldo",
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Supabase.instance.client.auth.signOut();
                        if (!mounted) return;
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        "Cerrar sesión",
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
