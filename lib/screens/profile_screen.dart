import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Actualizando foto de perfil...')),
          );
        }
        await provider.updateProfilePhoto(File(image.path));
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _showPickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galería'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(context, ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Cámara'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(context, ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final emp = provider.currentEmployeeData; // Datos reales
    final user = provider.user;

    // Construir nombre completo
    String fullName = "Usuario";
    if (emp != null) {
      final n = emp['nombre'] ?? '';
      final a = emp['apellido'] ?? '';
      if (n.isNotEmpty || a.isNotEmpty) {
        fullName = "$n $a".trim();
      } else if (emp['nombre_completo'] != null) {
        fullName = emp['nombre_completo'];
      }
    } else if (user?.email != null) {
      fullName = user!.email!.split('@')[0];
    }

    // Avatar
    final String? photoUrl = emp?['photo'];
    final bool hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () => provider.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  GestureDetector(
                    onTap: () => _showPickerOptions(context),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: hasPhoto
                          ? NetworkImage(photoUrl!)
                          : const NetworkImage(
                              'https://i.pravatar.cc/150?img=11',
                            ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showPickerOptions(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              fullName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              emp?['email'] ?? user?.email ?? '',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            if (emp?['departamento'] != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Text(
                  emp!['departamento'],
                  style: TextStyle(
                    color: Colors.blue[800],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            const SizedBox(height: 32),

            _ProfileItem(
              icon: Icons.badge_outlined,
              title: "Código / ID",
              value: emp?['codigo_empleado'] ?? emp?['id']?.toString() ?? "N/A",
            ),
            const Divider(),
            _ProfileItem(
              icon: Icons.apartment_outlined,
              title: "Departamento",
              value: emp?['departamento'] ?? "Sin asignar",
            ),
            const Divider(),
            _ProfileItem(
              icon: Icons.phone_outlined,
              title: "Teléfono",
              value: emp?['telefono'] ?? "No registrado",
            ),
            const Divider(),
            const _ProfileItem(
              icon: Icons.info_outline,
              title: "Versión App",
              value: "1.0.0 (Beta)",
            ),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => provider.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text("Cerrar Sesión"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _ProfileItem({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50], // Light blue
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blue[900], size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
