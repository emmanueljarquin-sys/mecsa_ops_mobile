// =============================================================================
// connectivity_service.dart — Estado de conexión con verificación real
// -----------------------------------------------------------------------------
// connectivity_plus solo dice si hay una red (Wi-Fi/datos). No dice si esa red
// tiene salida a internet: un Wi-Fi cautivo o sin internet cuenta como "red".
// Este servicio combina las dos cosas:
//
//   hasNetwork   → hay una interfaz de red activa (connectivity_plus)
//   hasInternet  → una petición ligera al backend respondió (sondeo real)
//   isOnline     → hasNetwork && hasInternet
//
// El sondeo se hace contra el REST de Supabase (mismo destino que los datos)
// con timeout corto. Se re-sondea al cambiar la red y a pedido
// (`checkInternet(force: true)`), con un pequeño caché para no abusar.
// =============================================================================
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_logger.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  static const Duration probeTimeout = Duration(seconds: 4);
  static const Duration probeCacheTtl = Duration(seconds: 8);

  Uri? _probeUri;
  Map<String, String> _probeHeaders = const {};

  bool _hasNetwork = true;
  bool _hasInternet = true;
  DateTime? _lastProbeAt;
  DateTime? _lastOnlineAt;
  Future<bool>? _probing;
  bool _initialized = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get hasNetwork => _hasNetwork;
  bool get hasInternet => _hasInternet;
  bool get isOnline => _hasNetwork && _hasInternet;
  DateTime? get lastProbeAt => _lastProbeAt;
  DateTime? get lastOnlineAt => _lastOnlineAt;

  /// [probeUrl]: endpoint ligero que responda rápido (p.ej. `<supabase>/rest/v1/`).
  Future<void> init({required String probeUrl, Map<String, String>? headers}) async {
    if (_initialized) return;
    _initialized = true;
    _probeUri = Uri.parse(probeUrl);
    _probeHeaders = headers ?? const {};
    try {
      _hasNetwork = _online(await Connectivity().checkConnectivity());
    } catch (_) {
      _hasNetwork = true;
    }
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      final net = _online(r);
      if (net != _hasNetwork) {
        _hasNetwork = net;
        log.i('conectividad', net ? 'Red disponible' : 'Sin red',
            data: {'tipos': r.map((x) => x.name).toList()});
        notifyListeners();
      }
      if (net) {
        checkInternet(force: true);
      } else {
        _setInternet(false);
      }
    });
    await checkInternet(force: true);
  }

  bool _online(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);

  void _setInternet(bool v) {
    if (v) _lastOnlineAt = DateTime.now();
    if (v != _hasInternet) {
      _hasInternet = v;
      log.i('conectividad', v ? 'Internet OK' : 'Sin internet real');
      notifyListeners();
    }
  }

  /// Verifica salida real a internet. Devuelve el resultado en caché si el
  /// último sondeo es reciente, salvo [force].
  Future<bool> checkInternet({bool force = false}) {
    if (!force &&
        _lastProbeAt != null &&
        DateTime.now().difference(_lastProbeAt!) < probeCacheTtl) {
      return Future.value(isOnline);
    }
    return _probing ??= _probe().whenComplete(() => _probing = null);
  }

  Future<bool> _probe() async {
    try {
      _hasNetwork = _online(await Connectivity().checkConnectivity());
    } catch (_) {}
    if (!_hasNetwork) {
      _lastProbeAt = DateTime.now();
      _setInternet(false);
      notifyListeners();
      return false;
    }
    final uri = _probeUri;
    if (uri == null) return true;
    final sw = Stopwatch()..start();
    bool ok;
    try {
      final resp = await http.get(uri, headers: _probeHeaders).timeout(probeTimeout);
      // Cualquier respuesta HTTP del backend (incluso 401/404) prueba que hay
      // salida a internet. Un portal cautivo suele devolver 302/200 con HTML,
      // así que además exigimos que no sea una redirección a otro host.
      ok = resp.statusCode < 500 &&
          !(resp.isRedirect && resp.headers['location'] != null);
      log.d('conectividad', 'Sondeo',
          data: {'status': resp.statusCode, 'ms': sw.elapsedMilliseconds});
    } catch (e) {
      ok = false;
      log.w('conectividad', 'Sondeo falló',
          data: {'ms': sw.elapsedMilliseconds}, error: e);
    }
    _lastProbeAt = DateTime.now();
    _setInternet(ok);
    return ok;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Acceso corto.
final ConnectivityService connectivity = ConnectivityService.instance;
