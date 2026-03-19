import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'map_picker_screen.dart';

class ReservationFormScreen extends StatefulWidget {
  final Map<String, dynamic>? vehicle;

  const ReservationFormScreen({super.key, this.vehicle});

  @override
  State<ReservationFormScreen> createState() => _ReservationFormScreenState();
}

class _ReservationFormScreenState extends State<ReservationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _motivoController = TextEditingController();
  final _projectController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _personalController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedprojectId;
  String? _selectedVehicleId;
  List<Map<String, dynamic>> _selectedEmployees = [];

  @override
  void initState() {
    super.initState();
    if (widget.vehicle != null) {
      _selectedVehicleId = widget.vehicle!['id'].toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final projects = provider.projects;
    final vehiculos = provider.vehiculos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Reserva'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vehicle Selector or Info Card
              if (widget.vehicle != null) ...[
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.directions_car,
                      color: AppTheme.primaryColor,
                      size: 32,
                    ),
                    title: Text(
                      widget.vehicle!['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(widget.vehicle!['plate']),
                  ),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: "Seleccionar Vehículo",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.directions_car),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  items: vehiculos
                      .where((v) => v['status'] == 'available') // SOLAMENTE disponibles
                      .map((v) {
                    return DropdownMenuItem<String>(
                      value: v['id'].toString(),
                      child: Text(
                        "${v['name']} - ${v['plate']}",
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedVehicleId = val),
                  validator: (value) =>
                      value == null ? 'Seleccione un vehículo' : null,
                ),
              ],

              const SizedBox(height: 24),
              const Text(
                "Fechas",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: _buildDateTimePicker(
                      context,
                      label: "Salida",
                      selectedDate: _startDate,
                      onSelect: (date) => setState(() => _startDate = date),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDateTimePicker(
                      context,
                      label: "Regreso",
                      selectedDate: _endDate,
                      onSelect: (date) => setState(() => _endDate = date),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Text(
                "Detalles",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              // Motivo
              TextFormField(
                controller: _motivoController,
                decoration: InputDecoration(
                  labelText: "Motivo del viaje",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                maxLines: 2,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),

              const SizedBox(height: 16),

              // Proyecto (Searchable Interface)
              TextFormField(
                controller: _projectController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: "Proyecto (Opcional)",
                  hintText: "Toque para buscar...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                onTap: () {
                  _showProjectSearch(context, projects);
                },
              ),

              const SizedBox(height: 16),

              // Ubicación
              TextFormField(
                controller: _ubicacionController,
                readOnly: true,
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MapPickerScreen()),
                  );
                  if (result != null && result is Map) {
                    setState(() {
                      // Guardamos formato híbrido: LAT,LNG|ADDRESS
                      final lat = result['lat'];
                      final lng = result['lng'];
                      final addr = result['address'];
                      _ubicacionController.text = "$lat,$lng|$addr";
                    });
                  }
                },
                decoration: InputDecoration(
                  labelText: "Ubicación / Destino (Google Maps)",
                  hintText: "Toque para seleccionar en el mapa...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.map, color: Colors.blue),
                  suffixIcon: _ubicacionController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() {
                              _ubicacionController.clear();
                            });
                          },
                        )
                      : const Icon(
                          Icons.touch_app,
                          size: 20,
                          color: Colors.grey,
                        ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              if (_ubicacionController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Ubicación cargada: ${_ubicacionController.text.contains('|') ? _ubicacionController.text.split('|')[1] : _ubicacionController.text}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Personal Incluido
              TextFormField(
                controller: _personalController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: "Personal Incluido",
                  hintText: "Toque para seleccionar personal...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: const Icon(
                    Icons.people_outline,
                    color: Colors.orange,
                  ),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                onTap: () {
                  _showEmployeeSelection(context, provider.employees);
                },
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: provider.isLoading
                      ? null
                      : () => _submit(provider),
                  child: provider.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Confirmar Reserva",
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProjectSearch(
    BuildContext context,
    List<Map<String, dynamic>> projects,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return _ProjectSearchModal(
              projects: projects,
              scrollController: scrollController,
              onSelect: (id, name) {
                setState(() {
                  _selectedprojectId = id;
                  _projectController.text = name;
                });
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  void _showEmployeeSelection(
    BuildContext context,
    List<Map<String, dynamic>> employees,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return _EmployeeMultiSelectModal(
              employees: employees,
              initialSelection: _selectedEmployees,
              scrollController: scrollController,
              onConfirm: (List<Map<String, dynamic>> selected) {
                setState(() {
                  _selectedEmployees = selected;
                  _personalController.text = selected
                      .map((e) => e['nombre_completo'])
                      .join(', ');
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDateTimePicker(
    BuildContext context, {
    required String label,
    DateTime? selectedDate,
    required Function(DateTime) onSelect,
  }) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        // 1. Pick Date
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? now,
          firstDate: now,
          lastDate: now.add(const Duration(days: 365)),
        );

        if (pickedDate == null) return;

        if (!context.mounted) return;

        // 2. Pick Time
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(selectedDate ?? now),
        );

        if (pickedTime == null) return;

        // 3. Combine
        final finalDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        onSelect(finalDateTime);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[50],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  selectedDate != null
                      ? DateFormat('dd/MM/yyyy').format(selectedDate)
                      : 'Fecha',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selectedDate != null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  selectedDate != null
                      ? DateFormat('HH:mm').format(selectedDate)
                      : 'Hora',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selectedDate != null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit(AppProvider provider) async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Seleccione fechas")));
      return;
    }

    if (_selectedVehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: Ningún vehículo seleccionado")),
      );
      return;
    }

    final success = await provider.createReservation({
      'vehiculo_id': _selectedVehicleId,
      'fecha_salida': _startDate!.toIso8601String(),
      'fecha_regreso': _endDate!.toIso8601String(),
      'motivo': _motivoController.text,
      'proyecto_id': _selectedprojectId,
      'ubicacion': _ubicacionController.text,
      'personal_incluido': _personalController.text,
      'estado': 'Pendiente',
    });

    if (success && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reserva creada exitosamente")),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.errorMessage ?? "Error")));
    }
  }
}

class _ProjectSearchModal extends StatefulWidget {
  final List<Map<String, dynamic>> projects;
  final ScrollController scrollController;
  final Function(String, String) onSelect;

  const _ProjectSearchModal({
    required this.projects,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  State<_ProjectSearchModal> createState() => _ProjectSearchModalState();
}

class _ProjectSearchModalState extends State<_ProjectSearchModal> {
  List<Map<String, dynamic>> _filteredProjects = [];

  @override
  void initState() {
    super.initState();
    _filteredProjects = widget.projects;
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProjects = widget.projects;
      } else {
        _filteredProjects = widget.projects.where((p) {
          final name = (p['name'] ?? '').toString().toLowerCase();
          final id = (p['id'] ?? '').toString().toLowerCase();
          final q = query.toLowerCase();
          return name.contains(q) || id.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            onChanged: _filter,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: "Buscar proyecto...",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: Colors.grey[100],
            ),
          ),
        ),
        // List
        Expanded(
          child: ListView.separated(
            controller: widget.scrollController,
            itemCount: _filteredProjects.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = _filteredProjects[index];
              final id = p['id']?.toString() ?? '';
              final name = p['name'] ?? 'Sin Título';
              return ListTile(
                title: Text(
                  "$id - $name",
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () => widget.onSelect(id, name),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmployeeMultiSelectModal extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> initialSelection;
  final ScrollController scrollController;
  final Function(List<Map<String, dynamic>>) onConfirm;

  const _EmployeeMultiSelectModal({
    required this.employees,
    required this.initialSelection,
    required this.scrollController,
    required this.onConfirm,
  });

  @override
  State<_EmployeeMultiSelectModal> createState() =>
      _EmployeeMultiSelectModalState();
}

class _EmployeeMultiSelectModalState extends State<_EmployeeMultiSelectModal> {
  List<Map<String, dynamic>> _filteredEmployees = [];
  List<Map<String, dynamic>> _selectedEmployees = [];

  @override
  void initState() {
    super.initState();
    _filteredEmployees = widget.employees;
    _selectedEmployees = List.from(widget.initialSelection);
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredEmployees = widget.employees;
      } else {
        _filteredEmployees = widget.employees.where((e) {
          final name = (e['nombre_completo'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with Confirm button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar"),
              ),
              const Text(
                "Seleccionar Personal",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              ElevatedButton(
                onPressed: () {
                  widget.onConfirm(_selectedEmployees);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text("Confirmar"),
              ),
            ],
          ),
        ),
        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            onChanged: _filter,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: "Buscar empleado...",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: Colors.grey[100],
            ),
          ),
        ),
        // Selected counter
        if (_selectedEmployees.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Text(
                  "${_selectedEmployees.length} seleccionados",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selectedEmployees.clear()),
                  child: const Text("Limpiar todo"),
                ),
              ],
            ),
          ),
        const Divider(),
        // List
        Expanded(
          child: ListView.separated(
            controller: widget.scrollController,
            itemCount: _filteredEmployees.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final e = _filteredEmployees[index];
              final isSelected = _selectedEmployees.any(
                (sel) => sel['id'] == e['id'],
              );

              return CheckboxListTile(
                title: Text(
                  e['nombre_completo'] ?? 'Sin Nombre',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                value: isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedEmployees.add(e);
                    } else {
                      _selectedEmployees.removeWhere(
                        (sel) => sel['id'] == e['id'],
                      );
                    }
                  });
                },
                activeColor: AppTheme.primaryColor,
              );
            },
          ),
        ),
      ],
    );
  }
}
