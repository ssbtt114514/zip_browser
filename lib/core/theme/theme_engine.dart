import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:material_color_utilities/palettes/core_palette.dart';

import 'appearance_settings.dart';
import 'style_mode.dart';

/// 莫奈动态色板类型别名。
///
/// `dynamic_color` 1.9 只暴露 `DynamicColorPlugin.getCorePalette()`，而
/// `material_color_utilities` 已把 `CorePalette` 标记为 deprecated（推荐迁移到
/// `DynamicScheme`）。在上游给出替代 API 之前，这里把该类型集中声明一次并
/// 就地忽略告警，避免在 app / main / theme_builder 等处重复 ignore。
// ignore: deprecated_member_use
typedef MonetPalette = CorePalette;

/// 主题引擎：根据 [AppearanceSettings] 生成亮/暗 ThemeData。
class ThemeEngine {
  /// 计算颜色方案：优先使用莫奈动态色，否则用 seed 色生成。
  static ColorScheme _scheme(
      AppearanceSettings s, Brightness brightness, MonetPalette? monet) {
    if (s.monetEnabled && monet != null) {
      return monet.toColorScheme(brightness: brightness);
    }
    return ColorScheme.fromSeed(seedColor: s.seedColor, brightness: brightness);
  }

  static ThemeData light(AppearanceSettings s,
      {MonetPalette? monet, AppStyleMode styleMode = AppStyleMode.material}) {
    final scheme = _scheme(s, Brightness.light, monet);
    final accent = s.accentColor ?? scheme.primary;
    return _build(scheme, accent, s, Brightness.light, styleMode);
  }

  static ThemeData dark(AppearanceSettings s,
      {MonetPalette? monet, AppStyleMode styleMode = AppStyleMode.material}) {
    final scheme = _scheme(s, Brightness.dark, monet);
    final accent = s.accentColor ?? scheme.primary;
    return _build(scheme, accent, s, Brightness.dark, styleMode);
  }

  static ThemeData _build(
    ColorScheme scheme,
    Color accent,
    AppearanceSettings s,
    Brightness brightness,
    AppStyleMode styleMode,
  ) {
    final isDark = brightness == Brightness.dark;
    final cupertino = styleMode == AppStyleMode.cupertino;
    final scaffoldBg = isDark && s.trueBlack
        ? Colors.black
        : (isDark ? const Color(0xFF121418) : const Color(0xFFF4F7FA));
    // Cupertino 风格使用更大的圆角
    final radius =
        cupertino ? (s.radiusValue < 14 ? 14.0 : s.radiusValue) : s.radiusValue;

    return ThemeData(
      useMaterial3: true,
      platform: cupertino ? TargetPlatform.iOS : defaultTargetPlatform,
      splashFactory:
          cupertino ? NoSplash.splashFactory : InkSparkle.splashFactory,
      colorScheme: scheme.copyWith(
        secondary: accent,
      ),
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBg,
      visualDensity: s.visualDensity,
      fontFamily: s.fontFamily.isEmpty ? null : s.fontFamily,
      textTheme: _textTheme(s, isDark),
      appBarTheme: AppBarTheme(
        centerTitle: cupertino,
        backgroundColor: isDark ? const Color(0xFF1A1D22) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: cupertino ? 0.5 : 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        // Cupertino 标题加粗居中
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: cupertino ? FontWeight.w600 : FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      // Cupertino 导航栏底部细分割线
      bottomAppBarTheme: BottomAppBarThemeData(
        color: isDark ? const Color(0xFF1A1D22) : Colors.white,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : Colors.black12,
        thickness: cupertino ? 0.4 : 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1E2228) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cupertino ? 14 : 20),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xFF22262C) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cupertino ? 13 : 8),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: isDark ? Colors.white70 : Colors.black54,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
        indicatorColor: scheme.primary,
        indicatorSize: cupertino
            ? TabBarIndicatorSize.label
            : TabBarIndicatorSize.tab,
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
          // 打开时滑块用「背景色」（融入卡片/页面底），轨道用主题色：
          // 视觉上"滑块=背景色、轨道=强调色"，开关状态一眼可辨。
          if (states.contains(WidgetState.selected)) {
            return isDark ? const Color(0xFF1E2228) : Colors.white;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return null;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.transparent
                : null),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      // 桌面端滚动条：细圆角、主题色滑块，观感更精致
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => isDark ? Colors.white24 : Colors.black26),
        thumbVisibility: WidgetStateProperty.all(false),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            p: cupertino
                ? const CupertinoPageTransitionsBuilder()
                : (p == TargetPlatform.iOS || p == TargetPlatform.macOS
                    ? const CupertinoPageTransitionsBuilder()
                    : const ZoomPageTransitionsBuilder()),
        },
      ),
    );
  }

  static TextTheme _textTheme(AppearanceSettings s, bool isDark) {
    final scale = s.fontScale;
    final color = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;
    // 全局字体族（内置 OPPO Sans / 系统默认 / 导入的自定义字体）
    final family = s.fontFamily.isEmpty ? null : s.fontFamily;
    return TextTheme(
      displayLarge: TextStyle(fontSize: 57 * scale, color: color, fontFamily: family),
      displayMedium: TextStyle(fontSize: 45 * scale, color: color, fontFamily: family),
      displaySmall: TextStyle(fontSize: 36 * scale, color: color, fontFamily: family),
      headlineLarge: TextStyle(fontSize: 32 * scale, color: color, fontFamily: family),
      headlineMedium: TextStyle(fontSize: 28 * scale, color: color, fontFamily: family),
      headlineSmall: TextStyle(fontSize: 24 * scale, color: color, fontFamily: family),
      titleLarge: TextStyle(
          fontSize: 22 * scale, color: color, fontWeight: FontWeight.w600, fontFamily: family),
      titleMedium: TextStyle(
          fontSize: 16 * scale, color: color, fontWeight: FontWeight.w500, fontFamily: family),
      titleSmall: TextStyle(fontSize: 14 * scale, color: subColor, fontFamily: family),
      bodyLarge: TextStyle(fontSize: 16 * scale, color: color, fontFamily: family),
      bodyMedium: TextStyle(fontSize: 14 * scale, color: color, fontFamily: family),
      bodySmall: TextStyle(fontSize: 12 * scale, color: subColor, fontFamily: family),
      labelLarge: TextStyle(fontSize: 14 * scale, color: color, fontFamily: family),
      labelMedium: TextStyle(fontSize: 12 * scale, color: subColor, fontFamily: family),
      labelSmall: TextStyle(fontSize: 11 * scale, color: subColor, fontFamily: family),
    );
  }
}
