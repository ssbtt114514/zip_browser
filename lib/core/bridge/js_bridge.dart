import 'dart:async';
import 'dart:convert';

/// 页面 / content-script 发起的 bridge 调用
class BridgeRequest {
  final int id;
  final String method;
  final dynamic params;

  /// 调用来源插件 id（页面自身发起为 null）
  final String? pluginId;

  const BridgeRequest({
    required this.id,
    required this.method,
    this.params,
    this.pluginId,
  });

  Map<String, dynamic> get paramsMap {
    if (params is Map) return Map<String, dynamic>.from(params as Map);
    return <String, dynamic>{};
  }
}

/// bridge 处理结果
class BridgeResult {
  final dynamic result;
  final String? error;

  const BridgeResult._(this.result, this.error);

  factory BridgeResult.ok([dynamic result]) => BridgeResult._(result, null);
  factory BridgeResult.fail(String message) => BridgeResult._(null, message);

  Map<String, dynamic> toJson() => {
        if (error == null) 'result': result else 'error': error,
      };
}

typedef BridgeHandler = Future<BridgeResult> Function(BridgeRequest request);

/// JS <-> Dart 通信中枢。
///
/// 页面侧通过 `window.<globalName>.call(method, params)` 发起 Promise 调用；
/// 宿主侧通过 [register] 注册处理函数。
/// 不同内核（Android JavaScriptChannel / Windows WebView2 webMessage）
/// 只负责把原始字符串送入 [handleRaw]，并把 [buildResponseScript]
/// 的返回值执行回页面即可。
class JsBridgeHub {
  /// 暴露给页面的全局对象名
  final String globalName;

  /// 允许调用的方法白名单（空 = 不允许任何调用）
  final Set<String> allowedMethods;

  /// 调用来源插件 id（content script 场景）
  final String? pluginId;

  final Map<String, BridgeHandler> _handlers = {};

  JsBridgeHub({
    this.globalName = 'zipBrowser',
    this.allowedMethods = const <String>{},
    this.pluginId,
  });

  /// 注册宿主能力，例如 `tabs.create`、`storage.get`、`nativeMessaging.send`
  void register(String method, BridgeHandler handler) {
    _handlers[method] = handler;
  }

  void registerAll(Map<String, BridgeHandler> handlers) {
    _handlers.addAll(handlers);
  }

  /// 注入到每个框架页面的引导脚本（documentStart 注入）。
  String bootstrapScript() {
    final g = jsonEncode(globalName);
    return '''
(function () {
  var G = $g;
  var root = window;
  if (root[G] && root[G].__installed) return;
  var pending = {};
  var seq = 1;
  var listeners = {};
  var queue = [];

  function host() {
    // Android：JavaScriptChannel 会注入同名对象
    if (root[G + '__host'] && root[G + '__host'].postMessage) return root[G + '__host'];
    // Windows：WebView2 内置 chrome.webview
    if (root.chrome && root.chrome.webview && root.chrome.webview.postMessage) return root.chrome.webview;
    return null;
  }
  function send(raw) {
    var h = host();
    if (h) h.postMessage(raw); else queue.push(raw);
  }
  setInterval(function () {
    if (queue.length) { var h = host(); while (h && queue.length) { h.postMessage(queue.shift()); } }
  }, 100);

  root[G] = {
    __installed: true,
    call: function (method, params) {
      return new Promise(function (resolve, reject) {
        var id = seq++;
        pending[id] = { resolve: resolve, reject: reject };
        send(JSON.stringify({ id: id, method: method, params: params || {} }));
      });
    },
    // 宿主内置能力（不经过插件权限白名单）
    __internalRaw: function (payload) {
      send(JSON.stringify({ scope: 'internal', payload: payload }));
    },
    on: function (event, cb) {
      (listeners[event] = listeners[event] || []).push(cb);
    },
    __respond: function (msg) {
      var m = typeof msg === 'string' ? JSON.parse(msg) : msg;
      var p = pending[m.id];
      if (!p) return;
      delete pending[m.id];
      if (m.error) p.reject(new Error(m.error)); else p.resolve(m.result);
    },
    __emit: function (msg) {
      var m = typeof msg === 'string' ? JSON.parse(msg) : msg;
      (listeners[m.event] || []).forEach(function (cb) {
        try { cb(m.data); } catch (e) {}
      });
    }
  };

  // 长按 / 右键：捕获链接、图片、选区，交给宿主菜单
  document.addEventListener('contextmenu', function (e) {
    try {
      var node = e.target;
      var link = null, img = null, sel = '';
      var el = node;
      while (el && el.nodeType === 1) {
        if (!link && el.tagName === 'A' && el.href) link = el.href;
        el = el.parentNode;
      }
      if (node.nodeType === 1 && node.tagName === 'IMG' && node.src) img = node.src;
      if (window.getSelection) sel = String(window.getSelection());
      var info = {
        pageUrl: location.href,
        linkUrl: link,
        imageUrl: img,
        selectedText: sel
      };
      root[G].__internalRaw('contextMenu:' + JSON.stringify(info));
      e.preventDefault();
    } catch (err) {}
  }, true);

  // 下载链接：拦截点击，交给宿主下载（跨平台一致）
  document.addEventListener('click', function (e) {
    try {
      var a = e.target;
      while (a && a.nodeType === 1 && a.tagName !== 'A') a = a.parentNode;
      if (!a || a.tagName !== 'A') return;
      var href = a.href || '';
      if (!href) return;
      if (/\\.(zip|rar|7z|tar|gz|apk|exe|msi|dmg|iso|bin|deb|rpm|jar|crx|whl|pdf|docx?|xlsx?|pptx?|mp3|mp4|avi|mkv|flac|wav)(\\?|#|\$)/i.test(href)) {
        e.preventDefault();
        e.stopPropagation();
        root[G].__internalRaw('download:' + href);
      }
      // 用户脚本链接：自动识别 .user.js
      if (/\\.user\\.js(\\?|#|\$)/i.test(href) ||
          /greasyfork\\.org|openuserjs\\.org|sleazyfork\\.org/i.test(href)) {
        root[G].__internalRaw('userscript:' + href);
      }
    } catch (err) {}
  }, true);

  // 页面加载后扫描 .user.js 链接并上报（用于地址栏提示安装）
  function __scanUserscripts() {
    try {
      var links = document.querySelectorAll('a[href]');
      var found = [];
      for (var i = 0; i < links.length; i++) {
        var href = links[i].href || '';
        if (/\\.user\\.js(\\?|#|\$)/i.test(href)) {
          found.push(href);
        }
      }
      if (found.length) {
        root[G].__internalRaw('userscriptList:' + JSON.stringify(found));
      }
    } catch (err) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', __scanUserscripts);
  } else {
    __scanUserscripts();
  }
})();
''';
  }

  /// 处理内核转发来的原始消息，返回需要执行回页面的脚本；
  /// 无返回值（异常/未授权）时返回 null。
  Future<String?> handleRaw(String raw) async {
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      msg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }

    final id = msg['id'];
    final method = msg['method'];
    if (id is! int || method is! String) return null;

    if (!allowedMethods.contains(method)) {
      return buildResponseScript(
        id,
        BridgeResult.fail('permission denied: $method'),
      );
    }

    final handler = _handlers[method];
    if (handler == null) {
      return buildResponseScript(
        id,
        BridgeResult.fail('no handler: $method'),
      );
    }

    try {
      final result = await handler(BridgeRequest(
        id: id,
        method: method,
        params: msg['params'],
        pluginId: pluginId,
      ));
      return buildResponseScript(id, result);
    } catch (e) {
      return buildResponseScript(id, BridgeResult.fail(e.toString()));
    }
  }

  /// 构造在页面内执行的响应脚本
  String buildResponseScript(int id, BridgeResult result) {
    final payload = jsonEncode(jsonEncode({
      'id': id,
      ...result.toJson(),
    }));
    return "window[${jsonEncode(globalName)}].__respond($payload);";
  }

  /// 在宿主本地直接调用一个已注册方法（FFI 内核的 native->host 回调）
  Future<BridgeResult> invokeLocal(
    String method,
    dynamic params, {
    String? pluginId,
  }) async {
    final handler = _handlers[method];
    if (handler == null) return BridgeResult.fail('no handler: $method');
    try {
      return await handler(BridgeRequest(
        id: -1,
        method: method,
        params: params,
        pluginId: pluginId,
      ));
    } catch (e) {
      return BridgeResult.fail(e.toString());
    }
  }

  /// 构造主动向页面派发事件的脚本
  String buildEmitScript(String event, dynamic data) {
    final payload = jsonEncode(jsonEncode({'event': event, 'data': data}));
    return "window[${jsonEncode(globalName)}].__emit($payload);";
  }
}
