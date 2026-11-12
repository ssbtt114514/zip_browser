import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zip_browser/core/bridge/internal_dispatcher.dart';
import 'package:zip_browser/core/debug/debug_injector.dart';
import 'package:zip_browser/core/debug/debug_log.dart';

void main() {
  group('调试注入脚本', () {
    test('替换全部占位符并保留桥接名', () {
      final script = DebugInjector.buildScript(
        bridgeGlobalName: 'zipBrowser',
        network: true,
      );
      expect(script.contains('__GLOBAL__'), isFalse);
      expect(script.contains('__LIMIT__'), isFalse);
      expect(script.contains('__NETWORK__'), isFalse);
      expect(script.contains('"zipBrowser"'), isTrue);
      expect(script.contains('${DebugInjector.maxEntries}'), isTrue);
    });

    test('hook 控制台、异常与网络', () {
      final script = DebugInjector.buildScript(bridgeGlobalName: 'zb');
      expect(script.contains('window.console'), isTrue);
      expect(script.contains("addEventListener('error'"), isTrue);
      expect(script.contains("addEventListener('unhandledrejection'"), isTrue);
      expect(script.contains('window.fetch'), isTrue);
      expect(script.contains('XMLHttpRequest'), isTrue);
      expect(script.contains('__zbDebugInstalled'), isTrue);
    });

    test('关闭网络后不 hook fetch / XHR', () {
      final script =
          DebugInjector.buildScript(bridgeGlobalName: 'zb', network: false);
      expect(script.contains('origFetch'), isFalse);
      expect(script.contains('XMLHttpRequest'), isFalse);
      expect(script.contains('window.console'), isTrue);
    });

    test('桥接名中的引号被正确转义', () {
      final script = DebugInjector.buildScript(bridgeGlobalName: 'a"b\\c');
      expect(script.contains(jsonEncode('a"b\\c')), isTrue);
    });
  });

  group('调试日志解析', () {
    test('解析完整网络条目', () {
      final e = DebugLogEntry.fromJson({
        'kind': 'network',
        'message': 'GET https://a.test/x',
        'url': 'https://a.test/x',
        'method': 'GET',
        'status': 200,
        'durationMs': 37,
        't': 1,
      })!;
      expect(e.kind, DebugLogKind.network);
      expect(e.status, 200);
      expect(e.displayText, 'GET 200 37ms https://a.test/x');
    });

    test('未知类别回退为 log；缺少 message 返回 null', () {
      final e = DebugLogEntry.fromJson({'kind': 'trace', 'message': 'hi'})!;
      expect(e.kind, DebugLogKind.log);
      expect(DebugLogEntry.fromJson({'kind': 'log'}), isNull);
    });

    test('非法字段类型被忽略', () {
      final e = DebugLogEntry.fromJson({
        'kind': 'network',
        'message': 'm',
        'status': 'oops',
        'method': 3,
      })!;
      expect(e.status, isNull);
      expect(e.method, isNull);
    });
  });

  group('内部消息分发', () {
    test('debug 前缀进入 debugLogs 流', () async {
      final dispatcher = InternalDispatcher();
      final payload = jsonEncode({'kind': 'warn', 'message': '测试警告'});
      final raw = jsonEncode({
        'scope': 'internal',
        'payload': 'debug:$payload',
      });
      final future = dispatcher.debugLogs.first;
      expect(dispatcher.dispatch(raw), isTrue);
      final entry = await future;
      expect(entry.kind, DebugLogKind.warn);
      expect(entry.message, '测试警告');
    });

    test('非 internal 消息交回插件 bridge', () {
      final dispatcher = InternalDispatcher();
      final raw = jsonEncode({'scope': 'plugin', 'payload': 'debug:{}'});
      expect(dispatcher.dispatch(raw), isFalse);
    });

    test('损坏的 debug JSON 被忽略且不抛错', () {
      final dispatcher = InternalDispatcher();
      final raw = jsonEncode({'scope': 'internal', 'payload': 'debug:{oops'});
      expect(dispatcher.dispatch(raw), isTrue);
    });
  });
}
