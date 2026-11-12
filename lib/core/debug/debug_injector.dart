import 'dart:convert';

/// 生成注入页面的调试钩子脚本。
///
/// 钩子把 `console.*` / 未捕获异常 / `fetch` 与 `XMLHttpRequest` 的结果
/// 通过 JsBridge 的 `__internalRaw` 通道回传宿主，消息前缀 `debug:`。
/// 每页最多回传 [maxEntries] 条，避免日志刷屏拖慢页面。
class DebugInjector {
  DebugInjector._();

  static const int maxEntries = 300;

  /// [network] 为 false 时只 hook 控制台与异常（不生成网络钩子代码）
  static String buildScript({
    required String bridgeGlobalName,
    bool network = true,
  }) {
    final script = _base
        .replaceFirst('__GLOBAL__', jsonEncode(bridgeGlobalName))
        .replaceFirst('__LIMIT__', '$maxEntries');
    if (!network) return script;
    return script.replaceFirst('__NETWORK_BLOCK__', _networkBlock);
  }

  static const String _base = r'''
(function(){
  if (window.__zbDebugInstalled) return;
  window.__zbDebugInstalled = true;
  var G = __GLOBAL__;
  var limit = __LIMIT__;
  var sent = 0;

  function send(kind, message, extra){
    if (sent >= limit) return;
    sent++;
    var payload = {kind: kind, message: String(message).slice(0, 2000), t: Date.now()};
    if (extra){
      for (var k in extra){
        if (extra[k] !== undefined && extra[k] !== null) payload[k] = extra[k];
      }
    }
    try {
      window[G].__internalRaw('debug:' + JSON.stringify(payload));
    } catch (e) {}
  }

  function fmt(v){
    try {
      if (v instanceof Error) return v.stack || (v.name + ': ' + v.message);
      if (typeof v === 'string') return v;
      if (v === undefined) return 'undefined';
      if (v === null) return 'null';
      if (typeof v === 'object') return JSON.stringify(v);
      return String(v);
    } catch (e) {
      try { return String(v); } catch (e2) { return '[unserializable]'; }
    }
  }

  function joinArgs(args){
    var out = [];
    for (var i = 0; i < args.length; i++) out.push(fmt(args[i]));
    return out.join(' ');
  }

  var c = window.console || (window.console = {});
  var levels = [['log','log'],['info','info'],['warn','warn'],['error','error'],['debug','log']];
  for (var i = 0; i < levels.length; i++){
    (function(name, kind){
      var orig = c[name];
      c[name] = function(){
        try { send(kind, joinArgs(arguments)); } catch (e) {}
        if (orig) return orig.apply(c, arguments);
      };
    })(levels[i][0], levels[i][1]);
  }

  window.addEventListener('error', function(e){
    var stack = e && e.error && e.error.stack ? e.error.stack : '';
    send('exception', (e && e.message ? e.message : 'script error') + (stack ? '\n' + stack : ''));
  });

  window.addEventListener('unhandledrejection', function(e){
    send('exception', '未处理的 Promise 拒绝：' + fmt(e && e.reason));
  });

__NETWORK_BLOCK__
})();
''';

  static const String _networkBlock = r'''
  var origFetch = window.fetch;
  if (origFetch){
    window.fetch = function(){
      var args = arguments;
      var url = '', method = 'GET';
      try {
        if (typeof args[0] === 'string') url = args[0];
        else if (args[0] && args[0].url) url = String(args[0].url);
        if (args[1] && args[1].method) method = String(args[1].method).toUpperCase();
      } catch (e) {}
      var start = Date.now();
      return origFetch.apply(this, args).then(function(res){
        send('network', method + ' ' + url, {
          url: url, method: method, status: res.status,
          durationMs: Date.now() - start
        });
        return res;
      }, function(err){
        send('network', method + ' ' + url, {
          url: url, method: method, durationMs: Date.now() - start
        });
        throw err;
      });
    };
  }

  var XO = window.XMLHttpRequest;
  if (XO && XO.prototype){
    var origOpen = XO.prototype.open;
    var origSend = XO.prototype.send;
    XO.prototype.open = function(m, u){
      this.__zbMethod = m;
      this.__zbUrl = u;
      return origOpen.apply(this, arguments);
    };
    XO.prototype.send = function(){
      var self = this;
      var start = Date.now();
      this.addEventListener('loadend', function(){
        send('network', String(self.__zbMethod || 'GET') + ' ' + String(self.__zbUrl || ''), {
          url: String(self.__zbUrl || ''),
          method: String(self.__zbMethod || 'GET'),
          status: self.status || 0,
          durationMs: Date.now() - start
        });
      });
      return origSend.apply(this, arguments);
    };
  }
''';
}
