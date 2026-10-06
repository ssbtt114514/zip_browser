import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zip_browser/core/tab/home_page.dart';
import 'package:zip_browser/services/bookmarks_service.dart';
import 'package:zip_browser/services/history_service.dart';
import 'package:zip_browser/ui/design/zb_design.dart';

void main() {
  group('ZbColors 语义色板', () {
    const seed = Color(0xFF0B84A5);

    ZbColors palette(Brightness brightness) => ZbColors(
          ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
          brightness == Brightness.dark,
        );

    // 旧实现在标签栏 / 地址栏里写死了 Color(0xFFE7EDF2)、Colors.white 等浅色值，
    // 导致深色主题下外壳发白、文字看不清。以下断言用于锁死该回归。
    test('深色主题的外壳确实是暗色，浅色主题的外壳确实是亮色', () {
      final light = palette(Brightness.light);
      final dark = palette(Brightness.dark);

      expect(dark.chrome.computeLuminance(), lessThan(0.20),
          reason: '深色主题标签栏底色应为暗色');
      expect(dark.chromeElevated.computeLuminance(), lessThan(0.25),
          reason: '深色主题工具栏底色应为暗色');
      expect(light.chrome.computeLuminance(), greaterThan(0.60),
          reason: '浅色主题标签栏底色应为亮色');
      expect(light.chromeElevated.computeLuminance(), greaterThan(0.70));
    });

    test('文字色与底色对比方向正确（亮底深字 / 暗底浅字）', () {
      final light = palette(Brightness.light);
      final dark = palette(Brightness.dark);

      expect(light.textPrimary.computeLuminance(), lessThan(0.30));
      expect(dark.textPrimary.computeLuminance(), greaterThan(0.55));
      // 次要文字比主文字更淡
      expect(dark.textMuted.computeLuminance(),
          greaterThan(dark.chrome.computeLuminance()));
    });

    test('活动标签与外壳底色之间有可辨识的层次差', () {
      final light = palette(Brightness.light);
      final dark = palette(Brightness.dark);

      final lightDelta =
          (light.tabActive.computeLuminance() - light.chrome.computeLuminance())
              .abs();
      final darkDelta =
          (dark.tabActive.computeLuminance() - dark.chrome.computeLuminance())
              .abs();

      expect(lightDelta, greaterThan(0.01),
          reason: '浅色主题下活动标签应比标签栏更亮');
      expect(darkDelta, greaterThan(0.005),
          reason: '深色主题下活动标签应比标签栏更亮');
    });

    test('地址栏填充色在两种主题下都与其上文字保持对比', () {
      for (final brightness in Brightness.values) {
        final zb = palette(brightness);
        final bg = zb.omniboxFill.computeLuminance();
        final fg = zb.textPrimary.computeLuminance();
        expect((bg - fg).abs(), greaterThan(0.3),
            reason: '$brightness 下地址栏文字对比度不足');
      }
    });

    test('交互态与分隔线可辨识但不喧宾夺主', () {
      final dark = palette(Brightness.dark);
      expect(dark.hover.a, greaterThan(0));
      expect(dark.pressed.a, greaterThan(dark.hover.a),
          reason: '按下态应比悬停态更明显');
      expect(dark.hairline.a, greaterThan(0));
    });
  });

  group('HomePage 内置新标签页', () {
    const prefix = 'data:text/html;charset=utf-8,';

    String decode(String uri) {
      expect(uri, startsWith(prefix));
      return Uri.decodeComponent(uri.substring(prefix.length));
    }

    final bookmarks = [
      Bookmark(
        id: '1',
        title: '示例站点',
        url: 'https://a.example/',
        added: DateTime(2024, 1, 1),
      ),
    ];
    final recent = [
      HistoryEntry(
        url: 'https://b.example/page',
        title: 'B 站页面',
        visited: DateTime(2024, 1, 2),
        visits: 5,
      ),
    ];

    test('生成合法 data URI 并包含搜索与快捷入口', () {
      final html = decode(HomePage.dataUri(
        'https://s.example/?q={q}',
        bookmarks: bookmarks,
        recent: recent,
      ));

      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('https://s.example/?q='));
      expect(html, contains('示例站点'));
      expect(html, contains('https://a.example/'));
      expect(html, contains('最近访问'));
      expect(html, contains('B 站页面'));
      // 搜索模板的 {q} 应被拆成 BASE + SUFFIX，而不是原样输出
      expect(html.contains('{q}'), isFalse);
    });

    test('深色 / 浅色两套配色由参数决定', () {
      final dark = decode(HomePage.dataUri('https://s.example/?q={q}', dark: true));
      final light =
          decode(HomePage.dataUri('https://s.example/?q={q}', dark: false));

      expect(dark, contains('content="dark"'));
      expect(light, contains('content="light"'));
      expect(dark, isNot(equals(light)));
      // 深色主题正文为浅色文字
      expect(dark, contains('--fg: #E7EAF0'));
    });

    test('搜索框前置脚本的地址判断正则完整（美元符号未被插值吞掉）', () {
      final html = decode(HomePage.dataUri('https://s.example/?q={q}'));
      // Dart 源里写成 \$ 才是字面 $；若被当成插值会直接编译失败或产生残缺正则。
      // 断言里同样要用拼接绕开 $ 的插值语义。
      final dollar = String.fromCharCode(0x24);
      final backslash = String.fromCharCode(0x5C);
      expect(html, contains('([$backslash/?#].*)?$dollar'));
      expect(html.contains('$backslash$dollar'), isFalse);
    });

    test('无书签时给出引导文案', () {
      final html = decode(HomePage.dataUri('https://s.example/?q={q}'));
      expect(html, contains('还没有常用站点'));
    });

    test('书签数量受 shortcutCount 约束', () {
      final many = List.generate(
        20,
        (i) => Bookmark(
          id: '$i',
          title: 'S$i',
          url: 'https://s$i.example/',
          added: DateTime(2024),
        ),
      );
      final html = decode(HomePage.dataUri(
        'https://s.example/?q={q}',
        bookmarks: many,
        shortcutCount: 4,
      ));
      expect(html, contains('https://s0.example/'));
      expect(html, contains('https://s3.example/'));
      expect(html.contains('https://s4.example/'), isFalse);
    });

    test('最近访问可关闭', () {
      final html = decode(HomePage.dataUri(
        'https://s.example/?q={q}',
        recent: recent,
        showRecent: false,
      ));
      // 注意：CSS 里有一处 "最近访问" 注释、以及由访问记录补齐的"常用站点"
      // 快捷入口都是无条件输出的，因此断言必须针对真正生成的 DOM 节点。
      expect(html.contains('<section class="card recent">'), isFalse);

      final withRecent = decode(HomePage.dataUri(
        'https://s.example/?q={q}',
        recent: recent,
      ));
      expect(withRecent, contains('<section class="card recent">'));
    });
  });
}
