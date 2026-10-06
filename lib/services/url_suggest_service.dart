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

  /// 输入是否「看起来像一个地址」（用于决定首条建议是直达还是搜索）
  static bool looksLikeUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return false;
    if (t.contains(' ')) return false;
    const schemes = ['http://', 'https://', 'file://', 'about:', 'data:'];
    for (final s in schemes) {
      if (t.startsWith(s)) return true;
    }
    if (RegExp(r'^(localhost|127\.0\.0\.1)(:\d+)?(\/.*)?$').hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(\/.*)?$').hasMatch(t)) {
      return true;
    }
    return RegExp(r'^([\w-]+\.)+[a-z]{2,}(:\d+)?(\/.*)?$',
            caseSensitive: false)
        .hasMatch(t);
  }

  /// 生成的搜索 URL
  String searchUrl(String query) => searchTemplate().replaceFirst(
        '{q}',
        Uri.encodeQueryComponent(query),
      );

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

    // 首条：直达 或 搜索
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
    } else {
      push(UrlSuggestion(
        text: q,
        subtitle: '使用默认搜索引擎搜索',
        url: searchUrl(q),
        kind: SuggestionKind.search,
      ));
    }

    // 书签优先于历史
    final lower = q.toLowerCase();
    for (final b in bookmarks.items) {
      if (out.length >= limit) break;
      final title = b.title.toLowerCase();
      final url = b.url.toLowerCase();
      if (title.contains(lower) || url.contains(lower)) {
        push(UrlSuggestion(
          text: b.title.isEmpty ? b.url : b.title,
          subtitle: b.url,
          url: b.url,
          kind: SuggestionKind.bookmark,
        ));
      }
    }

    for (final e in history.entries) {
      if (out.length >= limit) break;
      if (lower.isEmpty) break;
      final title = e.title.toLowerCase();
      final url = e.url.toLowerCase();
      if (title.contains(lower) || url.contains(lower)) {
        push(UrlSuggestion(
          text: e.title.isEmpty ? e.url : e.title,
          subtitle: e.url,
          url: e.url,
          kind: SuggestionKind.history,
        ));
      }
    }

    return out;
  }
}
