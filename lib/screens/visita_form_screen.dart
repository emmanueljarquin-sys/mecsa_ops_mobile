import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'map_picker_screen.dart';

class VisitaFormScreen extends StatefulWidget {
  final Map<String, dynamic>? visita; // Para edición si se requiere

  const VisitaFormScreen({super.key, this.visita});

  @override
  State<VisitaFormScreen> createState() => _VisitaFormScreenState();
}

class _VisitaFormScreenState extends State<VisitaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clienteController = TextEditingController();
  final _notasController = TextEditingController();
  final _direccionController = TextEditingController();
  final _fechaController = TextEditingController();

  String? _selectedProjectId;
  String _tipoVisita = 'cliente';
  String _estado = 'programada';
  double? _lat, _lng;
  List<Map<String, dynamic>> _destinos = [];
  List<File> _fotos = [];
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    if (widget.visita != null) {
      _clienteController.text = widget.visita!['cliente'] ?? '';
      _notasController.text = widget.visita!['notas'] ?? '';
      _direccionController.text = widget.visita!['direccion'] ?? '';
      _selectedProjectId = widget.visita!['proyecto_id']?.toString();
      _tipoVisita = widget.visita!['tipo_visita'] ?? 'cliente';
      _estado = widget.visita!['estado'] ?? 'programada';
      _lat = widget.visita!['lat']?.toDouble();
      _lng = widget.visita!['lng']?.toDouble();
      _fechaController.text = widget.visita!['fecha'] ?? '';
      _destinos = List<Map<String, dynamic>>.from(
        widget.visita!['destinos'] ?? [],
      );
    } else {
      _fechaController.text = DateTime.now().toString().substring(0, 10);
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Servicio de ubicación desactivado';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw 'Permiso denegado';
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });
    } catch (e) {
      debugPrint("Location error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo obtener la ubicación: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      setState(() => _fotos.add(File(pickedFile.path)));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<AppProvider>();

    // Subir fotos primero si hay
    List<String> photoUrls = [];
    if (widget.visita != null && widget.visita!['fotos'] != null) {
      photoUrls = List<String>.from(widget.visita!['fotos']);
    }

    if (_fotos.isNotEmpty) {
      for (var foto in _fotos) {
        final url = await provider.uploadVisitaFoto(foto);
        if (url != null) photoUrls.add(url);
      }
    }

    final data = {
      'cliente': _clienteController.text,
      'proyecto_id': _selectedProjectId,
      'fecha': _fechaController.text,
      'tipo_visita': _tipoVisita,
      'estado': _estado,
      'notas': _notasController.text,
      'direccion': _direccionController.text,
      'lat': _lat,
      'lng': _lng,
      'fotos': photoUrls,
      'destinos': _destinos,
    };

    bool success;
    if (widget.visita != null) {
      success = await provider.updateVisita(
        widget.visita!['id'].toString(),
        data,
      );
    } else {
      success = await provider.createVisita(data);
    }

    if (success && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Visita registrada correctamente")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.visita == null ? "Nueva Visita" : "Editar Visita"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLocationStatus(),
              const SizedBox(height: 20),

              _buildLabel("CLIENTE / PROSPECTO"),
              TextFormField(
                controller: _clienteController,
                decoration: _inputDecoration("Nombre de la empresa o persona"),
                validator: (v) => v!.isEmpty ? "Campo requerido" : null,
              ),
              const SizedBox(height: 16),

              _buildLabel("PROYECTO (OPCIONAL)"),
              DropdownButtonFormField<String>(
                value: _selectedProjectId,
                decoration: _inputDecoration("Selecciona un proyecto"),
                items: [
                  const DropdownMenuItem(value: null, child: Text("Ninguno")),
                  ...provider.projects.map(
                    (p) => DropdownMenuItem(
                      value: p['id'].toString(),
                      child: Text(p['name'] ?? 'Proyecto'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedProjectId = v),
              ),
              const SizedBox(height: 16),

              _buildLabel("FECHA PROGRAMADA"),
              TextFormField(
                controller: _fechaController,
                readOnly: true,
                decoration: _inputDecoration("Selecciona la fecha").copyWith(
                  suffixIcon: const Icon(Icons.calendar_today, size: 20),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() {
                      _fechaController.text = date.toString().substring(0, 10);
                    });
                  }
                },
                validator: (v) => v!.isEmpty ? "Campo requerido" : null,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel("TIPO"),
                        DropdownButtonFormField<String>(
                          value: _tipoVisita,
                          items: const [
                            DropdownMenuItem(
                              value: 'cliente',
                              child: Text("Cliente"),
                            ),
                            DropdownMenuItem(
                              value: 'prospecto',
                              child: Text("Prospecto"),
                            ),
                            DropdownMenuItem(
                              value: 'seguimiento',
                              child: Text("Seguimiento"),
                            ),
                          ],
                          onChanged: (v) => setState(() => _tipoVisita = v!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel("ESTADO"),
                        DropdownButtonFormField<String>(
                          value: _estado,
                          items: const [
                            DropdownMenuItem(
                              value: 'programada',
                              child: Text("Programada"),
                            ),
                            DropdownMenuItem(
                              value: 'en_curso',
                              child: Text("En Curso"),
                            ),
                            DropdownMenuItem(
                              value: 'completada',
                              child: Text("Completada"),
                            ),
                          ],
                          onChanged: (v) => setState(() => _estado = v!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildLabel("DIRECCIÓN PRINCIPAL"),
              TextFormField(
                controller: _direccionController,
                decoration: _inputDecoration(
                  "Dirección de la parada principal",
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildLabel("PARADAS ADICIONALES"),
                  TextButton.icon(
                    onPressed: _addDestiny,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text("Añadir parada"),
                  ),
                ],
              ),
              _buildDestinosList(),
              const SizedBox(height: 24),

              _buildLabel("OBJETIVO DE LA VISITA (OPCIONAL)"),
              TextFormField(
                controller: _notasController,
                maxLines: 3,
                decoration: _inputDecoration(
                  "Escribe brevemente el motivo de la visita...",
                ),
              ),
              const SizedBox(height: 20),

              _buildLabel("FOTOS DE RESPALDO"),
              const SizedBox(height: 8),
              _buildPhotoList(),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: provider.isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: provider.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "GUARDAR VISITA",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addDestiny() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (result != null && result is Map) {
      final stop = {
        'direccion': result['address'],
        'lat': result['lat'],
        'lng': result['lng'],
        'cliente': '',
        'tipo_visita': 'cliente',
        'estado': 'programada',
        'proyecto_id': null,
      };

      if (mounted) {
        _showEditStopDialog(stop, _destinos.length);
      }
    }
  }

  void _showEditStopDialog(Map<String, dynamic> stop, int index) {
    final clientCtrl = TextEditingController(text: stop['cliente']);
    String tipo = stop['tipo_visita'] ?? 'cliente';
    String estado = stop['estado'] ?? 'programada';
    String? projId = stop['proyecto_id']?.toString();
    final provider = context.read<AppProvider>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            index >= _destinos.length ? "Configurar Parada" : "Editar Parada",
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel("CLIENTE / PROSPECTO"),
                TextFormField(
                  controller: clientCtrl,
                  decoration: _inputDecoration("Nombre"),
                ),
                const SizedBox(height: 12),
                _buildLabel("TIPO"),
                DropdownButtonFormField<String>(
                  value: tipo,
                  decoration: _inputDecoration(""),
                  items: const [
                    DropdownMenuItem(value: 'cliente', child: Text("Cliente")),
                    DropdownMenuItem(
                      value: 'prospecto',
                      child: Text("Prospecto"),
                    ),
                    DropdownMenuItem(
                      value: 'seguimiento',
                      child: Text("Seguimiento"),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => tipo = v!),
                ),
                const SizedBox(height: 12),
                _buildLabel("PROYECTO"),
                DropdownButtonFormField<String>(
                  value: projId,
                  decoration: _inputDecoration(""),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Ninguno")),
                    ...provider.projects.map(
                      (p) => DropdownMenuItem(
                        value: p['id'].toString(),
                        child: Text(p['name'] ?? 'Proyecto'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => projId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCELAR"),
            ),
            ElevatedButton(
              onPressed: () {
                String? projName;
                if (projId != null) {
                  try {
                    final p = provider.projects.firstWhere(
                      (p) => p['id'].toString() == projId,
                    );
                    projName = p['name'];
                  } catch (_) {}
                }

                setState(() {
                  stop['cliente'] = clientCtrl.text;
                  stop['tipo_visita'] = tipo;
                  stop['estado'] = estado;
                  stop['proyecto_id'] = projId;
                  stop['proyecto_nombre'] = projName;

                  if (index >= _destinos.length) {
                    _destinos.add(stop);
                  } else {
                    _destinos[index] = stop;
                  }
                });
                Navigator.pop(context);
              },
              child: const Text("GUARDAR"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinosList() {
    if (_destinos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(
          child: Text(
            "No hay paradas adicionales",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _destinos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final d = _destinos[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.blueAccent,
              child: Text(
                "${index + 2}",
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
            title: Text(
              d['cliente'].toString().isNotEmpty ? d['cliente'] : "Sin nombre",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "${d['tipo_visita']} - ${d['direccion']}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () =>
                _showEditStopDialog(Map<String, dynamic>.from(d), index),
            trailing: IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                color: Colors.red,
                size: 20,
              ),
              onPressed: () => setState(() => _destinos.removeAt(index)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocationStatus() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (_lat != null) ? Colors.green[50] : Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (_lat != null) ? Colors.green[100]! : Colors.amber[100]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _lat != null ? Icons.location_on : Icons.location_off,
            color: _lat != null ? Colors.green : Colors.amber,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lat != null
                      ? "Ubicación capturada"
                      : "Obteniendo ubicación...",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _lat != null ? Colors.green[800] : Colors.amber[800],
                  ),
                ),
                if (_lat != null)
                  Text("$_lat, $_lng", style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          if (_isGettingLocation)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (!_isGettingLocation)
            Row(
              children: [
                IconButton(
                  onPressed: _getCurrentLocation,
                  tooltip: "GPS Automático",
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                IconButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MapPickerScreen(),
                      ),
                    );
                    if (result != null && result is Map) {
                      setState(() {
                        _lat = result['lat'];
                        _lng = result['lng'];
                        _direccionController.text = result['address'];
                      });
                    }
                  },
                  tooltip: "Seleccionar en mapa",
                  icon: const Icon(
                    Icons.map_outlined,
                    size: 20,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoList() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ..._fotos.map(
          (f) => Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(f, width: 80, height: 80, fit: BoxFit.cover),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () => setState(() => _fotos.remove(f)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.blueGrey[400],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
    );
  }
}
