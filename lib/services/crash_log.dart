import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

/// 启动 / 运行崩溃日志。
///
/// 写入 `<数据目录>/logs/crash.log`（轮转保留最近 512 KB）。
/// 若应用装好后双击无法启动，把该文件内容反馈给开发者即可定位。
class CrashLog {
  static const int _maxBytes = 512 * 1024;
  static File? _file;
  static bool _enabled = true;

  static File get file {
    final dir = Directory(_dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _file ??= File('${dir.path}/crash.log');
  }

  static String get _dirPath => '${AppPaths.supportDir.path}/logs';

  /// Flutter 框架错误回调
  static void handleFlutterError(FlutterErrorDetails details) {
    if (!_enabled) return;
    write('FLUTTER ERROR', details.exceptionAsString(),
        stack: details.stack?.toString());
  }

  /// Dart 未捕获异步错误回调
  static void handleZoneError(Object error, StackTrace stack) {
    if (!_enabled) return;
    write('UNCAUGHT ERROR', error.toString(), stack: stack.toString());
  }

  /// 磁盘故障时静默放弃，绝不能因写日志而二次崩溃
  static void write(String level, String message, {String? stack}) {
    if (!_enabled || kDebugMode) return;
    try {
      final f = file;
      final sb = StringBuffer()
        ..writeln('===== ${DateTime.now().toIso8601String()} [$level] =====')
        ..writeln(message);
      if (stack != null && stack.isNotEmpty) sb.writeln(stack);
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        f.deleteSync();
      }
      f.writeAsStringSync(sb.toString(), mode: FileMode.append);
    } catch (_) {
      _enabled = false;
    }
  }

  /// 读取日志尾部（开发者工具箱展示）
  static String tail({int maxChars = 6000}) {
    try {
      final f = file;
      if (!f.existsSync()) return '（暂无日志）';
      final text = f.readAsStringSync();
      return text.length <= maxChars
          ? text
          : '…${text.substring(text.length - maxChars)}';
    } catch (e) {
      return '读取失败：$e';
    }
  }

  static void clear() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

/// 在 [body] 外套一层全局错误捕获，所有未处理异常写入崩溃日志。
Future<void> runWithCrashLog(FutureOr<void> Function() body) async {
  await runZonedGuarded(() async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashLog.handleFlutterError(details);
    };
    await body();
  }, CrashLog.handleZoneError);
}
