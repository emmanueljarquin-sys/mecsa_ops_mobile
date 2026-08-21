import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/offline_service.dart';

class VehicleRegisterScreen extends StatefulWidget {
  final Map<String, dynamic> reservation;
  final String tipo; // 'salida' or 'entrada'

  const VehicleRegisterScreen({
    super.key,
    required this.reservation,
    required this.tipo,
  });

  @override
  State<VehicleRegisterScreen> createState() => _VehicleRegisterScreenState();
}

class _VehicleRegisterScreenState extends State<VehicleRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _kilometrajeController = TextEditingController();
  final _aceiteController = TextEditingController();
  final _combustibleController = TextEditingController();

  String _estadoPintura = 'Bien';
  String _estadoLlantas = 'Bien';
  String _estadoInteriores = 'Bien';

  bool _poseeKit = false;
  bool _poseeRefraccion = false;
  bool _poseeCompass = false;

  final Map<String, XFile?> _photos = {
    'frente': null,
    'lateral_der': null,
    'lateral_izq': null,
    'trasera': null,
    'kilometraje': null,
  };

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    if (widget.tipo == 'entrada') {
      // 1. Buscar registro de salida previo
      final regSalida = (widget.reservation['registros_vehiculos'] as List?)
          ?.firstWhere((r) => r['tipo'] == 'salida', orElse: () => null);

      if (regSalida != null) {
        final kmSalida =
            double.tryParse(regSalida['kilometraje'].toString()) ?? 0.0;

        // 2. Obtener distancia rastreada por el GPS en el proveedor
        final provider = Provider.of<AppProvider>(context, listen: false);
        final kmRastreado = provider.getTripDistance(
          widget.reservation['id'].toString(),
        );

        // 3. Pre-llenar con la suma (Valor actual estimado del tablero)
        final totalEstimado = kmSalida + kmRastreado;
        if (totalEstimado > 0) {
          _kilometrajeController.text = totalEstimado.toStringAsFixed(0);
        }
      }
    }
  }

  Future<void> _takePhoto(String key) async {
    // Deja elegir entre cámara y galería. La galería permite que el personal
    // que no logró marcar en el momento adjunte fotos que ya tiene tomadas.
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? photo = await _picker.pickImage(
      source: source,
      imageQuality: 70,
    );
    if (photo != null) {
      setState(() {
        _photos[key] = photo;
      });
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate photos
    for (var p in _photos.values) {
      if (p == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Por favor toma todas las 5 fotos requeridas."),
          ),
        );
        return;
      }
    }

    final provider = Provider.of<AppProvider>(context, listen: false);

    // Prepare photo map for upload (converting XFile to File or just passing path)
    final Map<String, dynamic> localPhotos = {};
    _photos.forEach((key, value) {
      if (value != null) localPhotos[key] = File(value.path);
    });

    // ── SIN CONEXIÓN: guardar en la cola y subir cuando vuelva el internet ──
    if (!await OfflineService.instance.hayConexion()) {
      await _encolarParaSubir('Guardado sin conexión. Se subirá solo cuando haya internet.');
      return;
    }

    try {
      final success = await provider.saveVehicleRegister(
        reservaId: widget.reservation['id'].toString(),
        tipo: widget.tipo,
        kilometraje: double.parse(_kilometrajeController.text),
        nivelAceite: double.tryParse(_aceiteController.text) ?? 100.0,
        nivelCombustible: double.tryParse(_combustibleController.text) ?? 100.0,
        estadoPintura: _estadoPintura,
        estadoLlantas: _estadoLlantas,
        estadoInteriores: _estadoInteriores,
        poseeKit: _poseeKit,
        poseeRefraccion: _poseeRefraccion,
        poseeCompass: _poseeCompass,
        localPhotos: localPhotos,
      );

      if (success && mounted) {
        // --- AUTOMATIZACIÓN DE RASTREO ---
        // Detener rastreo si el registro fue de entrada (devolución)
        if (widget.tipo == 'entrada') {
          provider.clearTripDistance(widget.reservation['id'].toString());
          provider.trackingService.stopTracking();
        }

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Registro guardado con éxito")),
        );
      } else if (!success && mounted) {
        // La subida en vivo no completó (señal débil) → encolar y subir solo.
        await _encolarParaSubir('No se pudo subir ahora (señal débil). Se subirá automáticamente cuando haya buena señal.');
      }
    } catch (e) {
      if (!mounted) return;
      try {
        await _encolarParaSubir('No se pudo subir ahora (señal débil). Se subirá automáticamente cuando haya buena señal.');
      } catch (_) {
        if (mounted) _ofrecerRegistroManual(localPhotos);
      }
    }
  }

  // Encola el registro (con sus fotos) para subirlo automáticamente cuando haya
  // conexión. Se usa sin conexión y cuando la subida en vivo falla (señal débil).
  Future<void> _encolarParaSubir(String mensaje) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    await OfflineService.instance.enqueue(
      type: 'registro_vehiculo',
      record: {
        'reserva_id': widget.reservation['id'].toString(),
        'empleado_id': provider.currentEmployeeId,
        'tipo': widget.tipo,
        'kilometraje': double.tryParse(_kilometrajeController.text),
        'nivel_aceite': double.tryParse(_aceiteController.text) ?? 100.0,
        'nivel_combustible': double.tryParse(_combustibleController.text) ?? 100.0,
        'estado_pintura': _estadoPintura,
        'estado_llantas': _estadoLlantas,
        'estado_interiores': _estadoInteriores,
        'posee_kit': _poseeKit,
        'posee_refraccion': _poseeRefraccion,
        'posee_compass': _poseeCompass,
        'ubicacion': '',
      },
      photos: {
        for (final e in _photos.entries)
          if (e.value != null) e.key: e.value!.path,
      },
    );
    if (mounted) {
      if (widget.tipo == 'entrada') {
        provider.clearTripDistance(widget.reservation['id'].toString());
        provider.trackingService.stopTracking();
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  // Respaldo: si el registro normal falla/se cuelga, envía comentario + fotos
  // como registro MANUAL, que un admin aprueba en la web.
  Future<void> _ofrecerRegistroManual(Map<String, dynamic> localPhotos) async {
    final comentarioCtrl = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se pudo registrar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Podés enviar un registro manual con tus observaciones y tus fotos '
              '(podés elegirlas de la galería). Un administrador lo revisará y '
              'aprobará en la web.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: comentarioCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                hintText: 'Qué pasó / detalle…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar para aprobación')),
        ],
      ),
    );
    if (enviar != true || !mounted) return;

    final provider = Provider.of<AppProvider>(context, listen: false);
    final ok = await provider.saveVehicleRegisterManual(
      reservaId: widget.reservation['id'].toString(),
      tipo: widget.tipo,
      comentario: comentarioCtrl.text.trim().isEmpty
          ? 'Registro manual (falló el registro automático)'
          : comentarioCtrl.text.trim(),
      localPhotos: localPhotos,
      kilometraje: double.tryParse(_kilometrajeController.text),
    );
    if (!mounted) return;
    if (ok) {
      if (widget.tipo == 'entrada') {
        provider.clearTripDistance(widget.reservation['id'].toString());
        provider.trackingService.stopTracking();
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registro enviado para aprobación'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo enviar el registro manual. Revisá tu conexión.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.tipo == 'salida'
        ? 'Registro de Salida'
        : 'Registro de Entrada';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(title),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildSectionTitle("DATOS DEL VEHÍCULO"),
                    const SizedBox(height: 12),
                    _buildMotorData(),

                    if (widget.tipo == 'entrada') _buildKMCalculationDisplay(),

                    if (widget.tipo == 'salida') ...[
                      const SizedBox(height: 24),
                      _buildSectionTitle("ESTADO FÍSICO"),
                      _buildPhysicalStatus(),

                      const SizedBox(height: 24),
                      _buildSectionTitle("EQUIPAMIENTO"),
                      _buildEquipment(),
                    ],

                    const SizedBox(height: 24),
                    _buildSectionTitle("REGISTRO FOTOGRÁFICO"),
                    _buildPhotoSection(),

                    const SizedBox(height: 40),
                    _buildSubmitButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1B263B),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Vehículo: ${widget.reservation['vehiculos']?['marca'] ?? ''} ${widget.reservation['vehiculos']?['modelo'] ?? ''}",
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 4, height: 20, color: const Color(0xFF0D6EFD)),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1.2,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMotorData() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildNumberField(
              _kilometrajeController,
              "Kilometraje Total (Tablero)",
              Icons.speed,
              "km",
              enabled: true,
              onChanged: (v) {
                if (mounted) setState(() {});
              },
            ),
            if (widget.tipo == 'salida') ...[
              const Divider(height: 30),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberField(
                      _aceiteController,
                      "Aceite %",
                      Icons.oil_barrel,
                      "%",
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildNumberField(
                      _combustibleController,
                      "Combustible %",
                      Icons.local_gas_station,
                      "%",
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKMCalculationDisplay() {
    // Buscar registro de salida previo
    final regSalida = (widget.reservation['registros_vehiculos'] as List?)
        ?.firstWhere((r) => r['tipo'] == 'salida', orElse: () => null);

    if (regSalida == null) return const SizedBox.shrink();

    final kmSalida =
        double.tryParse(regSalida['kilometraje'].toString()) ?? 0.0;
    final kmEntrada = double.tryParse(_kilometrajeController.text) ?? 0.0;
    final recorrido = kmEntrada - kmSalida;

    if (kmEntrada <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: recorrido < 0 ? Colors.red.shade50 : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: recorrido < 0 ? Colors.red.shade200 : Colors.blue.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              recorrido < 0 ? Icons.warning : Icons.info_outline,
              color: recorrido < 0 ? Colors.red : Colors.blue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                recorrido < 0
                    ? "Error: Kilometraje menor al de salida ($kmSalida km)"
                    : "Recorrido calculado: ${recorrido.toStringAsFixed(1)} KM",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: recorrido < 0 ? Colors.red : Colors.blue.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberField(
    TextEditingController controller,
    String label,
    IconData icon,
    String suffix, {
    void Function(String)? onChanged,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF0D6EFD)),
        suffixText: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: !enabled,
        fillColor: !enabled ? Colors.grey.shade100 : null,
      ),
      validator: (v) => (v == null || v.isEmpty) ? "Requerido" : null,
    );
  }

  Widget _buildPhysicalStatus() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            _buildDropdown(
              "Pintura",
              _estadoPintura,
              (val) => setState(() => _estadoPintura = val!),
            ),
            _buildDropdown(
              "Llantas",
              _estadoLlantas,
              (val) => setState(() => _estadoLlantas = val!),
            ),
            _buildDropdown(
              "Interiores",
              _estadoInteriores,
              (val) => setState(() => _estadoInteriores = val!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    void Function(String?) onChanged,
  ) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: DropdownButton<String>(
        value: value,
        onChanged: onChanged,
        items: [
          'Bien',
          'Regular',
          'Mal',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      ),
    );
  }

  Widget _buildEquipment() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          CheckboxListTile(
            title: const Text(
              "Kit de emergencia",
              style: TextStyle(fontSize: 14),
            ),
            value: _poseeKit,
            onChanged: (v) => setState(() => _poseeKit = v!),
          ),
          CheckboxListTile(
            title: const Text(
              "Refracción (Llanta repuesto)",
              style: TextStyle(fontSize: 14),
            ),
            value: _poseeRefraccion,
            onChanged: (v) => setState(() => _poseeRefraccion = v!),
          ),
          CheckboxListTile(
            title: const Text("Posee Compass", style: TextStyle(fontSize: 14)),
            value: _poseeCompass,
            onChanged: (v) => setState(() => _poseeCompass = v!),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      children: [
        _buildPhotoItem("frente", "Frente del vehículo"),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildPhotoItem("lateral_der", "Laterial Der.")),
            const SizedBox(width: 12),
            Expanded(child: _buildPhotoItem("lateral_izq", "Lateral Izq.")),
          ],
        ),
        const SizedBox(height: 12),
        _buildPhotoItem("trasera", "Detrás del vehículo"),
        const SizedBox(height: 12),
        _buildPhotoItem("kilometraje", "Foto del Kilometraje"),
      ],
    );
  }

  Widget _buildPhotoItem(String key, String label) {
    final photo = _photos[key];
    return GestureDetector(
      onTap: () => _takePhoto(key),
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: photo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(photo.path), fit: BoxFit.cover),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt, color: Colors.blue, size: 30),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    final provider = Provider.of<AppProvider>(context);
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: provider.isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D6EFD),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: provider.isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                "GUARDAR REGISTRO",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
      ),
    );
  }
}
