import 'package:flutter/material.dart';
// ignore: deprecated_member_use
import 'package:material_color_utilities/palettes/core_palette.dart';

/// 内置莫奈取色引擎。
///
/// 不依赖系统 Material You（Android 12+ 之外的 Windows / Linux / 老 Android
/// 也可用）：直接用 Google 官方 material_color_utilities 的 HCT 调色板
/// 从任意种子色生成 Android 12 同款的三组色调色板（主色 / 中性 / 中性变量），
/// 再映射为 Material 3 的 ColorScheme。
class ZbMonetEngine {
  ZbMonetEngine._();

  /// 用内置莫奈引擎从 [seed] 生成完整配色方案。
  static ColorScheme schemeFromSeed(Color seed, Brightness brightness) {
    try {
      // ignore: deprecated_member_use
      final palette = CorePalette.of(seed.toARGB32());
      return palette.toColorScheme(brightness: brightness);
    } catch (_) {
      // 极端输入（全透明等）兜底：Material 3 自带的 HCT 种子方案
      return ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    }
  }

  /// 从系统莫奈色板（若有）或种子色取「源色」。
  // ignore: deprecated_member_use
  static Color sourceColorOf(MonetPalette? palette, Color fallbackSeed) {
    if (palette == null) return fallbackSeed;
    try {
      // tone 40（亮色主色）对应的源色近似值
      // ignore: deprecated_member_use
      return Color(palette.primary.get(40));
    } catch (_) {
      return fallbackSeed;
    }
  }
}
