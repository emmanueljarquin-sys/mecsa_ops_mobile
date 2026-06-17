import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';

/// Muestra los 8 backup codes UNA SOLA vez al usuario tras enroll.
class MfaBackupCodesScreen extends StatefulWidget {
  const MfaBackupCodesScreen({super.key, required this.codigos});
  final List<String> codigos;

  @override
  State<MfaBackupCodesScreen> createState() => _MfaBackupCodesScreenState();
}

class _MfaBackupCodesScreenState extends State<MfaBackupCodesScreen> {
  bool _confirmado = false;

  void _copiar() {
    Clipboard.setData(ClipboardData(text: widget.codigos.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Códigos copiados al portapapeles")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => _confirmado,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text("Códigos de respaldo"),
          backgroundColor: const Color(0xFF013483),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle,
                      color: Colors.green.shade600, size: 36),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "2FA activado correctamente",
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber,
                        color: Colors.orange, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Guarda estos códigos AHORA.\nTe servirán si pierdes tu dispositivo. Solo los verás esta vez.",
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 3,
                ),
                itemCount: widget.codigos.length,
                itemBuilder: (_, i) => Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    widget.codigos[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _copiar,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF013483),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text("Copiar todos"),
                ),
              ),
              const Divider(height: 32),
              CheckboxListTile(
                value: _confirmado,
                onChanged: (v) => setState(() => _confirmado = v ?? false),
                title: const Text(
                  "Confirmo que guardé estos códigos en un lugar seguro",
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _confirmado
                      ? () => Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) => const HomeScreen()),
                            (_) => false,
                          )
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF013483),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text("Continuar al panel"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
