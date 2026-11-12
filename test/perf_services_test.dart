import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/core/kernel/kernel_types.dart';
import 'package:zip_browser/core/tab/tab_memory_policy.dart';
import 'package:zip_browser/core/theme/appearance_settings.dart';
import 'package:zip_browser/services/web_font_injector.dart';
import 'package:zip_browser/services/webview_tuning.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('网页字体注入', () {
    test('空字族不生成脚本', () {
      expect(WebFontInjector.buildScript(''), isNull);
      expect(WebFontInjector.buildScript('   '), isNull);
    });

    test('生成覆盖样式并跳过代码块', () {
      final script = WebFontInjector.buildScript('Noto Serif SC')!;
      expect(script.contains('"Noto Serif SC"'), isTrue);
      expect(script.contains(':not(pre)'), isTrue);
      expect(script.contains(':not(code)'), isTrue);
      expect(script.contains('zb-web-font'), isTrue);
    });
  });

  group('网页访问优化脚本', () {
    test('预连接与优先级脚本均为 documentStart', () {
      expect(WebViewTuning.preconnectScript().timing,
          UserScriptInjectionTiming.documentStart);
      expect(WebViewTuning.priorityHintScript().timing,
          UserScriptInjectionTiming.documentStart);
      expect(WebViewTuning.preconnectScript().source.contains('preconnect'),
          isTrue);
      expect(
          WebViewTuning.priorityHintScript().source.contains('fetchpriority'),
          isTrue);
    });
  });

  group('后台标签休眠判定', () {
    bool sleep({
      bool active = false,
      bool pinned = false,
      bool priv = false,
      int tabs = 8,
      int idleMin = 15,
    }) =>
        TabMemoryPolicy.shouldSleep(
          isActive: active,
          pinned: pinned,
          privateTab: priv,
          tabCount: tabs,
          idle: Duration(minutes: idleMin),
          threshold: const Duration(minutes: 10),
        );

    test('前台 / 固定 / 隐私标签不休眠', () {
      expect(sleep(active: true), isFalse);
      expect(sleep(pinned: true), isFalse);
      expect(sleep(priv: true), isFalse);
    });

    test('标签数量不足或空闲未达阈值不休眠', () {
      expect(sleep(tabs: 4), isFalse);
      expect(sleep(idleMin: 5), isFalse);
    });

    test('满足条件时休眠', () {
      expect(sleep(), isTrue);
    });
  });

  group('快照脚本', () {
    test('恢复脚本转义引号并区分布尔值', () {
      final script = TabMemoryPolicy.restoreScript(
        scrollX: 10,
        scrollY: 240,
        values: const {
          'q': 'a"b\nc',
          'remember': true,
        },
      );
      expect(script.contains('window.scrollTo(10.0, 240.0)'), isTrue);
      expect(script.contains(r'"q":"a\"b\nc"'), isTrue);
      expect(script.contains('"remember":true'), isTrue);
      expect(script.contains('addEventListener'), isTrue);
    });

    test('decodeSnapshot 兼容重复编码', () {
      final map = {'url': 'https://a.test', 'scrollY': 12};
      final encoded = jsonEncode(jsonEncode(map));
      final decoded = TabMemoryPolicy.decodeSnapshot(encoded)!;
      expect(decoded['url'], 'https://a.test');
      expect(decoded['scrollY'], 12);
      expect(TabMemoryPolicy.decodeSnapshot('oops'), isNull);
      expect(TabMemoryPolicy.decodeSnapshot(null), isNull);
    });
  });

  group('网页字体取得与持久化', () {
    test('默认跟随页面，可设置并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await AppearanceSettings.create();
      expect(s.webFontFamily, isEmpty);

      await s.setWebFontFamily('  Noto Serif SC  ');
      expect(s.webFontFamily, 'Noto Serif SC');

      final again = await AppearanceSettings.create();
      expect(again.webFontFamily, 'Noto Serif SC');
    });
  });
}
