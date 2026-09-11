// =============================================================================
// notificaciones_service.dart — Centro de notificaciones de la app
// -----------------------------------------------------------------------------
// Guarda en SQLite (tabla `notificaciones`) todo aviso relevante para el
// usuario, para que la campana del Dashboard tenga historial y contador de
// no leídas:
//
//   - Push FCM recibido con la app abierta (pago de kilometraje, etc.)
//   - Cambios de estado de liquidaciones (Realtime)
//   - Operaciones offline que subieron y resultado de la copia de seguridad
//   - Aviso de nueva versión
//
// Cada notificación puede llevar `tipo` y `data` para navegar al abrirla
// (p.ej. tipo 'visita' con visita_id, o 'liquidacion'). Nunca lanza.
// =============================================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app_logger.dart';
import 'local_db.dart';

class NotificacionApp {
  final int id;
  final String titulo;
  final String cuerpo;
  /// 'liquidacion' | 'visita' | 'reserva' | 'sync' | 'version' | 'chat' | 'info'
  final String tipo;
  final Map<String, dynamic> data;
  final DateTime fecha;
  final bool leida;

  const NotificacionApp({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.tipo,
    required this.data,
    required this.fecha,
    required this.leida,
  });
}

class NotificacionesService extends ChangeNotifier {
  NotificacionesService._();
  static final NotificacionesService instance = NotificacionesService._();

  String _usuario = '_';
  int _noLeidas = 0;
  int get noLeidas => _noLeidas;

  void setUsuario(String? email) {
    _usuario = (email == null || email.isEmpty) ? '_' : email.toLowerCase();
    contarNoLeidas();
  }

  /// Agrega una notificación. Si [clave] se repite (p.ej. mismo aviso de
  /// versión) se reemplaza en vez de duplicarse.
  Future<void> agregar({
    required String titulo,
    required String cuerpo,
    String tipo = 'info',
    Map<String, dynamic>? data,
    String? clave,
  }) async {
    try {
      final db = await LocalDb.instance.db;
      if (clave != null) {
        await db.delete('notificaciones',
            where: 'usuario = ? AND clave = ?', whereArgs: [_usuario, clave]);
      }
      await db.insert(
        'notificaciones',
        {
          'usuario': _usuario,
          'titulo': titulo,
          'cuerpo': cuerpo,
          'tipo': tipo,
          'data': jsonEncode(data ?? {}, toEncodable: (o) => o.toString()),
          'clave': clave,
          'ts_ms': DateTime.now().millisecondsSinceEpoch,
          'leida': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Conservar solo las últimas 200 por usuario.
      await db.rawDelete(
        'DELETE FROM notificaciones WHERE usuario = ? AND id NOT IN '
        '(SELECT id FROM notificaciones WHERE usuario = ? ORDER BY ts_ms DESC LIMIT 200)',
        [_usuario, _usuario],
      );
      await contarNoLeidas();
    } catch (e) {
      log.w('notificaciones', 'No se pudo guardar', error: e);
    }
  }

  Future<List<NotificacionApp>> listar({int limit = 100}) async {
    try {
      final db = await LocalDb.instance.db;
      final rows = await db.query('notificaciones',
          where: 'usuario = ?', whereArgs: [_usuario], orderBy: 'ts_ms DESC', limit: limit);
      return rows.map((r) {
        Map<String, dynamic> d = {};
        try {
          d = Map<String, dynamic>.from(jsonDecode(r['data'] as String? ?? '{}'));
        } catch (_) {}
        return NotificacionApp(
          id: r['id'] as int,
          titulo: r['titulo'] as String,
          cuerpo: r['cuerpo'] as String,
          tipo: r['tipo'] as String,
          data: d,
          fecha: DateTime.fromMillisecondsSinceEpoch(r['ts_ms'] as int),
          leida: (r['leida'] as int) == 1,
        );
      }).toList();
    } catch (e) {
      log.w('notificaciones', 'No se pudo leer', error: e);
      return [];
    }
  }

  Future<void> contarNoLeidas() async {
    try {
      final db = await LocalDb.instance.db;
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM notificaciones WHERE usuario = ? AND leida = 0', [_usuario]);
      final n = (r.first['n'] as int?) ?? 0;
      if (n != _noLeidas) {
        _noLeidas = n;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> marcarLeida(int id) async {
    try {
      final db = await LocalDb.instance.db;
      await db.update('notificaciones', {'leida': 1}, where: 'id = ?', whereArgs: [id]);
      await contarNoLeidas();
    } catch (_) {}
  }

  Future<void> marcarTodasLeidas() async {
    try {
      final db = await LocalDb.instance.db;
      await db.update('notificaciones', {'leida': 1},
          where: 'usuario = ? AND leida = 0', whereArgs: [_usuario]);
      await contarNoLeidas();
    } catch (_) {}
  }

  Future<void> eliminar(int id) async {
    try {
      final db = await LocalDb.instance.db;
      await db.delete('notificaciones', where: 'id = ?', whereArgs: [id]);
      await contarNoLeidas();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> limpiar() async {
    try {
      final db = await LocalDb.instance.db;
      await db.delete('notificaciones', where: 'usuario = ?', whereArgs: [_usuario]);
      await contarNoLeidas();
      notifyListeners();
    } catch (_) {}
  }
}
