import 'package:flutter/material.dart';

import '../../services/bookmarks_service.dart';
import '../../services/history_service.dart';

/// 内置新标签页（about:home），以 data URI 形式加载，不依赖网络资源。
///
/// 内容由三部分组成：
///   1. 搜索框（使用当前默认搜索引擎模板）
///   2. 常用站点宫格（书签优先，不足时用访问次数最多补齐）
///   3. 最近访问列表（可关闭）
class HomePage {
  static String dataUri(
    String searchEngineTemplate, {
    List<Bookmark> bookmarks = const [],
    List<HistoryEntry> recent = const [],
    int shortcutCount = 8,
    bool showRecent = true,
    Color? bgColor,
    String? bgImage,
    Color? accentColor,
  }) {
    final qIndex = searchEngineTemplate.indexOf('{q}');
    final base = qIndex >= 0
        ? searchEngineTemplate.substring(0, qIndex)
        : searchEngineTemplate;
    final suffix = qIndex >= 0 ? searchEngineTemplate.substring(qIndex + 3) : '';

    // 背景：优先图片，其次纯色，否则渐变
    final bgHex = _colorToHex(bgColor ?? const Color(0xFFEEF4FB));
    final bgStyle = bgImage != null
        ? "background: url('${_esc(bgImage)}') center/cover no-repeat, $bgHex;"
        : "background: linear-gradient(160deg, $bgHex 0%, ${_lighten(bgHex)} 100%);";

    final accentHex =
        _colorToHex(accentColor ?? const Color(0xFF0B84A5));

    // —— 常用站点：书签优先，再按访问次数补齐 ——
    final seen = <String>{};
    final shortcuts = <_Shortcut>[];
    for (final b in bookmarks) {
      if (b.url.isEmpty || !seen.add(b.url)) continue;
      shortcuts.add(_Shortcut(b.title.isEmpty ? b.url : b.title, b.url));
      if (shortcuts.length >= shortcutCount) break;
    }
    if (shortcuts.length < shortcutCount) {
      final byVisits = [...recent]
        ..sort((a, b) => b.visits.compareTo(a.visits));
      for (final e in byVisits) {
        if (e.url.isEmpty || !seen.add(e.url)) continue;
        shortcuts.add(_Shortcut(e.title.isEmpty ? e.url : e.title, e.url));
        if (shortcuts.length >= shortcutCount) break;
      }
    }

    final shortcutHtml = shortcuts.map((s) {
      final letter = s.title.isNotEmpty ? s.title[0].toUpperCase() : '?';
      return '<a class="sc" href="${_esc(s.url)}">'
          '<div class="ico">${_esc(letter)}</div>'
          '<span>${_esc(s.title)}</span></a>';
    }).join();

    // —— 最近访问（最多 6 条） ——
    final recentList = recent.take(6).toList();
    final recentHtml = showRecent && recentList.isNotEmpty
        ? '''
  <div class="recent">
    <div class="rt">最近访问</div>
    ${recentList.map((e) {
          final host = Uri.tryParse(e.url)?.host ?? '';
          return '<a class="ri" href="${_esc(e.url)}">'
              '<span class="rn">${_esc(e.title.isEmpty ? e.url : e.title)}</span>'
              '<span class="rh">${_esc(host)}</span></a>';
        }).join()}
  </div>'''
        : '';

    final html = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>新标签页</title>
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; }
  body {
    font-family: -apple-system, "Segoe UI", "Microsoft YaHei", Roboto, sans-serif;
    $bgStyle
    min-height: 100vh;
    display: flex; flex-direction: column;
    align-items: center; justify-content: flex-start;
    color: #1f2d3d; padding: 46px 0 40px;
  }
  h1 { font-size: 34px; margin: 0 0 24px; font-weight: 700; letter-spacing: 2px; color: #1f2d3d; text-shadow: 0 1px 2px rgba(255,255,255,.4); }
  h1 span { color: $accentHex; }
  form { width: min(560px, 86vw); }
  .box {
    display: flex; background: rgba(255,255,255,.92); backdrop-filter: blur(8px);
    border-radius: 999px;
    box-shadow: 0 8px 30px rgba(16, 60, 90, .12);
    overflow: hidden; border: 1px solid rgba(255,255,255,.6);
  }
  input {
    flex: 1; border: 0; outline: 0; padding: 15px 22px;
    font-size: 16px; background: transparent; color: #1f2d3d;
  }
  button {
    border: 0; padding: 0 26px; background: $accentHex; color: #fff;
    font-size: 15px; cursor: pointer; transition: opacity .2s;
  }
  button:hover { opacity: .88; }
  .shortcuts {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(80px, 1fr));
    gap: 18px; width: min(560px, 86vw);
    margin-top: 32px;
  }
  .sc {
    display: flex; flex-direction: column; align-items: center;
    text-decoration: none; color: #33475b;
  }
  .ico {
    width: 48px; height: 48px; border-radius: 14px; background: rgba(255,255,255,.92);
    display: flex; align-items: center; justify-content: center;
    font-size: 20px; font-weight: 600; color: $accentHex;
    box-shadow: 0 4px 12px rgba(16, 60, 90, .1);
  }
  .sc span {
    margin-top: 7px; font-size: 12px; max-width: 76px;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    color: #1f2d3d;
  }
  .recent {
    width: min(560px, 86vw); margin-top: 30px;
    background: rgba(255,255,255,.78); backdrop-filter: blur(6px);
    border-radius: 14px; padding: 12px 6px;
    box-shadow: 0 6px 22px rgba(16, 60, 90, .08);
  }
  .rt { font-size: 12px; font-weight: 700; color: #5a7184; padding: 2px 12px 8px; }
  .ri {
    display: flex; align-items: center; gap: 10px;
    padding: 7px 12px; border-radius: 8px; text-decoration: none; color: #1f2d3d;
  }
  .ri:hover { background: rgba(11,132,165,.08); }
  .rn { flex: 1; font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .rh { font-size: 11.5px; color: #8496a6; }
  p.tip { margin-top: 26px; font-size: 12.5px; color: #5a7184; }
</style>
</head>
<body>
  <h1>Zip<span>Browser</span></h1>
  <form id="f">
    <div class="box">
      <input id="q" autofocus placeholder="搜索或输入网址" autocomplete="off">
      <button type="submit">搜索</button>
    </div>
  </form>
  <div class="shortcuts">$shortcutHtml</div>
  $recentHtml
  <p class="tip">内核以独立安装包提供 · 应用内「内核管理」可安装与切换</p>
<script>
  var BASE = ${_jsString(base)};
  var SUFFIX = ${_jsString(suffix)};
  document.getElementById('f').addEventListener('submit', function (e) {
    e.preventDefault();
    var q = document.getElementById('q').value.trim();
    if (q) location.href = BASE + encodeURIComponent(q) + SUFFIX;
  });
</script>
</body>
</html>
''';
    return 'data:text/html;charset=utf-8,${Uri.encodeComponent(html)}';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _jsString(String s) {
    final escaped = s
        .replaceAll(r'\\', r'\\\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', '');
    return "'$escaped'";
  }

  static String _colorToHex(Color c) {
    return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  /// 生成比背景稍亮的渐变色（简单叠加白色）
  static String _lighten(String hex) {
    try {
      final r = int.parse(hex.substring(1, 3), radix: 16);
      final g = int.parse(hex.substring(3, 5), radix: 16);
      final b = int.parse(hex.substring(5, 7), radix: 16);
      final nr = (r + 30).clamp(0, 255);
      final ng = (g + 30).clamp(0, 255);
      final nb = (b + 30).clamp(0, 255);
      return '#${nr.toRadixString(16).padLeft(2, '0')}'
          '${ng.toRadixString(16).padLeft(2, '0')}'
          '${nb.toRadixString(16).padLeft(2, '0')}';
    } catch (_) {
      return hex;
    }
  }
}

class _Shortcut {
  final String title;
  final String url;
  const _Shortcut(this.title, this.url);
}
