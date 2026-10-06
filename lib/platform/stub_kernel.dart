import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bridge/js_bridge.dart';
import '../core/desktop_mode_config.dart';
import '../core/kernel/browser_kernel.dart';
import '../core/kernel/kernel_types.dart';
import '../core/sniff/sniff_model.dart';

/// 尚未支持平台（Linux / macOS）的占位内核。
/// UI 仍可启动，网页区域显示平台路线图；可通过插件 FFI 内核获得实际能力。
class StubKernel implements BrowserKernel {
  late final JsBridgeHub _bridge;

  final _nav = StreamController<NavigationEvent>.broadcast();
  final _progressC = StreamController<double>.broadcast();
  final _urlC = StreamController<String>.broadcast();
  final _titleC = StreamController<String>.broadcast();
  final _errorC = StreamController<WebResourceError>.broadcast();

  @override
  String get id => 'system.unsupported';
  @override
  String get displayName => '平台占位内核';
  @override
  KernelOrigin get origin => KernelOrigin.system;
  @override
  Set<KernelCapability> get capabilities => const {};
  @override
  JsBridgeHub get bridge => _bridge;

  @override
  Future<void> initialize(KernelViewConfig config) async {
    _bridge = JsBridgeHub(
      globalName: config.bridgeGlobalName,
      allowedMethods: config.allowedBridgeMethods,
    );
  }

  @override
  Widget buildView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction, size: 56, color: Colors.blueGrey),
            SizedBox(height: 16),
            Text(
              '当前平台的系统内核尚在规划中',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              '路线图：Android / Windows → Linux / macOS\n'
              '在此之前可安装携带 FFI 内核的 zip 插件',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> loadUrl(String url) async {}
  @override
  Future<void> goBack() async {}
  @override
  Future<void> goForward() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> stopLoading() async {}
  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<bool> canGoForward() async => false;
  @override
  Future<String?> evaluateJavascript(String script) async => null;
  @override
  void registerBridgeHandler(String method, BridgeHandler handler) =>
      _bridge.register(method, handler);

  // —— 增强能力（占位：空实现）——
  @override
  Future<void> setUserAgent(String? userAgent) async {}
  @override
  Future<void> setDesktopMode(DesktopModeConfig config) async {}
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
  Future<void> clearCookies() async {}
  @override
  Future<void> clearCache() async {}

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
  Future<String?> getCurrentUrl() async => null;
  @override
  Future<String?> get version async => null;

  @override
  Future<void> dispose() async {
    await _nav.close();
    await _progressC.close();
    await _urlC.close();
    await _titleC.close();
    await _errorC.close();
  }
}
