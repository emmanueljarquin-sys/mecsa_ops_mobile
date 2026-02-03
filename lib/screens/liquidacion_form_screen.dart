import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/liquidacion.dart';
import '../services/liquidaciones_service.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class LiquidacionFormScreen extends StatefulWidget {
  final Liquidacion? liquidacion;

  const LiquidacionFormScreen({super.key, this.liquidacion});

  @override
  State<LiquidacionFormScreen> createState() => _LiquidacionFormScreenState();
}

class _LiquidacionFormScreenState extends State<LiquidacionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tarjetaController = TextEditingController();
  final _personalController = TextEditingController();

  String? _selectedEmpleadoId;
  int? _selectedProyectoId;
  DateTime _selectedDate = DateTime.now();
  String _selectedTipo = 'VIATICOS';
  List<Factura> _facturas = [];
  bool _isSaving = false;
  bool _isLoadingData = true;

  List<Empleado> _empleados = [];
  List<Proyecto> _proyectos = [];
  List<Proyecto> _filteredProyectos = [];
  List<Empleado> _filteredEmpleados = [];
  List<Empleado> _selectedPersonal = [];

  String get _selectedProyectoLabel {
    if (_selectedProyectoId == null) return 'Seleccione un proyecto';
    try {
      final p = _proyectos.firstWhere((p) => p.id == _selectedProyectoId);
      return '[#${p.id}] ${p.nombre}';
    } catch (_) {
      return 'Proyecto #${_selectedProyectoId}';
    }
  }

  String get _selectedEmpleadoLabel {
    if (_selectedEmpleadoId == null) return 'Seleccione un empleado';
    try {
      final e = _empleados.firstWhere((e) => e.id == _selectedEmpleadoId);
      return e.nombreCompleto;
    } catch (_) {
      return 'Empleado #${_selectedEmpleadoId}';
    }
  }

  void _showEmpleadoSearch() {
    _filteredEmpleados = List.from(_empleados);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Seleccionar Empleado',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o ID...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        final query = val.toLowerCase();
                        _filteredEmpleados = _empleados.where((e) {
                          return e.nombreCompleto.toLowerCase().contains(
                                query,
                              ) ||
                              e.id.toString().toLowerCase().contains(query);
                        }).toList();
                      });
                    },
                  ),
                ),
                Expanded(
                  child: _filteredEmpleados.isEmpty
                      ? const Center(child: Text('No se encontraron empleados'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _filteredEmpleados.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final e = _filteredEmpleados[index];
                            final isSelected = _selectedEmpleadoId == e.id;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              title: Text(
                                e.nombreCompleto,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Theme.of(context).primaryColor
                                      : Colors.black87,
                                ),
                              ),
                              subtitle: e.departamento != null
                                  ? Text(e.departamento!)
                                  : null,
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF28A745),
                                    )
                                  : const Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                              onTap: () {
                                setState(() {
                                  _selectedEmpleadoId = e.id;
                                });
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showProyectoSearch() {
    _filteredProyectos = List.from(_proyectos);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Seleccionar Proyecto',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o ID...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        final query = val.toLowerCase();
                        _filteredProyectos = _proyectos.where((p) {
                          return p.nombre.toLowerCase().contains(query) ||
                              p.id.toString().contains(query);
                        }).toList();
                      });
                    },
                  ),
                ),
                Expanded(
                  child: _filteredProyectos.isEmpty
                      ? const Center(child: Text('No se encontraron proyectos'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _filteredProyectos.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final p = _filteredProyectos[index];
                            final isSelected = _selectedProyectoId == p.id;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '#${p.id}',
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                p.nombre,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Theme.of(context).primaryColor
                                      : Colors.black87,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF28A745),
                                    )
                                  : const Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                              onTap: () {
                                setState(() {
                                  _selectedProyectoId = p.id;
                                });
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPersonalMultiSelect() {
    String localQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final filtered = _empleados.where((e) {
            return e.nombreCompleto.toLowerCase().contains(
              localQuery.toLowerCase(),
            );
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                _buildModalHeader('Seleccionar Personal'),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar empleado...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (val) => setModalState(() => localQuery = val),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = filtered[index];
                      final isSelected = _selectedPersonal.any(
                        (p) => p.id == e.id,
                      );
                      return CheckboxListTile(
                        title: Text(e.nombreCompleto),
                        subtitle: Text(e.departamento ?? ''),
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedPersonal.add(e);
                            } else {
                              _selectedPersonal.removeWhere(
                                (p) => p.id == e.id,
                              );
                            }
                          });
                          setModalState(() {});
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirmar Selección',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildModalHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        LiquidacionesService.getEmpleados(),
        LiquidacionesService.getProyectos(),
      ]);

      setState(() {
        _empleados = results[0] as List<Empleado>;
        _proyectos = results[1] as List<Proyecto>;

        if (widget.liquidacion != null) {
          _selectedEmpleadoId = widget.liquidacion!.empleadoId;
          _selectedProyectoId = widget.liquidacion!.proyectoId;
          _tarjetaController.text = widget.liquidacion!.tarjetaUlt4 ?? '';
          _personalController.text = widget.liquidacion!.personalIncluido ?? '';
          _selectedDate = widget.liquidacion!.fecha;
          _selectedTipo = widget.liquidacion!.tipo;
          _facturas = widget.liquidacion!.facturas ?? [];

          if (widget.liquidacion!.personalIncluido != null) {
            final names = widget.liquidacion!.personalIncluido!
                .split(',')
                .map((n) => n.trim());
            _selectedPersonal = _empleados
                .where((e) => names.contains(e.nombreCompleto))
                .toList();
          }
        } else {
          // Nueva liquidación: Auto-seleccionar usuario actual
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          _selectedEmpleadoId = appProvider.currentEmployeeId;
        }

        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
    }
  }

  @override
  void dispose() {
    _tarjetaController.dispose();
    _personalController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _addFactura() {
    showDialog(
      context: context,
      builder: (context) => _FacturaDialog(
        onSave: (factura) {
          setState(() {
            _facturas.add(factura);
          });
        },
      ),
    );
  }

  void _removeFactura(int index) {
    setState(() {
      _facturas.removeAt(index);
    });
  }

  double _calculateTotal() {
    return _facturas.fold(0.0, (sum, factura) => sum + factura.monto);
  }

  Future<void> _saveLiquidacion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_facturas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe agregar al menos una factura')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final liquidacion = Liquidacion(
        id: widget.liquidacion?.id ?? '',
        empleadoId: _selectedEmpleadoId!,
        fecha: _selectedDate,
        tarjetaUlt4: _tarjetaController.text.isEmpty
            ? null
            : _tarjetaController.text,
        proyectoId: _selectedProyectoId!,
        tipo: _selectedTipo,
        personalIncluido: _selectedPersonal.isEmpty
            ? null
            : _selectedPersonal.map((e) => e.nombreCompleto).join(', '),
        estado: 'pendiente',
        total: _calculateTotal(),
        createdAt: DateTime.now(),
      );

      Liquidacion savedLiquidacion;
      if (widget.liquidacion == null) {
        savedLiquidacion = await LiquidacionesService.createLiquidacion(
          liquidacion,
        );
      } else {
        savedLiquidacion = await LiquidacionesService.updateLiquidacion(
          widget.liquidacion!.id,
          liquidacion,
        );
      }

      // Guardar facturas
      for (final factura in _facturas) {
        if (factura.id == null) {
          final nuevaFactura = Factura(
            liquidacionId: savedLiquidacion.id,
            proveedor: factura.proveedor,
            numeroFactura: factura.numeroFactura,
            tipo: factura.tipo,
            monto: factura.monto,
            fecha: factura.fecha,
            documento: factura.documento,
          );
          await LiquidacionesService.createFactura(nuevaFactura);
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.liquidacion == null
                  ? 'Liquidación creada exitosamente'
                  : 'Liquidación actualizada exitosamente',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.liquidacion == null
              ? 'Nueva Liquidación'
              : 'Editar Liquidación',
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Información General
                    _SectionCard(
                      title: 'Información General',
                      child: Column(
                        children: [
                          InkWell(
                            onTap: widget.liquidacion == null
                                ? null
                                : _showEmpleadoSearch,
                            child: FormField<String>(
                              initialValue: _selectedEmpleadoId,
                              validator: (val) => _selectedEmpleadoId == null
                                  ? 'Seleccione un empleado'
                                  : null,
                              builder: (state) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Empleado *',
                                        border: const OutlineInputBorder(),
                                        filled: widget.liquidacion == null,
                                        fillColor: Colors.grey[200],
                                        errorText: state.errorText,
                                        suffixIcon: widget.liquidacion == null
                                            ? null
                                            : const Icon(Icons.arrow_drop_down),
                                      ),
                                      child: Text(
                                        _selectedEmpleadoLabel,
                                        style: TextStyle(
                                          color: _selectedEmpleadoId == null
                                              ? Colors.grey[600]
                                              : Colors.black,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _showProyectoSearch,
                            child: FormField<int>(
                              initialValue: _selectedProyectoId,
                              validator: (val) => _selectedProyectoId == null
                                  ? 'Seleccione un proyecto'
                                  : null,
                              builder: (state) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Proyecto *',
                                        border: const OutlineInputBorder(),
                                        errorText: state.errorText,
                                        suffixIcon: const Icon(
                                          Icons.arrow_drop_down,
                                        ),
                                      ),
                                      child: Text(
                                        _selectedProyectoLabel,
                                        style: TextStyle(
                                          color: _selectedProyectoId == null
                                              ? Colors.grey[600]
                                              : Colors.black,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _selectDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Fecha *',
                                border: OutlineInputBorder(),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                  ),
                                  const Icon(Icons.calendar_today),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _tarjetaController,
                            decoration: const InputDecoration(
                              labelText: 'Tarjeta (últimos 4 dígitos)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedTipo,
                            decoration: const InputDecoration(
                              labelText: 'Tipo',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'VIATICOS',
                                child: Text('Viáticos'),
                              ),
                              DropdownMenuItem(
                                value: 'COMBUSTIBLE',
                                child: Text('Combustible'),
                              ),
                              DropdownMenuItem(
                                value: 'OTROS',
                                child: Text('Otros'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedTipo = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _showPersonalMultiSelect,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Personal Incluido',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(
                                  Icons.people_outline,
                                  color: Colors.orange,
                                ),
                                suffixIcon: Icon(Icons.arrow_drop_down),
                              ),
                              child: Text(
                                _selectedPersonal.isEmpty
                                    ? 'Toque para seleccionar personal...'
                                    : _selectedPersonal
                                          .map((e) => e.nombreCompleto)
                                          .join(', '),
                                style: TextStyle(
                                  color: _selectedPersonal.isEmpty
                                      ? Colors.grey[600]
                                      : Colors.black,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Facturas
                    _SectionCard(
                      title: 'Facturas (${_facturas.length})',
                      child: Column(
                        children: [
                          if (_facturas.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  'No hay facturas agregadas',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          else
                            ..._facturas.asMap().entries.map((entry) {
                              final index = entry.key;
                              final factura = entry.value;
                              return _FacturaListItem(
                                factura: factura,
                                onDelete: () => _removeFactura(index),
                              );
                            }).toList(),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _addFactura,
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar Factura'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Total
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₡${_calculateTotal().toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Botones
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveLiquidacion,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF28A745),
                              foregroundColor: Colors.white,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _FacturaListItem extends StatelessWidget {
  final Factura factura;
  final VoidCallback onDelete;

  const _FacturaListItem({required this.factura, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (factura.documento != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.attach_file,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Documento adjunto',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  factura.tipoLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Text(factura.proveedor),
                Text(
                  '₡${factura.monto.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _FacturaDialog extends StatefulWidget {
  final Function(Factura) onSave;

  const _FacturaDialog({required this.onSave});

  @override
  State<_FacturaDialog> createState() => _FacturaDialogState();
}

class _FacturaDialogState extends State<_FacturaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _proveedorController = TextEditingController();
  final _numeroController = TextEditingController();
  final _montoController = TextEditingController();
  String _selectedTipo = 'D';
  DateTime _selectedDate = DateTime.now();
  String? _localImagePath;
  bool _isUploading = false;

  @override
  void dispose() {
    _proveedorController.dispose();
    _numeroController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar Factura'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedTipo,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: const [
                    DropdownMenuItem(value: 'D', child: Text('Desayuno')),
                    DropdownMenuItem(value: 'A', child: Text('Almuerzo')),
                    DropdownMenuItem(value: 'C', child: Text('Cena')),
                    DropdownMenuItem(value: 'H', child: Text('Hospedaje')),
                    DropdownMenuItem(
                      value: 'COMBUSTIBLE',
                      child: Text('Combustible'),
                    ),
                    DropdownMenuItem(value: 'OTROS', child: Text('Otros')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedTipo = value;
                      });
                    }
                  },
                ),
                TextFormField(
                  controller: _proveedorController,
                  decoration: const InputDecoration(labelText: 'Proveedor *'),
                  validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _numeroController,
                  decoration: const InputDecoration(labelText: '#Documento *'),
                  validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _montoController,
                  decoration: const InputDecoration(labelText: 'Monto *'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Requerido';
                    if (double.tryParse(v!) == null) return 'Número inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                if (_localImagePath != null)
                  Column(
                    children: [
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_localImagePath!),
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => Container(
                                height: 150,
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.cancel,
                              color: Colors.red,
                              shadows: [
                                Shadow(blurRadius: 5, color: Colors.white),
                              ],
                            ),
                            onPressed: () =>
                                setState(() => _localImagePath = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isUploading
                          ? null
                          : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Cámara'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isUploading
                          ? null
                          : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galería'),
                    ),
                  ],
                ),
                if (_isUploading)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 12,
                          width: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Subiendo documento...',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _save,
          child: const Text('Agregar'),
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 70, // Reducir calidad para subida rápida
    );

    if (pickedFile != null) {
      setState(() {
        _localImagePath = pickedFile.path;
      });
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isUploading = true);
      String? documentoPath;

      try {
        if (_localImagePath != null) {
          documentoPath = await LiquidacionesService.uploadDocumento(
            _localImagePath!,
          );
        }

        final factura = Factura(
          proveedor: _proveedorController.text,
          numeroFactura: _numeroController.text,
          tipo: _selectedTipo,
          monto: double.parse(_montoController.text),
          fecha: _selectedDate,
          documento: documentoPath,
        );
        widget.onSave(factura);
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al subir imagen: $e')));
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }
}
