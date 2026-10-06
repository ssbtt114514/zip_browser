import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart';

import '../core/bridge/find_script.dart';
import '../core/bridge/internal_dispatcher.dart';
import '../core/bridge/js_bridge.dart';
import '../core/desktop_mode_config.dart';
import '../core/kernel/browser_kernel.dart';
import '../core/kernel/kernel_types.dart';
import '../core/sniff/resource_sniffer.dart';
import '../core/sniff/sniff_model.dart';

/// Windows 内核：WebView2（Edge Chromium）
///
/// * [fixedRuntimeDir] == null：使用系统 Evergreen Runtime
/// * 传入目录：使用插件携带的 WebView2 Fixed Version 固定版本内核
///   （browserExecutableFolder）
class WindowsSystemKernel implements BrowserKernel {
  /// WebView2 环境是进程级、只能初始化一次
  static bool _environmentReady = false;
  static String? _environmentBrowserExePath;

  /// 环境初始化相关警告（例如固定内核切换需要重启应用）
  static String? environmentWarning;

  final String? fixedRuntimeDir;

  WebviewController? _controller;
  List<UserScript> _scripts = const [];
  String _bridgeGlobalName = 'zipBrowser';
  late JsBridgeHub _bridge;
  final InternalDispatcher _internal = InternalDispatcher();
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _lastUrl = '';
  final List<StreamSubscription> _subs = [];

  final _nav = StreamController<NavigationEvent>.broadcast();
  final _progressC = StreamController<double>.broadcast();
  final _urlC = StreamController<String>.broadcast();
  final _titleC = StreamController<String>.broadcast();
  final _errorC = StreamController<WebResourceError>.broadcast();

  WindowsSystemKernel({this.fixedRuntimeDir});

  @override
  String get id => fixedRuntimeDir == null
      ? 'system.windows_webview2'
      : 'system.windows_webview2_fixed';

  @override
  String get displayName =>
      fixedRuntimeDir == null ? 'WebView2（Evergreen 系统内核）' : 'WebView2 Fixed Version';

  @override
  KernelOrigin get origin =>
      fixedRuntimeDir == null ? KernelOrigin.system : KernelOrigin.plugin;

  @override
  Set<KernelCapability> get capabilities => const {
        KernelCapability.loadUrl,
        KernelCapability.evaluateJs,
        KernelCapability.userScripts,
        KernelCapability.multiTab,
        KernelCapability.download,
        KernelCapability.devTools,
      };

  @override
  JsBridgeHub get bridge => _bridge;

  @override
  Future<void> initialize(KernelViewConfig config) async {
    _scripts = config.userScripts;
    _bridgeGlobalName = config.bridgeGlobalName;
    _bridge = JsBridgeHub(
      globalName: config.bridgeGlobalName,
      allowedMethods: config.allowedBridgeMethods,
    );

    // 1. 进程级环境（只初始化一次）
    if (!_environmentReady) {
      await WebviewController.initializeEnvironment(
        browserExePath: fixedRuntimeDir,
      );
      _environmentReady = true;
      _environmentBrowserExePath = fixedRuntimeDir;
    } else if (fixedRuntimeDir != null &&
        fixedRuntimeDir != _environmentBrowserExePath) {
      environmentWarning = '切换 WebView2 固定版本内核需要重启浏览器后生效';
    }

    // 2. 创建控制器
    final controller = WebviewController();
    await controller.initialize();
    _controller = controller;

    // 3. bridge 引导（documentCreated，先于页面任何脚本）
    await controller.addScriptToExecuteOnDocumentCreated(
      _bridge.bootstrapScript(),
    );
    // 3b. 页面查找器（每个文档内置）
    await controller.addScriptToExecuteOnDocumentCreated(kFindScript);

    // 3c. 资源嗅探（hook fetch/XHR + DOM 扫描，documentCreated 注入）
    await controller.addScriptToExecuteOnDocumentCreated(
      ResourceSniffer.buildScript(config.bridgeGlobalName),
    );

    // 4. content scripts（自带 matches / timing 包装）
    for (final script in _scripts) {
      await controller.addScriptToExecuteOnDocumentCreated(_wrap(script));
    }

    // 5. 事件接线
    _subs.add(controller.title.listen((t) {
      if (t.isNotEmpty) _titleC.add(t);
    }));
    _subs.add(controller.url.listen((u) {
      _lastUrl = u;
      _urlC.add(u);
    }));
    _subs.add(controller.historyChanged.listen((h) {
      _canGoBack = h.canGoBack;
      _canGoForward = h.canGoForward;
    }));
    _subs.add(controller.loadingState.listen((state) {
      if (state == LoadingState.loading) {
        _progressC.add(0);
        _nav.add(NavigationEvent(_lastUrl, NavigationStage.start));
      } else if (state == LoadingState.navigationCompleted) {
        _progressC.add(1);
        _nav.add(NavigationEvent(_lastUrl, NavigationStage.finished));
      }
    }));
    _subs.add(controller.onLoadError.listen((status) {
      _errorC.add(WebResourceError(description: status.name));
    }));
    _subs.add(controller.webMessage.listen((dynamic msg) async {
      final raw = msg is String ? msg : jsonEncode(msg);
      if (_internal.dispatch(raw)) return;
      final responseScript = await _bridge.handleRaw(raw);
      if (responseScript != null) {
        await controller.executeScript(responseScript);
      }
    }));
  }

  /// 把 content script 包装为：matches 判定 + timing 控制
  String _wrap(UserScript script) {
    final patterns = jsonEncode(script.matches);
    final matcher = '''
var __patterns = $patterns;
function __match(url){
  for (var i = 0; i < __patterns.length; i++){
    var pat = __patterns[i];
    if (pat === '*' || pat === '<all_urls>') return true;
    if (pat.indexOf('*') < 0) { if (url === pat) return true; continue; }
    var parts = pat.split('*'), pos = 0, ok = true;
    for (var j = 0; j < parts.length; j++){
      var idx = url.indexOf(parts[j], pos);
      if (idx < 0) { ok = false; break; }
      pos = idx + parts[j].length;
    }
    if (ok && pat.charAt(pat.length - 1) !== '*'){
      var last = parts[parts.length - 1];
      if (url.indexOf(last) + last.length !== url.length) ok = false;
    }
    if (ok) return true;
  }
  return false;
}
if (!__match(location.href)) return;
''';

    final String body;
    if (script.timing == UserScriptInjectionTiming.documentStart) {
      body = script.source;
    } else {
      body = '''
function __run(){
${script.source}
}
if (document.readyState === 'loading')
  document.addEventListener('DOMContentLoaded', __run);
else __run();
''';
    }
    return '(function(){\n$matcher\n$body\n})();';
  }

  @override
  Widget buildView() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Webview(controller);
  }

  @override
  Future<void> loadUrl(String url) async {
    final controller = _controller;
    if (controller == null) return;

    if (url.startsWith('data:')) {
      await controller.loadStringContent(UriData.parse(url).contentAsString());
      return;
    }
    if (url == 'about:blank') {
      await controller.loadStringContent('');
      return;
    }
    await controller.loadUrl(url);
  }

  @override
  Future<void> goBack() async => _controller?.goBack();
  @override
  Future<void> goForward() async => _controller?.goForward();
  @override
  Future<void> reload() async => _controller?.reload();
  @override
  Future<void> stopLoading() async => _controller?.stop();

  @override
  Future<bool> canGoBack() async => _canGoBack;
  @override
  Future<bool> canGoForward() async => _canGoForward;

  @override
  Future<String?> evaluateJavascript(String script) async {
    final result = await _controller?.executeScript(script);
    if (result == null) return null;
    return jsonEncode(result);
  }

  @override
  void registerBridgeHandler(String method, BridgeHandler handler) {
    _bridge.register(method, handler);
  }

  // —— 增强能力 ——

  @override
  Future<void> setJavaScriptEnabled(bool enabled) async {
    // webview_windows 0.4 未暴露 WebView2 的 IsScriptEnabled，暂不支持运行时禁用
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    // webview_windows 的 setUserAgent 需要非空字符串
    await _controller?.setUserAgent(userAgent ?? '');
  }

  @override
  Future<void> setDesktopMode(DesktopModeConfig config) async {
    final c = _controller;
    if (c == null) return;
    await c.setUserAgent(config.enabled ? config.effectiveUA : '');
    // 视口 / DPR 覆写
    if (config.enabled) {
      final sb = StringBuffer();
      if (config.viewportWidth > 0) {
        sb.writeln(
            "document.querySelectorAll('meta[name=viewport]').forEach(e=>e.remove());");
        sb.writeln(
            "var m=document.createElement('meta');m.name='viewport';"
            "m.content='width=${config.viewportWidth},initial-scale=1';"
            "document.head&&document.head.appendChild(m);");
      }
      if (config.devicePixelRatio > 0) {
        sb.writeln("try{Object.defineProperty(window,'devicePixelRatio',"
            "{get:function(){return ${config.devicePixelRatio};}});}catch(e){}");
      }
      if (sb.isNotEmpty) {
        await c.executeScript(sb.toString());
      }
    }
  }

  @override
  Future<int> findStart(String query) async {
    final r = await _controller?.executeScript(
      'window.zipBrowserFind.start(${jsonEncode(query)})',
    );
    if (r is int) return r;
    return int.tryParse('$r') ?? 0;
  }

  @override
  Future<void> findNext(bool forward) async {
    await _controller?.executeScript('window.zipBrowserFind.next($forward)');
  }

  @override
  Future<void> findClear() async {
    await _controller?.executeScript('window.zipBrowserFind.clear()');
  }

  @override
  Stream<ContextMenuInfo> get contextMenu => _internal.contextMenu;

  @override
  Stream<String> get downloadRequests => _internal.downloads;

  @override
  Stream<String> get userscriptDetected => _internal.userscriptDetected;

  @override
  Stream<List<String>> get userscriptList => _internal.userscriptList;

  @override
  Stream<List<SniffedResource>> get sniffedResources => _internal.sniffedResources;

  @override
  Future<void> triggerSniff() async {
    await _controller?.executeScript(ResourceSniffer.buildScript(_bridgeGlobalName));
  }

  @override
  Future<void> clearCookies() async => _controller?.clearCookies();

  @override
  Future<void> clearCache() async => _controller?.clearCache();

  @override
  Stream<NavigationEvent> get navigationEvents => _nav.stream;
  @override
  Stream<double> get progress => _progressC.stream;
  @override
  Stream<String> get urlChanges => _urlC.stream;
  @override
  Stream<String> get titleChanges => _titleC.stream;
  @override
  Stream<WebResourceError> get resourceErrors => _errorC.stream;

  @override
  Future<String?> getCurrentTitle() async => evaluateJavascript('document.title');

  @override
  Future<String?> getCurrentUrl() async =>
      evaluateJavascript('window.location.href');

  @override
  Future<String?> get version => WebviewController.getWebViewVersion();

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _internal.close();
    await _controller?.dispose();
    await _nav.close();
    await _progressC.close();
    await _urlC.close();
    await _titleC.close();
    await _errorC.close();
  }
}
