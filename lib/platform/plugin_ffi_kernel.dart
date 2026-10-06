import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge/js_bridge.dart';
import '../core/desktop_mode_config.dart';
import '../core/kernel/browser_kernel.dart';
import '../core/kernel/kernel_source.dart';
import '../core/kernel/kernel_types.dart';
import '../core/plugin/ffi_kernel_loader.dart';
import '../core/sniff/sniff_model.dart';

/// FFI 原生内核（由独立安装包或 zip 插件提供）。
///
/// 渲染路径：内核生成 RGBA 帧 -> native surface 插件
/// （zb_surface_submit_frame，编译进宿主）-> Flutter Texture。
/// 控制路径：dart:ffi 调用 zb_kernel_*；内核的宿主请求经
/// hostDispatch 回调转发到宿主 bridge。
class FfiBrowserKernel implements BrowserKernel {
  final KernelSource source;

  static const MethodChannel _surfaceChannel =
      MethodChannel('zip_browser/native_surface');

  static const int _surfaceWidth = 960;
  static const int _surfaceHeight = 600;

  FfiKernelLink? _link;
  Timer? _ticker;
  int? _textureId;
  bool _surfaceAvailable = false;
  String? _surfaceError;
  bool _canBack = false;

  late JsBridgeHub _bridge;

  final _nav = StreamController<NavigationEvent>.broadcast();
  final _progressC = StreamController<double>.broadcast();
  final _urlC = StreamController<String>.broadcast();
  final _titleC = StreamController<String>.broadcast();
  final _errorC = StreamController<WebResourceError>.broadcast();

  FfiBrowserKernel({required this.source});

  @override
  String get id => source.kernelId;
  @override
  String get displayName => source.displayName;
  @override
  KernelOrigin get origin => source.origin;
  @override
  Set<KernelCapability> get capabilities => source.capabilities.isEmpty
      ? const {
          KernelCapability.loadUrl,
          KernelCapability.evaluateJs,
          KernelCapability.userScripts,
          KernelCapability.multiTab,
        }
      : source.capabilities;
  @override
  JsBridgeHub get bridge => _bridge;

  @override
  Future<void> initialize(KernelViewConfig config) async {
    _bridge = JsBridgeHub(
      globalName: config.bridgeGlobalName,
      allowedMethods: config.allowedBridgeMethods,
    );

    final libraryPath = source.libraryPath ?? config.nativeLibraryPath;
    if (libraryPath == null) {
      throw StateError('该内核未提供当前平台的原生库');
    }

    _link = FfiKernelLink.open(
      libraryPath: libraryPath,
      configJson: jsonEncode({
        'tab_id': config.tabId,
        'bridge_global': config.bridgeGlobalName,
        'user_scripts': config.userScripts
            .map((s) => {'source': s.source, 'matches': s.matches})
            .toList(),
      }),
      onHostDispatch: (requestId, method, paramsJson) async {
        dynamic params;
        try {
          params = jsonDecode(paramsJson);
        } catch (_) {
          params = <String, dynamic>{};
        }
        final result = await _bridge.invokeLocal(method, params);
        _link?.dispatchFromHost(jsonEncode({
          'request_id': requestId,
          ...result.toJson(),
        }));
      },
    );

    await _attachSurface();
  }

  Future<void> _attachSurface() async {
    try {
      final textureId = await _surfaceChannel.invokeMethod<int>(
        'createSurface',
        const {'width': _surfaceWidth, 'height': _surfaceHeight},
      );
      if (textureId == null) {
        throw StateError('surface 插件未返回 textureId');
      }
      _textureId = textureId;

      // native surface 插件导出的帧入口（帧路径不经过 Dart）
      final submit = DynamicLibrary.process()
          .lookup<NativeFunction<FrameSubmitC>>('zb_surface_submit_frame');

      _surfaceAvailable = _link!.attachSurface(
        textureId: textureId,
        frameSubmit: submit,
        width: _surfaceWidth,
        height: _surfaceHeight,
      );

      if (_surfaceAvailable) {
        _ticker = Timer.periodic(
          const Duration(milliseconds: 33),
          (_) => _link?.tick(),
        );
      }
    } catch (e) {
      _surfaceAvailable = false;
      _surfaceError = e.toString();
    }
  }

  @override
  Widget buildView() {
    if (_surfaceAvailable && _textureId != null) {
      return Texture(textureId: _textureId!);
    }
    return _SurfaceFallback(error: _surfaceError);
  }

  @override
  Future<void> loadUrl(String url) async {
    final link = _link;
    if (link == null) return;

    if (url.startsWith('data:')) {
      link.loadUrl(UriData.parse(url).contentAsString());
    } else {
      link.loadUrl(url);
    }
    _canBack = true;
    _progressC.add(0);
    _nav.add(NavigationEvent(url, NavigationStage.start));
    link.tick();
    _progressC.add(1);
    _urlC.add(url);
    final title = link.title;
    if (title != null && title.isNotEmpty) _titleC.add(title);
    _nav.add(NavigationEvent(url, NavigationStage.finished));
  }

  @override
  Future<void> goBack() async => _link?.goBack();
  @override
  Future<void> goForward() async => _link?.goForward();
  @override
  Future<void> reload() async => _link?.reload();
  @override
  Future<void> stopLoading() async {}
  @override
  Future<bool> canGoBack() async => _canBack;
  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<String?> evaluateJavascript(String script) async =>
      _link?.evalJs(script);

  @override
  void registerBridgeHandler(String method, BridgeHandler handler) =>
      _bridge.register(method, handler);

  // —— 增强能力（软件内核：多数不适用，空实现）——
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
  Future<String?> getCurrentTitle() async => _link?.title;
  @override
  Future<String?> getCurrentUrl() async => _link?.currentUrl;
  @override
  Future<String?> get version async => _link?.version;

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
    if (_textureId != null) {
      try {
        await _surfaceChannel
            .invokeMethod('destroySurface', {'textureId': _textureId});
      } catch (_) {}
    }
    _link?.dispose();
    await _nav.close();
    await _progressC.close();
    await _urlC.close();
    await _titleC.close();
    await _errorC.close();
  }
}

/// surface 插件缺失时的降级提示
class _SurfaceFallback extends StatelessWidget {
  final String? error;
  const _SurfaceFallback({this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_off_outlined,
                size: 52, color: Colors.orange),
            const SizedBox(height: 14),
            const Text(
              '插件内核已加载，但缺少配套的原生表面插件',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              '请将 native_plugins/zb_native_surface 编译进宿主后重试\n'
              '（详见 docs/PLUGIN_KERNEL_GUIDE.md）',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.6, fontSize: 13),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!,
                  style: const TextStyle(fontSize: 11, color: Colors.black38)),
            ],
          ],
        ),
      ),
    );
  }
}
