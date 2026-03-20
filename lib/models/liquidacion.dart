class Liquidacion {
  final String id;
  final String empleadoId;
  final String? empleadoNombre;
  final String? empleadoApellido;
  final DateTime fecha;
  final String? tarjetaUlt4;
  final int? proyectoId;
  final String? proyectoNombre;
  final String tipo;
  final String? personalIncluido;
  final String estado;
  final double? total;
  final DateTime createdAt;
  final List<Factura>? facturas;
  final Map<String, double>? totales;

  Liquidacion({
    required this.id,
    required this.empleadoId,
    this.empleadoNombre,
    this.empleadoApellido,
    required this.fecha,
    this.tarjetaUlt4,
    this.proyectoId,
    this.proyectoNombre,
    required this.tipo,
    this.personalIncluido,
    required this.estado,
    this.total,
    required this.createdAt,
    this.facturas,
    this.totales,
  });

  factory Liquidacion.fromJson(Map<String, dynamic> json) {
    return Liquidacion(
      id: json['id']?.toString() ?? '',
      empleadoId: json['empleado_id']?.toString() ?? '',
      empleadoNombre: json['empleado']?['nombre'],
      empleadoApellido: json['empleado']?['apellido'],
      fecha: json['fecha'] != null
          ? DateTime.parse(json['fecha'])
          : DateTime.now(),
      tarjetaUlt4: json['tarjeta_ult4'],
      proyectoId: json['proyecto_id'] != null
          ? (json['proyecto_id'] is int
                ? json['proyecto_id']
                : int.tryParse(json['proyecto_id'].toString()))
          : null,
      proyectoNombre: json['proyecto']?['nombre'],
      tipo: json['tipo'] ?? 'VIATICOS',
      personalIncluido: json['personal_incluido'],
      estado: json['estado'] ?? 'pendiente',
      total: json['total'] != null ? (json['total'] as num).toDouble() : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      facturas: json['facturas'] != null
          ? (json['facturas'] as List).map((f) => Factura.fromJson(f)).toList()
          : null,
      totales: json['totales'] != null
          ? Map<String, double>.from(
              (json['totales'] as Map).map(
                (key, value) =>
                    MapEntry(key.toString(), (value as num).toDouble()),
              ),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'empleado_id': empleadoId,
      'fecha': fecha.toIso8601String().split('T')[0],
      'tarjeta_ult4': tarjetaUlt4,
      'proyecto_id': proyectoId,
      'tipo': tipo,
      'personal_incluido': personalIncluido,
      'total': total,
    };
  }

  String get empleadoCompleto =>
      empleadoNombre != null && empleadoApellido != null
      ? '$empleadoNombre $empleadoApellido'
      : 'N/A';

  double get totalGeneral => totales?['TOTAL'] ?? (total ?? 0.0);

  String get estadoLabel {
    switch (estado) {
      case 'pendiente':
        return 'Pendiente';
      case 'aprobada':
        return 'Aprobada';
      case 'rechazada':
        return 'Rechazada';
      default:
        return estado;
    }
  }
}

class Factura {
  final String? id;
  final String? liquidacionId;
  final String proveedor;
  final String numeroFactura;
  final String tipo;
  final double monto;
  final DateTime fecha;
  final String? documento;
  final DateTime? createdAt;

  Factura({
    this.id,
    this.liquidacionId,
    required this.proveedor,
    required this.numeroFactura,
    required this.tipo,
    required this.monto,
    required this.fecha,
    this.documento,
    this.createdAt,
  });

  factory Factura.fromJson(Map<String, dynamic> json) {
    return Factura(
      id: json['id'],
      liquidacionId: json['liquidacion_id'],
      proveedor: json['proveedor'],
      numeroFactura: json['numero_factura'],
      tipo: json['tipo'],
      monto: (json['monto'] as num).toDouble(),
      fecha: DateTime.parse(json['fecha']),
      documento: json['documento'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'liquidacion_id': liquidacionId,
      'proveedor': proveedor,
      'numero_factura': numeroFactura,
      'tipo': tipo,
      'monto': monto,
      'fecha': fecha.toIso8601String().split('T')[0],
      'documento': documento,
    };
  }

  String get tipoLabel {
    switch (tipo) {
      case 'D':
        return 'Desayuno';
      case 'A':
        return 'Almuerzo';
      case 'C':
        return 'Cena';
      case 'H':
        return 'Hospedaje';
      case 'COMBUSTIBLE':
        return 'Combustible';
      case 'OTROS':
        return 'Otros';
      default:
        return tipo;
    }
  }
}

class Empleado {
  final String id;
  final String nombre;
  final String apellido;
  final String? cedula;
  final String? departamento;

  Empleado({
    required this.id,
    required this.nombre,
    required this.apellido,
    this.cedula,
    this.departamento,
  });

  factory Empleado.fromJson(Map<String, dynamic> json) {
    return Empleado(
      id: json['id'].toString(),
      nombre: json['nombre'],
      apellido: json['apellido'],
      cedula: json['cedula'],
      departamento: json['departamento'],
    );
  }

  String get nombreCompleto => '$nombre $apellido';
}

class Proyecto {
  final int id;
  final String nombre;
  final String? zona;

  Proyecto({required this.id, required this.nombre, this.zona});

  factory Proyecto.fromJson(Map<String, dynamic> json) {
    return Proyecto(
      id: (json['project_id'] ?? json['id'] ?? 0) as int,
      nombre: json['nombre'] ?? 'Sin nombre',
      zona: json['zona'],
    );
  }
}
