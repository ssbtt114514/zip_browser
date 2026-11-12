import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/appearance_settings.dart';
import '../services/wallpaper_color.dart';
import 'windows_system_theme.dart';

/// Windows 系统取色引导。
///
/// 在启动时（以及用户切换取色源时）读取系统强调色或壁纸主色，写入
/// [AppearanceSettings.systemSeedOverride]，由主题引擎按优先级合成配色。
/// 任何一步失败都静默返回，主题回退到手动种子色。
class WindowsThemeBootstrap {
  WindowsThemeBootstrap._();

  static Future<void> apply(AppearanceSettings settings) async {
    if (!Platform.isWindows) return;
    if (!settings.monetEnabled) return;
    if (settings.monetSource == MonetSource.builtin) return;

    final theme = await WindowsSystemTheme.read();
    if (theme == null) return;

    Color? seed;
    if (settings.monetSource == MonetSource.wallpaper) {
      final path = theme.wallpaperPath;
      if (path != null && path.isNotEmpty) {
        seed = await WallpaperColor.extractFromFile(path);
      }
    }
    seed ??= theme.accentColor;
    if (seed == null) return;

    settings.setSystemSeedOverride(seed);
    debugPrint('Windows 取色种子：${seed.toARGB32().toRadixString(16)}');
  }
}
