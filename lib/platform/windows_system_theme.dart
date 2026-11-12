import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Windows 系统主题信息（强调色 / 深色偏好 / 壁纸路径）。
///
/// 由原生插件 `zip_browser/native_surface` 的 `readSystemTheme` 方法返回；
/// 非 Windows 平台或调用失败时返回 null，调用方按现有逻辑降级。
@immutable
class WindowsSystemTheme {
  const WindowsSystemTheme({
    this.accentColor,
    this.darkMode = false,
    this.wallpaperPath,
  });

  /// 系统强调色（ARGB）。
  final Color? accentColor;

  /// 应用深色偏好（注册表 AppsUseLightTheme == 0）。
  final bool darkMode;

  /// 当前桌面壁纸文件路径。
  final String? wallpaperPath;

  static const MethodChannel _channel =
      MethodChannel('zip_browser/native_surface');

  /// 读取系统主题；非 Windows 或插件不可用时返回 null。
  static Future<WindowsSystemTheme?> read() async {
    if (!Platform.isWindows) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
          'readSystemTheme');
      if (raw == null) return null;
      final accent = raw['accentColor'];
      final path = raw['wallpaperPath'];
      return WindowsSystemTheme(
        // DwmGetColorizationColor 返回带 alpha 的 ARGB，统一归一为不透明
        accentColor:
            accent is int && accent != 0 ? Color(0xFF000000 | accent) : null,
        darkMode: raw['darkMode'] == true,
        wallpaperPath: path is String && path.isNotEmpty ? path : null,
      );
    } catch (e) {
      debugPrint('读取 Windows 系统主题失败：$e');
      return null;
    }
  }
}
