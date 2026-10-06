/// 资源嗅探器：生成注入页面的 JS，扫描 DOM 媒体元素并 hook fetch/XHR。
/// 发现的资源通过 `window.<global>.__internalRaw('sniff:...')` 上报。
class ResourceSniffer {
  /// 生成注入脚本（documentEnd 注入）
  static String buildScript(String globalName) {
    return '''
(function () {
  var G = ${_jsString(globalName)};
  var reported = {};

  function send(list) {
    if (!list.length) return;
    try {
      window[G].__internalRaw('sniff:' + JSON.stringify(list));
    } catch (e) {}
  }

  function classify(url, mime) {
    if (mime && mime.indexOf('video') === 0) return 'video';
    if (mime && mime.indexOf('audio') === 0) return 'audio';
    if (mime && mime.indexOf('image') === 0) return 'image';
    if (mime && mime.indexOf('css') >= 0) return 'css';
    if (mime && mime.indexOf('javascript') >= 0) return 'js';
    if (mime && mime.indexOf('font') >= 0) return 'font';
    var p = url.split('?')[0].split('#')[0].toLowerCase();
    if (/\\.(mp4|webm|ogv|m3u8|ts|flv|mov|mkv|avi)(\\?|#|\$)/.test(p)) return 'video';
    if (/\\.(mp3|wav|flac|ogg|m4a|aac)(\\?|#|\$)/.test(p)) return 'audio';
    if (/\\.(jpg|jpeg|png|gif|webp|svg|bmp)(\\?|#|\$)/.test(p)) return 'image';
    if (/\\.css(\\?|#|\$)/.test(p)) return 'css';
    if (/\\.js(\\?|#|\$)/.test(p)) return 'js';
    if (/\\.(woff2?|ttf|otf|eot)(\\?|#|\$)/.test(p)) return 'font';
    return 'other';
  }

  function push(url, type, mime, size, title) {
    if (!url || reported[url]) return;
    reported[url] = true;
    send([{ url: url, type: type, mime: mime || null, size: size || null, title: title || null }]);
  }

  function scanDom() {
    try {
      var list = [];
      var vids = document.querySelectorAll('video, source');
      vids.forEach(function (el) {
        var src = el.src || (el.querySelector && el.querySelector('source') && el.querySelector('source').src);
        if (src) list.push({ url: src, type: 'video', mime: el.type || null, title: el.title || null });
      });
      var auds = document.querySelectorAll('audio');
      auds.forEach(function (el) {
        var src = el.src || (el.querySelector && el.querySelector('source') && el.querySelector('source').src);
        if (src) list.push({ url: src, type: 'audio', mime: el.type || null, title: el.title || null });
      });
      var imgs = document.querySelectorAll('img');
      imgs.forEach(function (el) {
        if (el.src && el.naturalWidth > 50) list.push({ url: el.src, type: 'image', title: el.alt || el.title || null });
      });
      var links = document.querySelectorAll('link[rel="stylesheet"]');
      links.forEach(function (el) { if (el.href) list.push({ url: el.href, type: 'css' }); });
      var scripts = document.querySelectorAll('script[src]');
      scripts.forEach(function (el) { if (el.src) list.push({ url: el.src, type: 'js' }); });

      var fresh = list.filter(function (r) { return !reported[r.url]; });
      fresh.forEach(function (r) { reported[r.url] = true; });
      if (fresh.length) send(fresh);
    } catch (e) {}
  }

  // hook fetch
  try {
    var origFetch = window.fetch;
    if (origFetch) {
      window.fetch = function () {
        var url = typeof arguments[0] === 'string' ? arguments[0] : (arguments[0] && arguments[0].url);
        if (url) {
          var type = classify(url, null);
          if (type !== 'other') push(url, type, null, null, null);
        }
        return origFetch.apply(this, arguments);
      };
    }
  } catch (e) {}

  // hook XHR
  try {
    var OrigOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      this.__sniffUrl = url;
      return OrigOpen.apply(this, arguments);
    };
    var OrigSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function () {
      var url = this.__sniffUrl;
      if (url) {
        var type = classify(url, null);
        if (type !== 'other') push(url, type, null, null, null);
      }
      return OrigSend.apply(this, arguments);
    };
  } catch (e) {}

  // 初次扫描 + 定时扫描（捕获动态加载的资源）
  scanDom();
  var count = 0;
  var timer = setInterval(function () {
    scanDom();
    if (++count > 20) clearInterval(timer);
  }, 1500);
})();
''';
  }

  static String _jsString(String s) {
    final escaped = s
        .replaceAll(r'\\', r'\\\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', '');
    return "'$escaped'";
  }
}
