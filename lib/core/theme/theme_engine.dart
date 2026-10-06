import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:material_color_utilities/palettes/core_palette.dart';

import 'appearance_settings.dart';

/// 主题引擎：根据 [AppearanceSettings] 生成亮/暗 ThemeData。
class ThemeEngine {
  /// 计算颜色方案：优先使用莫奈动态色，否则用 seed 色生成。
  static ColorScheme _scheme(
      AppearanceSettings s, Brightness brightness, CorePalette? monet) {
    if (s.monetEnabled && monet != null) {
      return monet.toColorScheme(brightness: brightness);
    }
    return ColorScheme.fromSeed(seedColor: s.seedColor, brightness: brightness);
  }

  static ThemeData light(AppearanceSettings s, {CorePalette? monet}) {
    final scheme = _scheme(s, Brightness.light, monet);
    final accent = s.accentColor ?? scheme.primary;
    return _build(scheme, accent, s, Brightness.light);
  }

  static ThemeData dark(AppearanceSettings s, {CorePalette? monet}) {
    final scheme = _scheme(s, Brightness.dark, monet);
    final accent = s.accentColor ?? scheme.primary;
    return _build(scheme, accent, s, Brightness.dark);
  }

  static ThemeData _build(
    ColorScheme scheme,
    Color accent,
    AppearanceSettings s,
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    final scaffoldBg = isDark && s.trueBlack
        ? Colors.black
        : (isDark ? const Color(0xFF121418) : const Color(0xFFF4F7FA));
    final radius = s.radiusValue;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        secondary: accent,
      ),
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBg,
      visualDensity: s.visualDensity,
      textTheme: _textTheme(s, isDark),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: isDark ? const Color(0xFF1A1D22) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1E2228) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: isDark ? Colors.white24 : Colors.black26,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: isDark ? Colors.white24 : Colors.black26,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return null;
        }),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : Colors.black12,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(AppearanceSettings s, bool isDark) {
    final scale = s.fontScale;
    final color = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;
    return TextTheme(
      displayLarge: TextStyle(fontSize: 57 * scale, color: color),
      displayMedium: TextStyle(fontSize: 45 * scale, color: color),
      displaySmall: TextStyle(fontSize: 36 * scale, color: color),
      headlineLarge: TextStyle(fontSize: 32 * scale, color: color),
      headlineMedium: TextStyle(fontSize: 28 * scale, color: color),
      headlineSmall: TextStyle(fontSize: 24 * scale, color: color),
      titleLarge: TextStyle(
          fontSize: 22 * scale, color: color, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(
          fontSize: 16 * scale, color: color, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(fontSize: 14 * scale, color: subColor),
      bodyLarge: TextStyle(fontSize: 16 * scale, color: color),
      bodyMedium: TextStyle(fontSize: 14 * scale, color: color),
      bodySmall: TextStyle(fontSize: 12 * scale, color: subColor),
      labelLarge: TextStyle(fontSize: 14 * scale, color: color),
      labelMedium: TextStyle(fontSize: 12 * scale, color: subColor),
      labelSmall: TextStyle(fontSize: 11 * scale, color: subColor),
    );
  }
}
