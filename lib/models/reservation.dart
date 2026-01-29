class Reservation {
  final String? id;
  final dynamic vehiculoId;
  final String empleadoId;
  final DateTime fechaSalida;
  final DateTime fechaRegreso;
  final String motivo;
  final String estado;
  final dynamic proyectoId;
  final String? ubicacion;

  Reservation({
    this.id,
    required this.vehiculoId,
    required this.empleadoId,
    required this.fechaSalida,
    required this.fechaRegreso,
    required this.motivo,
    this.estado = 'Pendiente',
    this.proyectoId,
    this.ubicacion,
  });

  Map<String, dynamic> toJson() {
    return {
      'vehiculo_id': vehiculoId,
      'empleado_id': empleadoId,
      'fecha_salida': fechaSalida.toIso8601String(),
      'fecha_regreso': fechaRegreso.toIso8601String(),
      'motivo': motivo,
      'estado': estado,
      'proyecto_id': proyectoId,
      'ubicacion': ubicacion,
    };
  }

  factory Reservation.fromJson(Map<String, dynamic> json) {
    return Reservation(
      id: json['id'],
      vehiculoId: json['vehiculo_id'],
      empleadoId: json['empleado_id'],
      fechaSalida: DateTime.parse(json['fecha_salida']),
      fechaRegreso: DateTime.parse(json['fecha_regreso']),
      motivo: json['motivo'],
      estado: json['estado'],
      proyectoId: json['proyecto_id'],
      ubicacion: json['ubicacion'],
    );
  }
}
