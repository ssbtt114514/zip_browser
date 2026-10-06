import 'dart:ui' show Color;

import '../../services/bookmarks_service.dart';
import '../../services/history_service.dart';

/// 内置新标签页（about:home），以 data URI 形式加载，不依赖任何网络资源。
///
/// 重新设计后的视觉结构：
///   1. 品牌头部（图形标记 + 名称）
///   2. 搜索卡片（大圆角、聚焦态高亮、阴影分层）
///   3. 常用站点宫格（书签优先、访问次数补齐；字母头像按域名哈希取色）
///   4. 最近访问卡片列表
///   5. 页脚（内核与插件提示）
///
/// 同时支持浅色 / 深色两套配色（由宿主主题决定）。
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
    bool dark = false,
  }) {
    final qIndex = searchEngineTemplate.indexOf('{q}');
    final base = qIndex >= 0
        ? searchEngineTemplate.substring(0, qIndex)
        : searchEngineTemplate;
    final suffix = qIndex >= 0 ? searchEngineTemplate.substring(qIndex + 3) : '';

    final accentHex = _colorToHex(accentColor ?? const Color(0xFF0B84A5));
    final bgHex = _colorToHex(
        bgColor ?? (dark ? const Color(0xFF14171C) : const Color(0xFFEEF4FB)));

    // 背景：优先图片，其次纯色渐变
    final bgStyle = bgImage != null
        ? "background: url('${_esc(bgImage)}') center/cover no-repeat, $bgHex;"
        : (dark
            ? "background: radial-gradient(1200px 600px at 50% -10%, ${_mix(bgHex, accentHex, 0.16)} 0%, $bgHex 62%);"
            : "background: radial-gradient(1200px 600px at 50% -10%, ${_mix(bgHex, accentHex, 0.14)} 0%, $bgHex 62%);");

    // —— 常用站点：书签优先，再按访问次数补齐 ——
    final seen = <String>{};
    final shortcuts = <_Shortcut>[];
    for (final b in bookmarks) {
      if (b.url.isEmpty || !seen.add(b.url)) continue;
      shortcuts.add(_Shortcut(b.title.isEmpty ? b.url : b.title, b.url));
      if (shortcuts.length >= shortcutCount) break;
    }
    if (shortcuts.length < shortcutCount) {
      final byVisits = [...recent]..sort((a, b) => b.visits.compareTo(a.visits));
      for (final e in byVisits) {
        if (e.url.isEmpty || !seen.add(e.url)) continue;
        shortcuts.add(_Shortcut(e.title.isEmpty ? e.url : e.title, e.url));
        if (shortcuts.length >= shortcutCount) break;
      }
    }

    final shortcutHtml = shortcuts.asMap().entries.map((entry) {
      final i = entry.key;
      final s = entry.value;
      final host = Uri.tryParse(s.url)?.host ?? s.url;
      final hue = _hueOf(host);
      final letter = _initial(s.title);
      return '<a class="sc" href="${_esc(s.url)}" style="--d:${i * 26}ms">'
          '<span class="ico" style="--h:$hue">${_esc(letter)}</span>'
          '<span class="sc-t">${_esc(s.title)}</span></a>';
    }).join();

    // —— 最近访问（最多 6 条） ——
    final recentList = recent.take(6).toList();
    final recentHtml = showRecent && recentList.isNotEmpty
        ? '''
  <section class="card recent">
    <div class="card-h"><span>最近访问</span><span class="muted">${recentList.length} 条</span></div>
    ${recentList.asMap().entries.map((entry) {
          final i = entry.key;
          final e = entry.value;
          final host = Uri.tryParse(e.url)?.host ?? '';
          final hue = _hueOf(host);
          return '<a class="ri" href="${_esc(e.url)}" style="--d:${i * 22}ms">'
              '<span class="dot" style="--h:$hue"></span>'
              '<span class="rn">${_esc(e.title.isEmpty ? e.url : e.title)}</span>'
              '<span class="rh">${_esc(host)}</span></a>';
        }).join()}
  </section>'''
        : '';

    final emptyShortcuts = shortcuts.isEmpty
        ? '<p class="empty">还没有常用站点：浏览网页时点击地址栏的 ★ 添加书签，这里会自动出现快捷入口。</p>'
        : '';

    final html = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="${dark ? 'dark' : 'light'}">
<title>新标签页</title>
<style>
  :root {
    --accent: $accentHex;
    --fg: ${dark ? '#E7EAF0' : '#16212E'};
    --fg-soft: ${dark ? '#A7B0BE' : '#4C5D6E'};
    --fg-faint: ${dark ? '#727C8C' : '#8496A6'};
    --card: ${dark ? 'rgba(30,34,41,.86)' : 'rgba(255,255,255,.86)'};
    --card-solid: ${dark ? '#1E2229' : '#FFFFFF'};
    --line: ${dark ? 'rgba(255,255,255,.10)' : 'rgba(16,60,90,.10)'};
    --shadow: ${dark
        ? '0 18px 44px rgba(0,0,0,.46)'
        : '0 18px 44px rgba(16,60,90,.13)'};
    --shadow-sm: ${dark
        ? '0 6px 18px rgba(0,0,0,.36)'
        : '0 6px 18px rgba(16,60,90,.10)'};
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI",
                 "Microsoft YaHei", "PingFang SC", Roboto, sans-serif;
    $bgStyle
    background-attachment: fixed;
    min-height: 100vh;
    color: var(--fg);
    display: flex; flex-direction: column; align-items: center;
    padding: 0 20px 44px;
    -webkit-font-smoothing: antialiased;
  }
  .wrap { width: min(720px, 100%); }

  /* —— 品牌头部 —— */
  header {
    display: flex; align-items: center; justify-content: center; gap: 11px;
    padding: 54px 0 26px;
    animation: rise .5s cubic-bezier(.2,.7,.3,1) both;
  }
  .mark {
    width: 38px; height: 38px; border-radius: 12px;
    background: linear-gradient(140deg, var(--accent), ${_shift(accentHex, -26)});
    box-shadow: var(--shadow-sm);
    display: flex; align-items: center; justify-content: center;
    color: #fff; font-weight: 800; font-size: 19px; letter-spacing: -.5px;
  }
  .brand { font-size: 21px; font-weight: 700; letter-spacing: .2px; }
  .brand em { font-style: normal; color: var(--accent); }

  /* —— 搜索卡片 —— */
  form { margin: 0 0 30px; animation: rise .5s .06s cubic-bezier(.2,.7,.3,1) both; }
  .search {
    display: flex; align-items: center; gap: 10px;
    background: var(--card); backdrop-filter: blur(14px);
    border: 1px solid var(--line);
    border-radius: 18px; padding: 7px 7px 7px 18px;
    box-shadow: var(--shadow);
    transition: border-color .18s, box-shadow .18s, transform .18s;
  }
  .search:focus-within {
    border-color: var(--accent);
    box-shadow: var(--shadow), 0 0 0 4px ${_alpha(accentHex, 0.16)};
  }
  .search svg { flex: none; color: var(--fg-faint); }
  input {
    flex: 1; min-width: 0; border: 0; outline: 0; background: transparent;
    padding: 11px 0; font-size: 16px; color: var(--fg);
    font-family: inherit;
  }
  input::placeholder { color: var(--fg-faint); }
  button {
    flex: none; border: 0; border-radius: 13px; cursor: pointer;
    padding: 11px 22px; font-size: 14.5px; font-weight: 600;
    font-family: inherit; color: #fff; background: var(--accent);
    transition: filter .18s, transform .12s;
  }
  button:hover { filter: brightness(1.07); }
  button:active { transform: scale(.97); }

  /* —— 卡片通用 —— */
  .card {
    background: var(--card); backdrop-filter: blur(14px);
    border: 1px solid var(--line);
    border-radius: 18px; box-shadow: var(--shadow-sm);
    padding: 8px;
    animation: rise .5s .12s cubic-bezier(.2,.7,.3,1) both;
  }
  .card-h {
    display: flex; align-items: center; justify-content: space-between;
    padding: 9px 12px 11px;
    font-size: 12px; font-weight: 700; letter-spacing: .5px;
    color: var(--accent); text-transform: none;
  }
  .muted { color: var(--fg-faint); font-weight: 500; letter-spacing: 0; }

  /* —— 快捷入口宫格 —— */
  .shortcuts {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
    gap: 6px 4px; padding: 4px 4px 6px;
  }
  .sc {
    display: flex; flex-direction: column; align-items: center; gap: 8px;
    padding: 12px 6px; border-radius: 14px;
    text-decoration: none; color: var(--fg);
    transition: background .16s, transform .16s;
    animation: rise .44s var(--d, 0ms) cubic-bezier(.2,.7,.3,1) both;
  }
  .sc:hover { background: ${_alpha(accentHex, 0.09)}; transform: translateY(-2px); }
  .ico {
    width: 46px; height: 46px; border-radius: 15px;
    display: flex; align-items: center; justify-content: center;
    font-size: 19px; font-weight: 700;
    background: hsl(var(--h) 68% ${dark ? '22%' : '93%'});
    color: hsl(var(--h) 62% ${dark ? '74%' : '36%'});
    border: 1px solid ${_alpha(accentHex, dark ? 0.06 : 0.05)};
  }
  .sc-t {
    font-size: 12px; max-width: 88px; text-align: center;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    color: var(--fg-soft);
  }

  /* —— 最近访问 —— */
  .recent { margin-top: 14px; animation-delay: .18s; }
  .ri {
    display: flex; align-items: center; gap: 11px;
    padding: 10px 12px; border-radius: 12px;
    text-decoration: none; color: var(--fg);
    animation: rise .4s var(--d, 0ms) cubic-bezier(.2,.7,.3,1) both;
    animation-delay: calc(180ms + var(--d, 0ms));
  }
  .ri:hover { background: ${_alpha(accentHex, 0.08)}; }
  .dot {
    flex: none; width: 9px; height: 9px; border-radius: 50%;
    background: hsl(var(--h) 66% ${dark ? '60%' : '52%'});
  }
  .rn {
    flex: 1; min-width: 0; font-size: 13.5px;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .rh { flex: none; font-size: 11.5px; color: var(--fg-faint); }

  .empty {
    margin: 6px 4px 10px; font-size: 12.5px; line-height: 1.7;
    color: var(--fg-faint); text-align: center;
  }
  footer {
    margin-top: 30px; text-align: center;
    font-size: 11.5px; line-height: 1.8; color: var(--fg-faint);
    animation: rise .5s .24s cubic-bezier(.2,.7,.3,1) both;
  }
  footer kbd {
    font-family: inherit; font-size: 11px;
    background: ${_alpha(accentHex, dark ? 0.18 : 0.10)};
    color: var(--accent);
    border-radius: 5px; padding: 1px 5px;
  }
  @keyframes rise {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: none; }
  }
  @media (prefers-reduced-motion: reduce) {
    * { animation: none !important; transition: none !important; }
  }
</style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="mark">Z</div>
      <div class="brand">Zip<em>Browser</em></div>
    </header>

    <form id="f">
      <div class="search">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
             stroke="currentColor" stroke-width="2.1" stroke-linecap="round">
          <circle cx="11" cy="11" r="7"></circle>
          <line x1="16.5" y1="16.5" x2="21" y2="21"></line>
        </svg>
        <input id="q" autofocus placeholder="搜索或输入网址" autocomplete="off"
               spellcheck="false">
        <button type="submit">搜索</button>
      </div>
    </form>

    <section class="card">
      <div class="card-h"><span>常用站点</span>
        <span class="muted">书签优先</span></div>
      <div class="shortcuts">$shortcutHtml</div>
      $emptyShortcuts
    </section>

    $recentHtml

    <footer>
      按 <kbd>Ctrl</kbd>+<kbd>T</kbd> 新建标签 ·
      <kbd>Ctrl</kbd>+<kbd>L</kbd> 聚焦地址栏 ·
      <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd> 恢复关闭的标签<br>
      内核与插件均可在应用内「内核管理 / 插件管理」中热插拔
    </footer>
  </div>
<script>
  var BASE = ${_jsString(base)};
  var SUFFIX = ${_jsString(suffix)};
  var input = document.getElementById('q');
  document.getElementById('f').addEventListener('submit', function (e) {
    e.preventDefault();
    var q = input.value.trim();
    if (!q) return;
    // 看起来像地址就直接跳转，否则交给搜索引擎
    if (/^(https?:\\/\\/|file:\\/\\/)/i.test(q)) { location.href = q; return; }
    if (!/\\s/.test(q) && /^[\\w-]+(\\.[\\w-]+)+([\\/?#].*)?\$/.test(q)) {
      location.href = 'https://' + q; return;
    }
    location.href = BASE + encodeURIComponent(q) + SUFFIX;
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement !== input) {
      e.preventDefault(); input.focus();
    }
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

  /// 首字母（CJK 取首字，其它取首个字母并大写）
  static String _initial(String title) {
    final t = title.trim();
    if (t.isEmpty) return '?';
    final rune = t.runes.first;
    final ch = String.fromCharCode(rune);
    if (RegExp(r'[a-zA-Z]').hasMatch(ch)) return ch.toUpperCase();
    if (RegExp(r'[0-9]').hasMatch(ch)) return ch;
    return ch;
  }

  /// 由域名推导稳定的色相（0-359），保证同一站点每次颜色一致
  static int _hueOf(String host) {
    if (host.isEmpty) return 205;
    var hash = 0;
    for (final code in host.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash % 360;
  }

  static String _colorToHex(Color c) {
    return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  static List<int> _rgb(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length < 6) return const [0, 0, 0];
    return [
      int.parse(h.substring(0, 2), radix: 16),
      int.parse(h.substring(2, 4), radix: 16),
      int.parse(h.substring(4, 6), radix: 16),
    ];
  }

  static String _toHex(List<int> rgb) => '#${rgb.map((v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join()}';

  /// 两色线性混合，[t] 为 [b] 的占比
  static String _mix(String a, String b, double t) {
    final ra = _rgb(a);
    final rb = _rgb(b);
    return _toHex([
      (ra[0] * (1 - t) + rb[0] * t).round(),
      (ra[1] * (1 - t) + rb[1] * t).round(),
      (ra[2] * (1 - t) + rb[2] * t).round(),
    ]);
  }

  /// 亮度偏移（负值变暗）
  static String _shift(String hex, int delta) {
    final rgb = _rgb(hex);
    return _toHex(rgb.map((v) => v + delta).toList());
  }

  /// rgba() 字符串
  static String _alpha(String hex, double alpha) {
    final rgb = _rgb(hex);
    return 'rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${alpha.toStringAsFixed(3)})';
  }

  /// 比背景稍亮的渐变色（保留旧接口，供外部调用）
  static String lighten(String hex) {
    try {
      return _shift(hex, 30);
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
