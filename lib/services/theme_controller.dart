// =============================================================================
// theme_controller.dart — Modo claro / oscuro / sistema
// -----------------------------------------------------------------------------
// Guarda la preferencia en SharedPreferences (`theme_mode`: system | light |
// dark) y la expone como ThemeMode para MaterialApp. Se cambia desde
// Perfil → Apariencia.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const String _kPref = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  String get etiqueta {
    switch (_mode) {
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.dark:
        return 'Oscuro';
      case ThemeMode.system:
        return 'Según el sistema';
    }
  }

  Future<void> cargar() async {
    try {
      final p = await SharedPreferences.getInstance();
      _mode = _parse(p.getString(_kPref));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPref, m.name);
    } catch (_) {}
  }

  static ThemeMode _parse(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
