import 'package:flutter/foundation.dart';

/// 浏览器界面临时状态（页面查找栏开关、嗅探面板开关等）
class BrowserUiState extends ChangeNotifier {
  bool _findOpen = false;
  bool get findOpen => _findOpen;

  bool _sniffOpen = false;
  bool get sniffOpen => _sniffOpen;

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
}
