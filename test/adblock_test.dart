import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/core/adblock/adblock_data.dart';
import 'package:zip_browser/core/adblock/adblock_script.dart';
import 'package:zip_browser/core/kernel/kernel_types.dart';
import 'package:zip_browser/services/ad_blocker_service.dart';
import 'package:zip_browser/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdBlocker 脚本生成', () {
    test('生成的脚本包含规则与防重入标记', () {
      final s = AdBlocker.buildScript(
        domains: ['ads.example.com'],
        allow: ['ok.example.com'],
        selectors: ['.ad-banner', '[id^="google_ads_"]'],
      );
      expect(s, contains('window.__zbAdBlockLoaded'));
      expect(s, contains('ads.example.com'));
      expect(s, contains('ok.example.com'));
      // 选择器中的引号被正确转义进 JSON 数组
      expect(s, contains(r'[id^=\"google_ads_\"]'));
      expect(s, isNotEmpty);
    });

    test('内置规则表非空且无重复', () {
      expect(kAdBlockDomains.length, greaterThan(100));
      expect(kAdBlockSelectors.length, greaterThan(20));
      final unique = kAdBlockDomains.toSet();
      expect(unique.length, kAdBlockDomains.length,
          reason: '内置域名表不应有重复条目');
    });
  });

  group('AdBlockerService', () {
    test('关闭开关时仍可生成脚本，由 TabManager 决定注入', () async {
      SharedPreferences.setMockInitialValues({'content.ad_block': false});
      final cfg = await ConfigService.create();
      final svc = AdBlockerService(cfg);
      expect(svc.buildUserScript().source.length, greaterThan(0));
    });

    test('白名单优先于拦截规则', () async {
      SharedPreferences.setMockInitialValues({
        'content.ad_block_allow': '["mydomain.example"]',
      });
      final cfg = await ConfigService.create();
      final svc = AdBlockerService(cfg);
      expect(svc.isBlocked('https://pos.baidu.com/x.js'), isTrue);
      expect(svc.isBlocked('https://mydomain.example'), isFalse);
      expect(svc.isBlocked('https://sub.mydomain.example/page'), isFalse);
    });

    test('内置域名后缀匹配', () async {
      SharedPreferences.setMockInitialValues({});
      final cfg = await ConfigService.create();
      final svc = AdBlockerService(cfg);
      expect(svc.isBlocked('https://pos.baidu.com/cpro.js'), isTrue);
      expect(svc.isBlocked('https://pagead2.googlesyndication.com/a'), isTrue);
      expect(svc.isBlocked('https://www.baidu.com/'), isFalse,
          reason: '主站根域名不应被拦截');
      expect(svc.isBlocked('data:text/html,hi'), isFalse);
    });
  });

  group('UserScript 组装', () {
    test('documentStart 时机且匹配所有 URL', () async {
      SharedPreferences.setMockInitialValues({});
      final cfg = await ConfigService.create();
      final svc = AdBlockerService(cfg);
      final us = svc.buildUserScript();
      expect(us.timing, UserScriptInjectionTiming.documentStart);
      expect(us.matchesUrl('https://example.com/'), isTrue);
      expect(us.pluginId, isNull);
    });
  });
}
