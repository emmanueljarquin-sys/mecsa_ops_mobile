// =============================================================================
// liquidaciones_local.dart — Liquidaciones en SQLite (tabla `liquidaciones`)
// -----------------------------------------------------------------------------
// Dos tipos de filas:
//
//   local = 0 → copia de las liquidaciones del servidor (último mes del
//               usuario). Se reemplazan completas en cada sincronización.
//   local = 1 → liquidaciones creadas SIN conexión que todavía están en la
//               cola offline. Su id es `local-<uuid>`. Se borran cuando la
//               cola confirma la subida (OfflineService._subirLiquidacion).
//
// `json` guarda la fila completa (con `facturas`) para poder mostrar el
// detalle sin red. Nunca lanza: un fallo local no debe romper la carga.
// =============================================================================
import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/liquidacion.dart';
import 'app_logger.dart';
import 'local_db.dart';

class LiquidacionesLocal {
  LiquidacionesLocal._();
  static final LiquidacionesLocal instance = LiquidacionesLocal._();

  Map<String, dynamic> _row(Map<String, dynamic> j, {required bool local}) {
    final created = DateTime.tryParse(j['created_at']?.toString() ?? '') ??
        DateTime.now();
    return {
      'id': j['id'].toString(),
      'empleado_id': j['empleado_id'].toString(),
      'fecha': j['fecha']?.toString(),
      'estado': j['estado']?.toString(),
      'total': (j['total'] is num)
          ? (j['total'] as num).toDouble()
          : double.tryParse(j['total']?.toString() ?? ''),
      'created_ms': created.millisecondsSinceEpoch,
      'local': local ? 1 : 0,
      'json': jsonEncode(j, toEncodable: (o) => o.toString()),
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Reemplaza las liquidaciones remotas del empleado por [rows] (las del
  /// último mes). Las locales pendientes no se tocan.
  Future<void> guardarRemotas(
      String empleadoId, List<Map<String, dynamic>> rows) async {
    try {
      final db = await LocalDb.instance.db;
      await db.transaction((txn) async {
        await txn.delete('liquidaciones',
            where: 'empleado_id = ? AND local = 0', whereArgs: [empleadoId]);
        for (final r in rows) {
          await txn.insert('liquidaciones', _row(r, local: false),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      log.i('liquidaciones', 'Liquidaciones guardadas en SQLite',
          data: {'empleado': empleadoId, 'filas': rows.length});
    } catch (e, st) {
      log.w('liquidaciones', 'No se pudieron guardar en SQLite', error: e);
      // ignore: avoid_print
      print(st);
    }
  }

  /// Guarda una liquidación creada sin conexión (id local) con sus facturas.
  Future<void> guardarPendiente({
    required String localId,
    required Liquidacion liquidacion,
    required List<Factura> facturas,
  }) async {
    try {
      final j = liquidacion.toJson();
      j['id'] = localId;
      j['estado'] = 'pendiente';
      j['created_at'] = DateTime.now().toIso8601String();
      j['facturas'] = facturas.map((f) {
        final fj = f.toJson();
        fj['liquidacion_id'] = localId;
        if (f.localDocPath != null) fj['documento_local'] = f.localDocPath;
        return fj;
      }).toList();
      final db = await LocalDb.instance.db;
      await db.insert('liquidaciones', _row(j, local: true),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      log.w('liquidaciones', 'No se pudo guardar la pendiente', error: e);
    }
  }

  Future<void> eliminar(String id) async {
    try {
      final db = await LocalDb.instance.db;
      await db.delete('liquidaciones', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      log.w('liquidaciones', 'No se pudo eliminar $id', error: e);
    }
  }

  /// Lista del empleado, pendientes locales primero y luego por fecha de
  /// creación descendente. [estado] filtra (pendiente/aprobada/rechazada).
  Future<List<Liquidacion>> listar(String empleadoId,
      {String? estado, bool soloLocales = false}) async {
    try {
      final db = await LocalDb.instance.db;
      final where = StringBuffer('empleado_id = ?');
      final args = <Object>[empleadoId];
      if (soloLocales) where.write(' AND local = 1');
      if (estado != null) {
        where.write(' AND estado = ?');
        args.add(estado);
      }
      final rows = await db.query('liquidaciones',
          where: where.toString(),
          whereArgs: args,
          orderBy: 'local DESC, created_ms DESC');
      return rows.map((r) {
        final j = Map<String, dynamic>.from(jsonDecode(r['json'] as String));
        final l = Liquidacion.fromJson(j);
        l.esLocal = (r['local'] as int) == 1;
        return l;
      }).toList();
    } catch (e) {
      log.w('liquidaciones', 'No se pudo leer SQLite', error: e);
      return [];
    }
  }

  Future<Liquidacion?> obtener(String id) async {
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.query('liquidaciones',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      final r = rows.first;
      final l = Liquidacion.fromJson(
          Map<String, dynamic>.from(jsonDecode(r['json'] as String)));
      l.esLocal = (r['local'] as int) == 1;
      return l;
    } catch (_) {
      return null;
    }
  }

  Future<void> limpiarEmpleado(String empleadoId) async {
    try {
      final db = await LocalDb.instance.db;
      await db.delete('liquidaciones',
          where: 'empleado_id = ? AND local = 0', whereArgs: [empleadoId]);
    } catch (_) {}
  }
}
