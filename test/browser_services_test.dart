import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/services/bookmarks_service.dart';
import 'package:zip_browser/services/history_service.dart';
import 'package:zip_browser/services/session_service.dart';
import 'package:zip_browser/services/url_suggest_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UrlSuggestService.looksLikeUrl', () {
    test('识别各种地址形态', () {
      expect(UrlSuggestService.looksLikeUrl('https://a.com'), isTrue);
      expect(UrlSuggestService.looksLikeUrl('http://a.com/x'), isTrue);
      expect(UrlSuggestService.looksLikeUrl('file:///tmp/x'), isTrue);
      expect(UrlSuggestService.looksLikeUrl('about:blank'), isTrue);
      expect(UrlSuggestService.looksLikeUrl('example.com'), isTrue);
      expect(UrlSuggestService.looksLikeUrl('sub.example.co.uk/x?y=1'), isTrue);
      expect(UrlSuggestService.looksLikeUrl('localhost:8080'), isTrue);
      expect(UrlSuggestService.looksLikeUrl('127.0.0.1:3000/y'), isTrue);
    });

    test('普通搜索词不算地址', () {
      expect(UrlSuggestService.looksLikeUrl(''), isFalse);
      expect(UrlSuggestService.looksLikeUrl('flutter'), isFalse);
      expect(UrlSuggestService.looksLikeUrl('hello world'), isFalse);
      expect(UrlSuggestService.looksLikeUrl('flutter widget 教程'), isFalse);
    });
  });

  group('UrlSuggestService.suggest', () {
    late Directory dir;
    late BookmarksService bookmarks;
    late HistoryService history;
    late UrlSuggestService suggest;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('zb_suggest_test_');
      bookmarks = BookmarksService(File(p.join(dir.path, 'bookmarks.json')))
        ..load();
      history = HistoryService(File(p.join(dir.path, 'history.json')))..load();
      suggest = UrlSuggestService(
        history: history,
        bookmarks: bookmarks,
        searchTemplate: () => 'https://search.example/?q={q}',
      );
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('空输入给出最近访问', () {
      history.recordVisit('https://a.com/', 'A 站');
      final list = suggest.suggest('');
      expect(list, isNotEmpty);
      expect(list.first.url, 'https://a.com/');
      expect(list.first.kind, SuggestionKind.history);
    });

    test('搜索词的首条建议是搜索', () {
      final list = suggest.suggest('flutter widgets');
      expect(list.first.kind, SuggestionKind.search);
      expect(list.first.url, startsWith('https://search.example/?q='));
      expect(list.first.url, contains('flutter'));
    });

    test('地址的首条建议是直达', () {
      final list = suggest.suggest('example.com');
      expect(list.first.kind, SuggestionKind.open);
      expect(list.first.url, 'https://example.com');
    });

    test('书签优先于历史，且按 URL 去重', () {
      bookmarks.add(title: 'Example Site', url: 'https://example.com/page');
      history.recordVisit('https://example.com/page', 'Example Site');
      history.recordVisit('https://example.com/other', 'Example Other');

      final list = suggest.suggest('example');
      final kinds = list.map((s) => s.kind).toList();
      expect(kinds.contains(SuggestionKind.bookmark), isTrue);
      expect(kinds.contains(SuggestionKind.history), isTrue);
      expect(kinds.indexOf(SuggestionKind.bookmark),
          lessThan(kinds.indexOf(SuggestionKind.history)));
      // same url should appear only once
      final urls = list.map((s) => s.url).toList();
      expect(urls.toSet().length, urls.length);
    });

    test('限制返回条数', () {
      for (var i = 0; i < 30; i++) {
        history.recordVisit('https://site$i.com/', 'Site $i');
      }
      expect(suggest.suggest('site', limit: 5).length, lessThanOrEqualTo(5));
      expect(suggest.suggest('', limit: 3).length, lessThanOrEqualTo(3));
    });
  });

  group('SessionService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('保存快照时过滤隐私与 data: 地址', () async {
      final s = await SessionService.create();
      expect(s.hasSnapshot, isFalse);

      await s.saveSnapshot([
        const SessionTab(url: 'https://a.com/', title: 'A', pinned: true),
        const SessionTab(url: 'https://b.com/', title: 'B'),
        const SessionTab(url: 'data:text/html,<p>x</p>', title: '内置'),
        const SessionTab(url: ''),
      ]);

      final list = s.readSnapshot();
      expect(list.length, 2);
      expect(list.first.url, 'https://a.com/');
      expect(list.first.pinned, isTrue);
      expect(list[1].title, 'B');

      await s.clearSnapshot();
      expect(s.hasSnapshot, isFalse);
    });

    test('启动模式默认主页，可切换为恢复会话', () async {
      final s = await SessionService.create();
      expect(s.startupMode, SessionStartupMode.home);

      await s.setStartupMode(SessionStartupMode.restore);
      final again = await SessionService.create();
      expect(again.startupMode, SessionStartupMode.restore);
    });

    test('异常退出检测：未标记正常退出时 crashedLastRun 为真', () async {
      // 第一次「运行」：构造时即写 clean=false，且未调用 markCleanExit
      final first = await SessionService.create();
      expect(first.crashedLastRun, isFalse);

      final second = await SessionService.create();
      expect(second.crashedLastRun, isTrue);

      // 第三次：上一次已标记正常退出
      await second.markCleanExit();
      final third = await SessionService.create();
      expect(third.crashedLastRun, isFalse);
    });

    test('快照条目数受上限约束', () async {
      final s = await SessionService.create();
      final many = List.generate(
        SessionService.maxSnapshotTabs + 20,
        (i) => SessionTab(url: 'https://s$i.com/', title: 'S$i'),
      );
      await s.saveSnapshot(many);
      expect(s.readSnapshot().length, SessionService.maxSnapshotTabs);
    });
  });
}
