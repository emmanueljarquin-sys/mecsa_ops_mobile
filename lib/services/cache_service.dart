// =============================================================================
// cache_service.dart — Caché de lectura local (SQLite, tabla `cache`)
// -----------------------------------------------------------------------------
// Guarda la última respuesta conocida de cada consulta remota (vehículos,
// reservas, proyectos...) para que la app pueda mostrar datos sin conexión.
//
// Uso desde AppProvider:
//   await cache.put('reservas', myReservations);         // tras un fetch OK
//   final hit = await cache.get('reservas');             // al arrancar
//   if (hit != null) myReservations = hit.asList();
//
// Las claves se separan por usuario (`scope`, normalmente el email) para que
// dos personas en el mismo teléfono no vean datos ajenas. `clearScope()` se
// llama al cerrar sesión.
//
// Nunca lanza: un fallo de caché no debe romper la carga normal.
// =============================================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app_logger.dart';
import 'local_db.dart';

class CacheHit {
  final Object? value;
  final DateTime updatedAt;
  const CacheHit(this.value, this.updatedAt);

  List<Map<String, dynamic>> asList() {
    final v = value;
    if (v is List) {
      return v
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return [];
  }

  Map<String, dynamic>? asMap() {
    final v = value;
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }
}

class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  String _scope = '_';

  /// Define el usuario dueño de la caché (email). Cambiarlo no borra nada.
  void setScope(String? scope) {
    _scope = (scope == null || scope.isEmpty) ? '_' : scope.toLowerCase();
  }

  String _key(String name) => '$_scope:$name';

  Future<void> put(String name, Object? value) async {
    try {
      final db = await LocalDb.instance.db;
      await db.insert(
        'cache',
        {
          'key': _key(name),
          'json': jsonEncode(value, toEncodable: (o) => o.toString()),
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      log.w('cache', 'No se pudo guardar "$name"', error: e);
    }
  }

  Future<CacheHit?> get(String name) async {
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.query('cache',
          columns: ['json', 'updated_ms'],
          where: 'key = ?',
          whereArgs: [_key(name)],
          limit: 1);
      if (rows.isEmpty) return null;
      final r = rows.first;
      return CacheHit(
        jsonDecode(r['json'] as String),
        DateTime.fromMillisecondsSinceEpoch(r['updated_ms'] as int),
      );
    } catch (e) {
      log.w('cache', 'No se pudo leer "$name"', error: e);
      return null;
    }
  }

  /// Fecha de la última escritura entre varias claves (la más reciente).
  Future<DateTime?> lastUpdated(List<String> names) async {
    try {
      final db = await LocalDb.instance.db;
      final keys = names.map(_key).toList();
      final rows = await db.rawQuery(
        'SELECT MAX(updated_ms) AS m FROM cache WHERE key IN '
        '(${List.filled(keys.length, '?').join(',')})',
        keys,
      );
      final m = rows.first['m'] as int?;
      return m == null ? null : DateTime.fromMillisecondsSinceEpoch(m);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearScope() async {
    try {
      final db = await LocalDb.instance.db;
      final n = await db.delete('cache',
          where: 'key LIKE ?', whereArgs: ['$_scope:%']);
      log.i('cache', 'Caché borrada', data: {'scope': _scope, 'filas': n});
    } catch (e) {
      log.w('cache', 'No se pudo borrar la caché', error: e);
    }
  }

  Future<void> clearAll() async {
    try {
      final db = await LocalDb.instance.db;
      await db.delete('cache');
    } catch (e) {
      debugPrint('CacheService.clearAll: $e');
    }
  }
}

/// Acceso corto.
final CacheService cache = CacheService.instance;
