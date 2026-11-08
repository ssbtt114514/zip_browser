import 'package:flutter/foundation.dart';

import '../core/tab/url_utils.dart';
import 'bookmarks_service.dart';
import 'history_service.dart';

/// 地址栏建议类型
enum SuggestionKind {
  /// 「打开 xxx」（输入本身就是一个地址）
  open,

  /// 「搜索 xxx」
  search,

  /// 历史记录
  history,

  /// 书签
  bookmark,
}

/// 一条地址栏建议
@immutable
class UrlSuggestion {
  /// 主文本
  final String text;

  /// 次要文本（通常是完整 URL）；为空时不显示
  final String subtitle;

  /// 实际导航目标
  final String url;

  final SuggestionKind kind;

  const UrlSuggestion({
    required this.text,
    required this.url,
    this.subtitle = '',
    this.kind = SuggestionKind.history,
  });

  @override
  bool operator ==(Object other) =>
      other is UrlSuggestion && other.url == url && other.kind == kind;

  @override
  int get hashCode => Object.hash(url, kind);
}

/// 地址栏自动补全：本地历史 + 书签 + 搜索 / 直达建议。
///
/// 纯本地实现（不联网），因此不依赖任何搜索建议服务，
/// 在任何平台与网络环境下都可用。
class UrlSuggestService {
  final HistoryService history;
  final BookmarksService bookmarks;
  final String Function() searchTemplate;

  UrlSuggestService({
    required this.history,
    required this.bookmarks,
    required this.searchTemplate,
  });

  /// 输入是否「看起来像一个地址」。
  ///
  /// 规则统一收敛在 [UrlInput.isLikelyUrl]，地址栏、建议列表、
  /// 剪贴板识别共用同一套判定，避免三处规则逐渐漂移。
  static bool looksLikeUrl(String input) => UrlInput.isLikelyUrl(input);

  /// 生成的搜索 URL
  String searchUrl(String query) =>
      UrlInput.searchUrl(searchTemplate(), query);

  /// 生成建议列表。
  ///
  /// [query] 为空时给出最近访问（用于聚焦地址栏时的快速入口）。
  List<UrlSuggestion> suggest(String query, {int limit = 8}) {
    final q = query.trim();
    final out = <UrlSuggestion>[];
    final seen = <String>{};

    void push(UrlSuggestion s) {
      if (out.length >= limit) return;
      if (!seen.add(s.url)) return;
      out.add(s);
    }

    if (q.isEmpty) {
      for (final e in history.entries.take(limit)) {
        push(UrlSuggestion(
          text: e.title.isEmpty ? e.url : e.title,
          subtitle: e.url,
          url: e.url,
          kind: SuggestionKind.history,
        ));
      }
      return out;
    }

    // 首条：直达；再看是否补一条同词搜索（地址型输入也能直接搜索）
    if (looksLikeUrl(q)) {
      final target = UrlInput.resolve(
        q,
        searchEngineTemplate: searchTemplate(),
        homeDataUri: 'about:home',
      );
      push(UrlSuggestion(
        text: q,
        subtitle: '打开该地址',
        url: target,
        kind: SuggestionKind.open,
      ));
      push(UrlSuggestion(
        text: q,
        subtitle: '用默认搜索引擎搜索',
        url: searchUrl(q),
        kind: SuggestionKind.search,
      ));
    } else {
      push(UrlSuggestion(
        text: q,
        subtitle: '使用默认搜索引擎搜索',
        url: searchUrl(q),
        kind: SuggestionKind.search,
      ));
    }

    // 书签优先于历史；按匹配度（标题完全匹配 > 前缀 > 包含）与访问次数排序
    final lower = q.toLowerCase();
    final bookmarkHits = <(int, int, Bookmark)>[];
    for (final b in bookmarks.items) {
      final score = _matchScore(b.title, b.url, lower);
      if (score > 0) bookmarkHits.add((score, 0, b));
    }
    bookmarkHits.sort((a, b) => b.$1.compareTo(a.$1));
    for (final hit in bookmarkHits) {
      final b = hit.$3;
      push(UrlSuggestion(
        text: b.title.isEmpty ? b.url : b.title,
        subtitle: b.url,
        url: b.url,
        kind: SuggestionKind.bookmark,
      ));
    }

    final historyHits = <(int, int, HistoryEntry)>[];
    for (final e in history.entries) {
      final score = _matchScore(e.title, e.url, lower);
      if (score > 0) historyHits.add((score, e.visits, e));
    }
    // 匹配度优先，其次访问次数（常用站点更容易被选中）
    historyHits.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      return b.$2.compareTo(a.$2);
    });
    for (final hit in historyHits) {
      final e = hit.$3;
      push(UrlSuggestion(
        text: e.title.isEmpty ? e.url : e.title,
        subtitle: e.url,
        url: e.url,
        kind: SuggestionKind.history,
      ));
    }

    return out;
  }

  /// 匹配打分：0 表示不匹配；3=标题完全匹配，2=标题前缀，1=包含
  static int _matchScore(String title, String url, String lowerQuery) {
    if (lowerQuery.isEmpty) return 0;
    final t = title.toLowerCase();
    final u = url.toLowerCase();
    if (t == lowerQuery) return 3;
    if (t.startsWith(lowerQuery)) return 2;
    if (t.contains(lowerQuery)) return 1;
    if (u.contains(lowerQuery)) return 1;
    return 0;
  }
}
