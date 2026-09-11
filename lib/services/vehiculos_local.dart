// =============================================================================
// vehiculos_local.dart — Vehículos del empleado en SQLite (tabla `vehiculos`)
// -----------------------------------------------------------------------------
// Copia local de `visitas.vehiculos_personales` del empleado (los que usa para
// el kilometraje de las visitas). Se sobrescribe completa en cada
// sincronización: el servidor manda. Sirve para iniciar visitas sin red.
// Nunca lanza.
// =============================================================================
import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app_logger.dart';
import 'local_db.dart';

class VehiculosLocal {
  VehiculosLocal._();
  static final VehiculosLocal instance = VehiculosLocal._();

  Future<void> guardar(String empleadoId, List<Map<String, dynamic>> rows) async {
    try {
      final db = await LocalDb.instance.db;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((txn) async {
        await txn.delete('vehiculos', where: 'empleado_id = ?', whereArgs: [empleadoId]);
        for (final r in rows) {
          await txn.insert(
            'vehiculos',
            {
              'id': r['id'].toString(),
              'empleado_id': empleadoId,
              'alias': r['alias']?.toString(),
              'placa': r['placa']?.toString(),
              'json': jsonEncode(r, toEncodable: (o) => o.toString()),
              'updated_ms': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      log.i('vehiculos', 'Vehículos del empleado guardados en SQLite',
          data: {'empleado': empleadoId, 'filas': rows.length});
    } catch (e) {
      log.w('vehiculos', 'No se pudieron guardar en SQLite', error: e);
    }
  }

  Future<List<Map<String, dynamic>>> listar(String? empleadoId) async {
    if (empleadoId == null) return [];
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.query('vehiculos',
          columns: ['json'],
          where: 'empleado_id = ?',
          whereArgs: [empleadoId],
          orderBy: 'alias ASC');
      return rows
          .map((r) => Map<String, dynamic>.from(jsonDecode(r['json'] as String)))
          .toList();
    } catch (e) {
      log.w('vehiculos', 'No se pudo leer SQLite', error: e);
      return [];
    }
  }

  Future<void> limpiarEmpleado(String empleadoId) async {
    try {
      final db = await LocalDb.instance.db;
      await db.delete('vehiculos', where: 'empleado_id = ?', whereArgs: [empleadoId]);
    } catch (_) {}
  }
}
