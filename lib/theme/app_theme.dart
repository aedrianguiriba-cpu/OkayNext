import 'package:flutter/material.dart';

/// Palette tokens that differ between dark and light modes.
class AppColors {
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color surfaceElevated;
  final Color border;
  final Color borderBright;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceElevated,
    required this.border,
    required this.borderBright,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });
}

/// Shorthand: `context.col.background`, `context.col.textPrimary`, etc.
extension AppColorsX on BuildContext {
  AppColors get col {
    return Theme.of(this).brightness == Brightness.dark
        ? AppTheme.darkColors
        : AppTheme.lightColors;
  }
}

class AppTheme {
  AppTheme._();

  // ── Semantic colors — same in both themes ─────────────────────────────
  static const Color accent = Color(0xFFF59E0B);
  static const Color accentDark = Color(0xFFD97706);
  static const Color accentDim = Color(0x20F59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF97316);
  static const Color success = Color(0xFF22C55E);

  static const List<Color> songColors = [
    Color(0xFFF43F5E),
    Color(0xFF38BDF8),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFF6366F1),
    Color(0xFF84CC16),
    Color(0xFFFB7185),
  ];

  // ── Dark palette ──────────────────────────────────────────────────────
  static const AppColors darkColors = AppColors(
    background: Color(0xFF080808),
    surface: Color(0xFF0F0F0F),
    surfaceVariant: Color(0xFF161616),
    surfaceElevated: Color(0xFF1E1E1E),
    border: Color(0xFF252525),
    borderBright: Color(0xFF323232),
    textPrimary: Color(0xFFFAFAFA),
    textSecondary: Color(0xFF6B6B6B),
    textMuted: Color(0xFF333333),
  );

  // ── Light palette ─────────────────────────────────────────────────────
  static const AppColors lightColors = AppColors(
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEEEEEE),
    surfaceElevated: Color(0xFFE5E5E5),
    border: Color(0xFFDDDDDD),
    borderBright: Color(0xFFCCCCCC),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF555555),
    textMuted: Color(0xFFAAAAAA),
  );

  // ── Legacy static aliases (dark values) — for const contexts ─────────
  static const Color background = Color(0xFF080808);
  static const Color surface = Color(0xFF0F0F0F);
  static const Color surfaceVariant = Color(0xFF161616);
  static const Color surfaceElevated = Color(0xFF1E1E1E);
  static const Color border = Color(0xFF252525);
  static const Color borderBright = Color(0xFF323232);
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textMuted = Color(0xFF333333);

  // ── ThemeData ─────────────────────────────────────────────────────────

  static ThemeData get darkTheme => _build(Brightness.dark, darkColors);
  static ThemeData get lightTheme => _build(Brightness.light, lightColors);

  /// Backward-compat alias.
  static ThemeData get theme => darkTheme;

  static ThemeData _build(Brightness brightness, AppColors c) => ThemeData(
        useMaterial3: true,
        brightness: brightness,
        scaffoldBackgroundColor: c.background,
        colorScheme: ColorScheme(
          brightness: brightness,
          primary: accent,
          onPrimary: Colors.black,
          secondary: accentDark,
          onSecondary: Colors.black,
          error: danger,
          onError: Colors.white,
          surface: c.surface,
          onSurface: c.textPrimary,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: c.surfaceVariant,
          foregroundColor: c.textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: c.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: c.surfaceVariant,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.border),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: c.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
          labelStyle: TextStyle(color: c.textSecondary),
          hintStyle: TextStyle(color: c.textMuted),
        ),
        textTheme: TextTheme(
          displayLarge: TextStyle(color: c.textPrimary),
          displayMedium: TextStyle(color: c.textPrimary),
          bodyLarge: TextStyle(color: c.textPrimary),
          bodyMedium: TextStyle(color: c.textSecondary),
          labelLarge:
              TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: c.textSecondary),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: accent,
          foregroundColor: Colors.black,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: c.surface,
          selectedItemColor: accent,
          unselectedItemColor: c.textMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
      );
}
