import 'debug_log.dart';

/// 可提供页面调试日志的内核（Android WebView / Windows WebView2）
abstract class DebugLogSource {
  Stream<DebugLogEntry> get debugLogs;
}

/// 可打开内核自带开发者工具窗口的内核（Windows WebView2）
abstract class NativeDevTools {
  /// 返回是否成功打开
  Future<bool> openNativeDevTools();
}
