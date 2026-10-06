import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart' hide WebResourceError;
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/bridge/find_script.dart';
import '../core/bridge/internal_dispatcher.dart';
import '../core/bridge/js_bridge.dart';
import '../core/desktop_mode_config.dart';
import '../core/kernel/browser_kernel.dart';
import '../core/kernel/kernel_types.dart';
import '../core/sniff/resource_sniffer.dart';
import '../core/sniff/sniff_model.dart';

/// 视为下载的文件扩展名
const Set<String> _downloadExt = {
  'zip', 'rar', '7z', 'tar', 'gz', 'apk', 'exe', 'msi', 'dmg', 'iso',
  'bin', 'deb', 'rpm', 'jar', 'crx', 'whl', 'pdf', 'doc', 'docx', 'xls',
  'xlsx', 'ppt', 'pptx', 'mp3', 'mp4', 'avi', 'mkv', 'flac', 'wav',
};

bool _looksLikeDownload(String url) {
  final path = url.split('?').first.split('#').first.toLowerCase();
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return _downloadExt.contains(path.substring(dot + 1));
}

/// Android 系统内核：直接调用系统 Android System WebView
/// （com.google.android.webview，由 webview_flutter_android 承载）
class AndroidSystemKernel implements BrowserKernel {
  WebViewController? _controller;
  List<UserScript> _scripts = const [];
  String? _currentUrl;
  bool _findInjected = false;
  String _bridgeGlobalName = 'zipBrowser';

  late JsBridgeHub _bridge;
  final InternalDispatcher _internal = InternalDispatcher();

  final _nav = StreamController<NavigationEvent>.broadcast();
  final _progressC = StreamController<double>.broadcast();
  final _urlC = StreamController<String>.broadcast();
  final _titleC = StreamController<String>.broadcast();
  final _errorC = StreamController<WebResourceError>.broadcast();

  @override
  String get id => 'system.android_webview';

  @override
  String get displayName => 'Android System WebView';

  @override
  KernelOrigin get origin => KernelOrigin.system;

  @override
  Set<KernelCapability> get capabilities => const {
        KernelCapability.loadUrl,
        KernelCapability.evaluateJs,
        KernelCapability.userScripts,
        KernelCapability.multiTab,
        KernelCapability.download,
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

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(_buildDelegate());
    await controller.addJavaScriptChannel(
      '${config.bridgeGlobalName}__host',
      onMessageReceived: _onHostMessage,
    );
    // Android 平台专属设置：媒体无需用户手势即可播放（便于嗅探视频直接播放）
    if (Platform.isAndroid) {
      try {
        final android = controller.platform as AndroidWebViewController;
        await android.setMediaPlaybackRequiresUserGesture(false);
        // 允许 https 页面加载 http 子资源，避免页面内容缺失/打不开
        await android.setMixedContentMode(MixedContentMode.alwaysAllow);
      } catch (_) {}
    }

    _controller = controller;
  }

  NavigationDelegate _buildDelegate() {
    return NavigationDelegate(
      onPageStarted: (url) async {
        _currentUrl = url;
        _urlC.add(url);
        _nav.add(NavigationEvent(url, NavigationStage.start));
        await _injectAtStart(url);
      },
      onPageFinished: (url) async {
        await _injectAtEnd(url);
        try {
          final title = await _controller?.runJavaScriptReturningResult(
            'document.title',
          );
          final t = title?.toString() ?? '';
          if (t.isNotEmpty && t != 'null') _titleC.add(t);
        } catch (_) {}
        _nav.add(NavigationEvent(url, NavigationStage.finished));
      },
      onProgress: (progress) => _progressC.add(progress / 100.0),
      // 导航层拦截下载（比 JS 点击拦截更可靠，覆盖所有导航来源）
      onNavigationRequest: (request) {
        if (_looksLikeDownload(request.url)) {
          _internal.downloadCtrl.add(request.url);
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onWebResourceError: (error) {
        _errorC.add(WebResourceError(
          errorCode: error.errorCode,
          description: error.description,
          isForMainFrame: error.isForMainFrame ?? true,
          url: error.url,
        ));
      },
    );
  }

  Future<void> _onHostMessage(JavaScriptMessage message) async {
    // 宿主内置消息（长按菜单 / 下载）
    if (_internal.dispatch(message.message)) return;
    final responseScript = await _bridge.handleRaw(message.message);
    if (responseScript != null) {
      await _controller?.runJavaScript(responseScript);
    }
  }

  /// documentStart：先注入 bridge 引导，再注入 content_start 脚本
  Future<void> _injectAtStart(String url) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.runJavaScript(_bridge.bootstrapScript());
    // 资源嗅探：hook fetch/XHR 必须早于页面脚本
    await controller.runJavaScript(ResourceSniffer.buildScript(_bridgeGlobalName));
    for (final script in _scripts) {
      if (script.timing == UserScriptInjectionTiming.documentStart &&
          script.matchesUrl(url)) {
        await controller.runJavaScript(script.source);
      }
    }
  }

  Future<void> _injectAtEnd(String url) async {
    final controller = _controller;
    if (controller == null) return;
    for (final script in _scripts) {
      if (script.timing == UserScriptInjectionTiming.documentEnd &&
          script.matchesUrl(url)) {
        await controller.runJavaScript(script.source);
      }
    }
  }

  @override
  Widget buildView() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return WebViewWidget(controller: controller);
  }

  @override
  Future<void> loadUrl(String url) async {
    final controller = _controller;
    if (controller == null) return;

    if (url.startsWith('data:')) {
      await controller.loadHtmlString(UriData.parse(url).contentAsString());
      return;
    }
    if (url == 'about:blank') {
      await controller.loadHtmlString('');
      return;
    }
    _currentUrl = url;
    await controller.loadRequest(Uri.parse(url));
  }

  @override
  Future<void> goBack() async => _controller?.goBack();
  @override
  Future<void> goForward() async => _controller?.goForward();
  @override
  Future<void> reload() async => _controller?.reload();
  @override
  Future<void> stopLoading() async {
    // webview_flutter 未暴露 stop
  }

  @override
  Future<bool> canGoBack() async => _controller?.canGoBack() ?? false;
  @override
  Future<bool> canGoForward() async => _controller?.canGoForward() ?? false;

  @override
  Future<String?> evaluateJavascript(String script) async {
    final result = await _controller?.runJavaScriptReturningResult(script);
    if (result == null) return null;
    // 与 Windows executeScript 对齐，统一返回 JSON 字符串
    return jsonEncode(result);
  }

  @override
  void registerBridgeHandler(String method, BridgeHandler handler) {
    _bridge.register(method, handler);
  }

  // —— 增强能力 ——

  @override
  Future<void> setJavaScriptEnabled(bool enabled) async {
    await _controller?.setJavaScriptMode(
        enabled ? JavaScriptMode.unrestricted : JavaScriptMode.disabled);
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    await _controller?.setUserAgent(userAgent);
  }

  @override
  Future<void> setDesktopMode(DesktopModeConfig config) async {
    final c = _controller;
    if (c == null) return;
    await c.setUserAgent(config.effectiveUA);
    // 通过 JS 覆写视口与 DPR 以模拟桌面环境
    if (config.enabled) {
      final vp = StringBuffer();
      if (config.viewportWidth > 0) {
        vp.writeln(
            "document.querySelectorAll('meta[name=viewport]').forEach(e=>e.remove());");
        vp.writeln(
            "var m=document.createElement('meta');m.name='viewport';"
            "m.content='width=${config.viewportWidth},initial-scale=1';"
            "document.head&&document.head.appendChild(m);");
      }
      if (config.devicePixelRatio > 0) {
        vp.writeln("try{Object.defineProperty(window,'devicePixelRatio',"
            "{get:function(){return ${config.devicePixelRatio};}});}catch(e){}");
      }
      if (vp.isNotEmpty) {
        await c.runJavaScript(vp.toString());
      }
    }
  }

  @override
  Future<int> findStart(String query) async {
    final c = _controller;
    if (c == null) return 0;
    if (!_findInjected) {
      await c.runJavaScript(kFindScript);
      _findInjected = true;
    }
    final r = await c.runJavaScriptReturningResult(
      'window.zipBrowserFind.start(${jsonEncode(query)})',
    );
    if (r is int) return r;
    return int.tryParse('$r') ?? 0;
  }

  @override
  Future<void> findNext(bool forward) async {
    await _controller?.runJavaScript(
      'window.zipBrowserFind.next($forward)',
    );
  }

  @override
  Future<void> findClear() async {
    await _controller?.runJavaScript('window.zipBrowserFind.clear()');
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
    await _controller?.runJavaScript(ResourceSniffer.buildScript(_bridgeGlobalName));
  }

  @override
  Future<void> clearCookies() async {
    await WebViewCookieManager().clearCookies();
  }

  @override
  Future<void> clearCache() async {
    // webview_flutter 未暴露 clearCache；Android 缓存随应用数据，
    // 此处至少清除 Cookie（见 clearCookies）。
  }

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
  Future<String?> getCurrentTitle() async {
    return evaluateJavascript('document.title');
  }

  @override
  Future<String?> getCurrentUrl() async {
    final u = _currentUrl;
    if (u != null) return u;
    return evaluateJavascript('window.location.href');
  }

  @override
  Future<String?> get version async {
    final ua = await evaluateJavascript('navigator.userAgent');
    return ua;
  }

  @override
  Future<void> dispose() async {
    await _internal.close();
    await _nav.close();
    await _progressC.close();
    await _urlC.close();
    await _titleC.close();
    await _errorC.close();
  }
}
