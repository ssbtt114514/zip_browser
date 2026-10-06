import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge/js_bridge.dart';
import '../core/desktop_mode_config.dart';
import '../core/kernel/browser_kernel.dart';
import '../core/kernel/kernel_types.dart';
import '../core/sniff/sniff_model.dart';

/// Linux 内核：通过 WebKitGTK 承载网页。
///
/// 控制层走 MethodChannel `zip_browser/linux_webkit`：
/// 原生侧（linux/runner 或随平台插件提供的 WebKitGTK 视图）负责创建
/// `WebKitWebView` 并回传事件。当原生视图未注册时，[buildView] 回退到
/// 路线图提示，浏览器的其余功能（嗅探、用户脚本、下载）保持可用。
class LinuxWebKitKernel implements BrowserKernel {
  static const MethodChannel _channel =
      MethodChannel('zip_browser/linux_webkit');

  /// 原生 WebKitGTK 视图是否已注册
  static bool nativeAvailable = false;

  late JsBridgeHub _bridge;
  String _bridgeGlobalName = 'zipBrowser';
  String? _currentUrl;

  final _nav = StreamController<NavigationEvent>.broadcast();
  final _progressC = StreamController<double>.broadcast();
  final _urlC = StreamController<String>.broadcast();
  final _titleC = StreamController<String>.broadcast();
  final _errorC = StreamController<WebResourceError>.broadcast();

  @override
  String get id => 'system.linux_webkit';
  @override
  String get displayName => 'WebKitGTK（系统）';
  @override
  KernelOrigin get origin => KernelOrigin.system;
  @override
  Set<KernelCapability> get capabilities => const {
        KernelCapability.loadUrl,
        KernelCapability.evaluateJs,
        KernelCapability.userScripts,
        KernelCapability.download,
      };
  @override
  JsBridgeHub get bridge => _bridge;

  @override
  Future<void> initialize(KernelViewConfig config) async {
    _bridgeGlobalName = config.bridgeGlobalName;
    _bridge = JsBridgeHub(
      globalName: config.bridgeGlobalName,
      allowedMethods: config.allowedBridgeMethods,
    );
    try {
      await _channel.invokeMethod('create', {
        'viewId': id,
        'bridgeGlobalName': config.bridgeGlobalName,
      });
      nativeAvailable = true;
    } on MissingPluginException {
      nativeAvailable = false;
    } catch (_) {
      nativeAvailable = false;
    }
  }

  @override
  Widget buildView() {
    return const _LinuxRoadmapView();
  }

  @override
  Future<void> loadUrl(String url) async {
    _currentUrl = url;
    _urlC.add(url);
    _progressC.add(0.1);
    try {
      await _channel.invokeMethod('loadUrl', {'url': url});
    } catch (_) {
      _progressC.add(1);
    }
  }

  @override
  Future<void> goBack() async => _invoke('goBack');
  @override
  Future<void> goForward() async => _invoke('goForward');
  @override
  Future<void> reload() async => _invoke('reload');
  @override
  Future<void> stopLoading() async => _invoke('stop');

  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<String?> evaluateJavascript(String script) async {
    try {
      return await _channel.invokeMethod<String>('evaluate', {'script': script});
    } catch (_) {
      return null;
    }
  }

  @override
  void registerBridgeHandler(String method, BridgeHandler handler) =>
      _bridge.register(method, handler);

  @override
  Future<void> setUserAgent(String? userAgent) async {
    try {
      await _channel.invokeMethod('setUserAgent', {'userAgent': userAgent ?? ''});
    } catch (_) {}
  }

  @override
  Future<void> setDesktopMode(DesktopModeConfig config) async {
    await setUserAgent(config.enabled ? config.effectiveUA : null);
  }

  @override
  Future<int> findStart(String query) async => 0;
  @override
  Future<void> findNext(bool forward) async {}
  @override
  Future<void> findClear() async {}

  @override
  Stream<ContextMenuInfo> get contextMenu => const Stream.empty();
  @override
  Stream<String> get downloadRequests => const Stream.empty();
  @override
  Stream<String> get userscriptDetected => const Stream.empty();
  @override
  Stream<List<String>> get userscriptList => const Stream.empty();
  @override
  Stream<List<SniffedResource>> get sniffedResources => const Stream.empty();
  @override
  Future<void> triggerSniff() async {}

  @override
  Future<void> clearCookies() async => _invoke('clearCookies');
  @override
  Future<void> clearCache() async => _invoke('clearCache');

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
  Future<String?> getCurrentTitle() async => null;
  @override
  Future<String?> getCurrentUrl() async => _currentUrl;

  @override
  Future<String?> get version async => null;

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod(method, {'viewId': id});
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose', {'viewId': id});
    } catch (_) {}
    await _nav.close();
    await _progressC.close();
    await _urlC.close();
    await _titleC.close();
    await _errorC.close();
  }

  /// 供原生侧回调的桥接名称（占位，保持与其它内核一致的接口）
  String get bridgeGlobalName => _bridgeGlobalName;
}

/// 原生 WebKitGTK 视图未注册时的路线图视图
class _LinuxRoadmapView extends StatelessWidget {
  const _LinuxRoadmapView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.laptop_chromebook, size: 56, color: Colors.blueGrey),
            const SizedBox(height: 16),
            const Text(
              'Linux（WebKitGTK）',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              LinuxWebKitKernel.nativeAvailable
                  ? '正在连接 WebKitGTK 视图…'
                  : '未检测到 WebKitGTK 原生视图。\n'
                      '请安装 libwebkit2gtk-4.1-dev 并启用平台插件，\n'
                      '或使用携带 FFI 内核的 zip 插件浏览网页。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
