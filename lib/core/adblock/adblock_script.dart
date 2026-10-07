/// 广告拦截注入脚本生成器。
///
/// 生成一个 IIFE，在 documentStart 注入页面：
/// 1. 拦截 fetch / XMLHttpRequest 中命中广告域名后缀的请求（reject / abort）；
/// 2. 隐藏并移除命中广告选择器的元素（初始 + MutationObserver 节流清理）；
/// 3. 移除 src 命中广告域名的 <script> / <iframe> 节点。
///
/// 全部规则在生成脚本时以 JSON 内联，避免运行时查询宿主，注入零依赖。
library;

class AdBlocker {
  /// 生成注入脚本。domain 均为小写主域；allow 优先于 block。
  static String buildScript({
    required List<String> domains,
    required List<String> allow,
    required List<String> selectors,
  }) {
    final domJson = _json(domains);
    final allowJson = _json(allow);
    final selJson = _json(selectors);
    // 注意：selector 需转义为 JSON 字符串数组，避免特殊字符破坏脚本
    return '''
(function () {
  if (window.__zbAdBlockLoaded) return;
  window.__zbAdBlockLoaded = true;
  var DOMAINS = $domJson;
  var ALLOW = $allowJson;
  var SELECTORS = $selJson;

  function host(url) {
    try { return new URL(url, location.href).hostname.toLowerCase(); } catch (e) { return ''; }
  }
  function inList(h, list) {
    for (var i = 0; i < list.length; i++) {
      var d = list[i];
      if (h === d || h.endsWith('.' + d)) return true;
    }
    return false;
  }
  function blocked(url) {
    var h = host(url);
    if (!h) return false;
    if (inList(h, ALLOW)) return false;
    return inList(h, DOMAINS);
  }

  // —— fetch ——
  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function (input, init) {
      var url = (typeof input === 'string') ? input : (input && input.url);
      if (blocked(url)) {
        return Promise.reject(new TypeError('Blocked by Zip Browser ad blocker'));
      }
      return origFetch.apply(this, arguments);
    };
  }

  // —— XMLHttpRequest ——
  var origOpen = XMLHttpRequest.prototype.open;
  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__zbBlocked = blocked(url);
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    if (this.__zbBlocked) {
      try { this.abort(); } catch (e) {}
      return;
    }
    return origSend.apply(this, arguments);
  };

  // —— 隐藏广告元素 ——
  function hide() {
    if (!SELECTORS.length) return;
    var sel = SELECTORS.join(',');
    var els;
    try { els = document.querySelectorAll(sel); } catch (e) { return; }
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (el && el.parentNode) { try { el.remove(); } catch (e) {} }
    }
  }
  if (document.readyState !== 'loading') { hide(); }
  else { document.addEventListener('DOMContentLoaded', hide); }

  // —— 动态插入的广告脚本 / 广告 iframe ——
  function scan() {
    var ss = document.querySelectorAll('script[src], iframe[src], img[src], embed[src], object[data]');
    for (var i = 0; i < ss.length; i++) {
      var n = ss[i];
      var u = n.src || n.data;
      if (u && blocked(u)) { try { n.remove(); } catch (e) {} }
    }
    hide();
  }
  var t = null;
  function debounced() {
    if (t) return;
    t = setTimeout(function () { t = null; scan(); }, 600);
  }
  if (window.MutationObserver) {
    new MutationObserver(debounced).observe(document.documentElement, {
      childList: true, subtree: true
    });
  }
  window.addEventListener('load', scan);
})();
''';
  }

  static String _json(List<String> list) =>
      '[${list.map((e) => '"${e.replaceAll('"', r'\"')}"').join(',')}]';
}
