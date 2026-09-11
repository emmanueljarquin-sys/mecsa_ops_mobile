// =============================================================================
// app_theme.dart — Tema claro y oscuro de MecsaOPS
// -----------------------------------------------------------------------------
// Los colores "semánticos" de la app (fondo, superficie, texto principal,
// texto secundario, bordes…) viven en la extensión [AppColors] y cambian con
// el modo. Las pantallas los leen con `AppColors.of(context)` (o el atajo
// `context.colors`) en vez de usar valores fijos, así el modo nocturno se ve
// coherente sin tocar cada widget.
//
// El modo (sistema / claro / oscuro) lo decide ThemeController y lo aplica
// MaterialApp.themeMode en main.dart.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:google_fonts/google_fonts.dart';

/// Colores semánticos que dependen del modo claro/oscuro.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Fondo de pantalla (Scaffold).
  final Color background;
  /// Tarjetas, hojas, barras: superficie elevada sobre el fondo.
  final Color surface;
  /// Superficie secundaria (chips, campos, filas alternas, placeholders).
  final Color surfaceVariant;
  /// Texto principal.
  final Color textPrimary;
  /// Texto secundario (subtítulos, etiquetas).
  final Color textSecondary;
  /// Texto atenuado (pistas, placeholders, iconos inactivos).
  final Color textMuted;
  /// Bordes y divisores.
  final Color border;
  /// Sombra de tarjetas.
  final Color shadow;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.shadow,
  });

  static const AppColors light = AppColors(
    background: Color(0xFFF8FAFC),
    surface: Colors.white,
    surfaceVariant: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF212529),
    textSecondary: Color(0xFF6C757D),
    textMuted: Color(0xFF9CA3AF),
    border: Color(0xFFE5E7EB),
    shadow: Color(0x0A000000),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF0B1220),
    surface: Color(0xFF162032),
    surfaceVariant: Color(0xFF1F2B40),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFFA3B1C6),
    textMuted: Color(0xFF6B7A90),
    border: Color(0xFF2A3853),
    shadow: Color(0x40000000),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  bool get isDark => background.computeLuminance() < 0.2;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? shadow,
  }) =>
      AppColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceVariant: surfaceVariant ?? this.surfaceVariant,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        border: border ?? this.border,
        shadow: shadow ?? this.shadow,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// Atajo: `context.colors.surface`.
extension AppColorsContext on BuildContext {
  AppColors get colors => AppColors.of(this);
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  // Colores Corporativos (Basados en CMS/Web)
  static const Color primaryColor = Color(0xFF1E293B); // Slate Mecsa
  static const Color secondaryColor = Color(0xFF475569); // Slate Darker
  static const Color accentColor = Color(0xFF0EA5E9); // Sky Blue
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color backgroundColor = Color(0xFFF8FAFC); // Slate Ultra Light
  static const Color surfaceColor = Colors.white;

  /// Primario en modo oscuro: el slate corporativo se pierde sobre fondo
  /// oscuro, así que los botones y acentos usan un azul más luminoso.
  static const Color darkPrimaryColor = Color(0xFF3B82F6);

  static const PageTransitionsTheme _transitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  );

  static ThemeData get lightTheme => _build(AppColors.light, Brightness.light);
  static ThemeData get darkTheme => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness b) {
    final bool dark = b == Brightness.dark;
    final Color primary = dark ? darkPrimaryColor : primaryColor;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: b,
      primary: primary,
      onPrimary: Colors.white,
      secondary: dark ? const Color(0xFF94A3B8) : secondaryColor,
      surface: c.surface,
      onSurface: c.textPrimary,
      error: errorColor,
    );
    final TextTheme base = GoogleFonts.interTextTheme(
      dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.surface,
      dividerColor: c.border,
      extensions: [c],
      pageTransitionsTheme: _transitions,

      // Tipografía (Google Fonts)
      textTheme: base.apply(bodyColor: c.textPrimary, displayColor: c.textPrimary),

      // AppBar: en claro barra slate con texto blanco (como siempre); en
      // oscuro barra del color de superficie con texto claro.
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? c.surface : primaryColor,
        foregroundColor: dark ? c.textPrimary : Colors.white,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.border),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF334155) : const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(
        textColor: c.textPrimary,
        iconColor: c.textSecondary,
      ),
      iconTheme: IconThemeData(color: c.textPrimary),
      dividerTheme: DividerThemeData(color: c.border),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? c.surfaceVariant : Colors.white,
        hintStyle: TextStyle(color: c.textMuted),
        labelStyle: TextStyle(color: c.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: primary.withValues(alpha: 0.15),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.textPrimary),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: primary,
        unselectedItemColor: c.textMuted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceVariant,
        labelStyle: TextStyle(color: c.textPrimary),
        side: BorderSide(color: c.border),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : null),
      ),
    );
  }
}
