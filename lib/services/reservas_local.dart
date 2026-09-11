// =============================================================================
// reservas_local.dart — Reservas del usuario en SQLite (tabla `reservas`)
// -----------------------------------------------------------------------------
// Copia local de las reservas tal como las devuelve el API. En cada
// sincronización se reemplazan TODAS las del empleado por lo que mandó el
// servidor (el servidor manda: si una reserva cambió de estado o desapareció,
// aquí se refleja). No hay reservas "locales": crear una reserva requiere
// conexión.
//
// `json` guarda la fila completa (incluido el join `vehiculos`) para que la
// pantalla de detalle funcione sin red. Nunca lanza.
// =============================================================================
import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app_logger.dart';
import 'local_db.dart';

class ReservasLocal {
  ReservasLocal._();
  static final ReservasLocal instance = ReservasLocal._();

  /// Sobrescribe las reservas del empleado con [rows] (lo que dijo el API).
  Future<void> guardar(String empleadoId, List<Map<String, dynamic>> rows) async {
    try {
      final db = await LocalDb.instance.db;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((txn) async {
        await txn.delete('reservas',
            where: 'empleado_id = ?', whereArgs: [empleadoId]);
        for (final r in rows) {
          await txn.insert(
            'reservas',
            {
              'id': r['id'].toString(),
              'empleado_id': empleadoId,
              'estado': r['estado']?.toString(),
              'fecha_salida': r['fecha_salida']?.toString(),
              'fecha_regreso': r['fecha_regreso']?.toString(),
              'json': jsonEncode(r, toEncodable: (o) => o.toString()),
              'updated_ms': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      log.i('reservas', 'Reservas guardadas en SQLite',
          data: {'empleado': empleadoId, 'filas': rows.length});
    } catch (e) {
      log.w('reservas', 'No se pudieron guardar en SQLite', error: e);
    }
  }

  /// Reservas del empleado, más recientes primero.
  Future<List<Map<String, dynamic>>> listar(String? empleadoId) async {
    if (empleadoId == null) return [];
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.query('reservas',
          columns: ['json'],
          where: 'empleado_id = ?',
          whereArgs: [empleadoId],
          orderBy: 'fecha_salida DESC');
      return rows
          .map((r) => Map<String, dynamic>.from(jsonDecode(r['json'] as String)))
          .toList();
    } catch (e) {
      log.w('reservas', 'No se pudo leer SQLite', error: e);
      return [];
    }
  }

  Future<Map<String, dynamic>?> obtener(String id) async {
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.query('reservas',
          columns: ['json'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(jsonDecode(rows.first['json'] as String));
    } catch (_) {
      return null;
    }
  }

  Future<void> limpiarEmpleado(String empleadoId) async {
    try {
      final db = await LocalDb.instance.db;
      await db.delete('reservas', where: 'empleado_id = ?', whereArgs: [empleadoId]);
    } catch (_) {}
  }
}
