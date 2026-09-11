// =============================================================================
// local_db.dart — Base de datos local (SQLite) de la app
// -----------------------------------------------------------------------------
// Punto único de acceso a la base local del teléfono. Hoy aloja la tabla
// `app_log` (registro de actividad / diagnóstico). Está pensada para crecer:
// caché de lectura (vehículos, reservas) y la cola offline se migrarían aquí.
//
// Las migraciones se manejan con `version` + `_onUpgrade`. Nunca borrar tablas
// existentes en un upgrade: solo agregar columnas o tablas nuevas.
// =============================================================================
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  static const String dbName = 'mecsa_ops_local.db';
  static const int dbVersion = 1;

  Database? _db;
  Future<Database>? _opening;

  bool get isOpen => _db != null;

  /// Abre (o devuelve) la base. Idempotente y segura ante llamadas concurrentes.
  Future<Database> get db async {
    if (_db != null) return _db!;
    _opening ??= _open();
    return _opening!;
  }

  Future<String> get _path async => p.join(await getDatabasesPath(), dbName);

  Future<Database> _open() async {
    final database = await openDatabase(
      await _path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _db = database;
    return database;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createLogTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migraciones incrementales. Ejemplo futuro:
    // if (oldVersion < 2) await _createCacheTable(db);
    if (oldVersion < 1) await _createLogTable(db);
  }

  Future<void> _createLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        ts_ms       INTEGER NOT NULL,
        ts          TEXT    NOT NULL,
        level       INTEGER NOT NULL,
        level_name  TEXT    NOT NULL,
        module      TEXT    NOT NULL,
        message     TEXT    NOT NULL,
        data        TEXT,
        error       TEXT,
        stack       TEXT,
        usuario     TEXT,
        app_version TEXT
      )
    ''');
    // ts_ms: epoch ms UTC. ts: ISO-8601 local legible.
    // level: 0 debug, 1 info, 2 warning, 3 error.
    // module: 'auth', 'fetchData', 'registro', 'offline', 'app'...
    // data: JSON con contexto adicional. error/stack: excepción (recortada).
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_log_ts ON app_log(ts_ms DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_log_level ON app_log(level)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_log_module ON app_log(module)');
  }

  /// Tamaño del archivo de base de datos, en bytes (0 si no existe).
  Future<int> sizeBytes() async {
    try {
      final f = File(await _path);
      return await f.exists() ? await f.length() : 0;
    } catch (e) {
      debugPrint('LocalDb.sizeBytes: $e');
      return 0;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}
