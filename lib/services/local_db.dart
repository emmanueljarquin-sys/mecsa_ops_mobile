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
  static const int dbVersion = 5;

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
    await _createCacheTable(db);
    await _createOfflineTables(db);
    await _createVehiculosTable(db);
    await _createNotificacionesTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migraciones incrementales: solo agregar, nunca borrar.
    if (oldVersion < 1) await _createLogTable(db);
    if (oldVersion < 2) await _createCacheTable(db);
    if (oldVersion < 3) await _createOfflineTables(db);
    if (oldVersion < 4) await _createVehiculosTable(db);
    if (oldVersion < 5) await _createNotificacionesTable(db);
  }

  /// v5: centro de notificaciones (campana del Dashboard).
  Future<void> _createNotificacionesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notificaciones (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario TEXT NOT NULL,
        titulo  TEXT NOT NULL,
        cuerpo  TEXT NOT NULL,
        tipo    TEXT NOT NULL,
        data    TEXT,
        clave   TEXT,
        ts_ms   INTEGER NOT NULL,
        leida   INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notif_usuario ON notificaciones(usuario, ts_ms DESC)');
  }

  /// v4: vehículos personales del empleado (para iniciar visitas sin red).
  /// Se sobrescriben completos en cada sincronización.
  Future<void> _createVehiculosTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vehiculos (
        id          TEXT PRIMARY KEY,
        empleado_id TEXT NOT NULL,
        alias       TEXT,
        placa       TEXT,
        json        TEXT NOT NULL,
        updated_ms  INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_vehiculos_empleado ON vehiculos(empleado_id)');
  }

  /// Tablas de trabajo offline (v3):
  ///
  /// - `offline_queue`: cola de operaciones pendientes de subir (antes vivía
  ///   en SharedPreferences). `payload` es el JSON completo de la operación
  ///   (record, fotos, hijos). Se procesa en orden de `created_ms`.
  /// - `liquidaciones`: liquidaciones del usuario (último mes, traídas al
  ///   iniciar sesión) más las creadas sin conexión (`local = 1`). `json`
  ///   guarda la fila completa incluidas sus facturas.
  /// - `reservas`: copia de las reservas del usuario tal como las devuelve el
  ///   API. Se sobreescriben completas en cada sincronización (el servidor
  ///   manda). Sirven para ver reservas y registrar salida/entrada sin red.
  /// - `id_map`: traduce ids locales (`local-…`) a ids del servidor una vez
  ///   sincronizados, para que operaciones encadenadas (iniciar visita →
  ///   waypoints → finalizar) se resuelvan aunque se hayan creado offline.
  Future<void> _createOfflineTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_queue (
        id          TEXT PRIMARY KEY,
        type        TEXT    NOT NULL,
        payload     TEXT    NOT NULL,
        created_ms  INTEGER NOT NULL,
        attempts    INTEGER NOT NULL DEFAULT 0,
        last_error  TEXT,
        usuario     TEXT,
        estado      TEXT    NOT NULL DEFAULT 'pendiente',
        synced_ms   INTEGER,
        remote_id   TEXT
      )
    ''');
    // estado: 'pendiente' (falta subir) | 'subido' (confirmado por el servidor).
    // Las subidas se conservan un tiempo como historial y luego se purgan.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_offline_queue_created ON offline_queue(created_ms)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_offline_queue_estado ON offline_queue(estado)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reservas (
        id            TEXT PRIMARY KEY,
        empleado_id   TEXT NOT NULL,
        estado        TEXT,
        fecha_salida  TEXT,
        fecha_regreso TEXT,
        json          TEXT NOT NULL,
        updated_ms    INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reservas_empleado ON reservas(empleado_id, fecha_salida DESC)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS liquidaciones (
        id          TEXT PRIMARY KEY,
        empleado_id TEXT    NOT NULL,
        fecha       TEXT,
        estado      TEXT,
        total       REAL,
        created_ms  INTEGER NOT NULL,
        local       INTEGER NOT NULL DEFAULT 0,
        json        TEXT    NOT NULL,
        updated_ms  INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_liq_empleado ON liquidaciones(empleado_id, created_ms DESC)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS id_map (
        local_id    TEXT PRIMARY KEY,
        remote_id   TEXT NOT NULL,
        created_ms  INTEGER NOT NULL
      )
    ''');
  }

  /// Caché de lectura: última respuesta conocida de cada consulta remota,
  /// serializada en JSON. Permite mostrar datos sin conexión.
  /// key: `usuario:nombre` (p.ej. `ana@mecsa.net:reservas`).
  Future<void> _createCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache (
        key        TEXT PRIMARY KEY,
        json       TEXT NOT NULL,
        updated_ms INTEGER NOT NULL
      )
    ''');
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
