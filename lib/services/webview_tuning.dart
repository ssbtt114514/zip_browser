import '../core/kernel/kernel_types.dart';

/// 网页访问优化：DNS 预取 / 预连接 / 首屏资源优先级提示。
///
/// 全部以 documentStart 用户脚本注入；脚本自身带幂等标记，
/// 多次调用不会重复添加 link 标签。整体由设置开关控制。
class WebViewTuning {
  WebViewTuning._();

  /// 预取并预连接页面自身与主要第三方资源域名
  static UserScript preconnectScript() => UserScript(
        timing: UserScriptInjectionTiming.documentStart,
        matches: const ['*'],
        source: _preconnect,
      );

  /// 首屏图片 `fetchpriority=high`，首屏外图片延迟加载
  static UserScript priorityHintScript() => UserScript(
        timing: UserScriptInjectionTiming.documentStart,
        matches: const ['*'],
        source: _priorityHints,
      );

  static const String _preconnect = r'''
(function(){
  if (window.__zbTuningInstalled) return;
  window.__zbTuningInstalled = true;
  var added = {};
  function add(rel, href){
    if (!href || added[rel + '|' + href]) return;
    added[rel + '|' + href] = 1;
    try {
      var l = document.createElement('link');
      l.rel = rel;
      l.href = href;
      (document.head || document.documentElement).appendChild(l);
    } catch (e) {}
  }
  try {
    add('dns-prefetch', '//' + location.host);
    add('preconnect', location.origin);
  } catch (e) {}
  function scan(){
    try {
      var els = document.querySelectorAll('link[href],script[src],img[src],iframe[src]');
      var count = 0;
      for (var i = 0; i < els.length && count < 6; i++){
        var u = els[i].href || els[i].src;
        if (!u || u.indexOf('http') !== 0) continue;
        var origin = u.split('/').slice(0, 3).join('/');
        if (origin === location.origin) continue;
        add('preconnect', origin);
        count++;
      }
    } catch (e) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan);
  } else {
    scan();
  }
})();
''';

  static const String _priorityHints = r'''
(function(){
  if (window.__zbHintInstalled) return;
  window.__zbHintInstalled = true;
  var done = false;
  function hint(){
    if (done) return;
    done = true;
    try {
      var imgs = document.images || [];
      var highSet = false;
      for (var i = 0; i < imgs.length; i++){
        var img = imgs[i];
        var rect = img.getBoundingClientRect();
        if (!highSet && rect.top < innerHeight * 1.2 && rect.width > 32){
          img.setAttribute('fetchpriority', 'high');
          highSet = true;
        } else if (rect.top >= innerHeight * 1.5 &&
            !img.hasAttribute('loading')) {
          img.setAttribute('loading', 'lazy');
        }
      }
      var links = document.querySelectorAll('link[rel="stylesheet"][href]');
      if (links.length > 0) links[0].setAttribute('fetchpriority', 'high');
    } catch (e) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hint);
  } else {
    hint();
  }
})();
''';
}
