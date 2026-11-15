import 'package:flutter/services.dart';

/// 屏幕方向模式：跟随系统 / 锁定竖屏 / 锁定横屏。
enum AppOrientationMode { system, portrait, landscape }

extension AppOrientationModeX on AppOrientationMode {
  String get label {
    switch (this) {
      case AppOrientationMode.system:
        return '跟随系统';
      case AppOrientationMode.portrait:
        return '锁定竖屏';
      case AppOrientationMode.landscape:
        return '锁定横屏';
    }
  }

  String get description {
    switch (this) {
      case AppOrientationMode.system:
        return '随设备旋转自动切换';
      case AppOrientationMode.portrait:
        return '始终保持竖屏，适合单手持握';
      case AppOrientationMode.landscape:
        return '始终保持横屏，适合支架与视频';
    }
  }

  /// 允许的设备方向列表；空列表表示由系统决定。
  List<DeviceOrientation> get preferredOrientations {
    switch (this) {
      case AppOrientationMode.system:
        return const [];
      case AppOrientationMode.portrait:
        return const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ];
      case AppOrientationMode.landscape:
        return const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
    }
  }
}

AppOrientationMode parseAppOrientationMode(String? raw) {
  switch (raw) {
    case 'portrait':
      return AppOrientationMode.portrait;
    case 'landscape':
      return AppOrientationMode.landscape;
    default:
      return AppOrientationMode.system;
  }
}

/// 把方向模式应用到宿主；桌面平台为空操作。
Future<void> applyAppOrientation(AppOrientationMode mode) {
  return SystemChrome.setPreferredOrientations(mode.preferredOrientations);
}
