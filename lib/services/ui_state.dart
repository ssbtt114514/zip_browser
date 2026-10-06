import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 浏览器界面临时状态（页面查找栏开关、嗅探面板开关、全屏等）
class BrowserUiState extends ChangeNotifier {
  bool _findOpen = false;
  bool get findOpen => _findOpen;

  bool _sniffOpen = false;
  bool get sniffOpen => _sniffOpen;

  bool _secondaryOpen = false;
  bool get secondaryOpen => _secondaryOpen;

  bool _fullscreen = false;
  bool get fullscreen => _fullscreen;

  void openFind() {
    if (_findOpen) return;
    _findOpen = true;
    notifyListeners();
  }

  void closeFind() {
    if (!_findOpen) return;
    _findOpen = false;
    notifyListeners();
  }

  void openSniff() {
    if (_sniffOpen) return;
    _sniffOpen = true;
    notifyListeners();
  }

  void closeSniff() {
    if (!_sniffOpen) return;
    _sniffOpen = false;
    notifyListeners();
  }

  void toggleSniff() {
    _sniffOpen = !_sniffOpen;
    notifyListeners();
  }

  void toggleSecondary() {
    _secondaryOpen = !_secondaryOpen;
    notifyListeners();
  }

  void setSecondaryOpen(bool value) {
    if (_secondaryOpen == value) return;
    _secondaryOpen = value;
    notifyListeners();
  }

  /// 全屏 / 退出全屏（沉浸式）
  Future<void> setFullscreen(bool value) async {
    _fullscreen = value;
    await SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    notifyListeners();
  }

  Future<void> toggleFullscreen() => setFullscreen(!_fullscreen);
}
