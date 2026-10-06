import 'package:flutter/foundation.dart';

import '../core/desktop_mode_config.dart';
import 'config_service.dart';

/// 桌面模式偏好管理（全局 ChangeNotifier，持久化）。
class DesktopModePreferences extends ChangeNotifier {
  final ConfigService _config;
  DesktopModeConfig _value;

  DesktopModePreferences(this._config) : _value = _config.desktopMode;

  DesktopModeConfig get config => _value;
  bool get enabled => _value.enabled;

  Future<void> update(DesktopModeConfig config) async {
    _value = config;
    notifyListeners();
    await _config.setDesktopMode(config);
  }
}
