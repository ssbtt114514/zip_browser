import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/gestures.dart';
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
///
/// 本实现补齐了软件内核真正可用所需的四件事：
///   1. **输入**：指针 / 滚轮 / 按键事件经 `zb_kernel_dispatch_from_host`
///      送入内核（ABI v1 没有输入符号，约定用该消息通道传输入）；
///   2. **网络**：内核通过 `host_dispatch("net.fetch")` 请求宿主代抓页面，
///      宿主在 `HostBridgeApi` 中实现；
///   3. **状态**：内核用 `host_dispatch("kernel.state")` 上报
///      url/title/可否前进后退/滚动位置，用于刷新工具栏与地址栏；
///   4. **自适应尺寸**：视图尺寸变化时重建表面并按新尺寸重新排版。
class FfiBrowserKernel implements BrowserKernel {
  final KernelSource source;

  static const MethodChannel _surfaceChannel =
      MethodChannel('zip_browser/native_surface');

  /// 首次创建表面时的默认尺寸（真实尺寸随视图自适应）
  static const int _defaultWidth = 1024;
  static const int _defaultHeight = 720;

  FfiKernelLink? _link;
  Timer? _ticker;
  int? _textureId;
  int _surfaceW = 0;
  int _surfaceH = 0;
  bool _surfaceAvailable = false;
  bool _resizing = false;
  String? _surfaceError;
  bool _canBack = false;
  bool _canForward = false;

  /// 当前纹理 id：尺寸变化后需要重建 Texture 组件
  final ValueNotifier<int?> _texture = ValueNotifier<int?>(null);

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
          KernelCapability.multiTab,
          KernelCapability.download,
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
        // 内核状态上报：本地消化，不转发给插件 bridge
        if (method == 'kernel.state') {
          _applyState(paramsJson);
          _link?.dispatchFromHost(
              jsonEncode({'request_id': requestId, 'result': {'ok': true}}));
          return;
        }
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

    await _attachSurface(_defaultWidth, _defaultHeight);
  }

  /// 解析内核上报的状态并同步到宿主事件流
  void _applyState(String paramsJson) {
    try {
      final decoded = jsonDecode(paramsJson);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);

      final back = map['can_back'] == true;
      final forward = map['can_forward'] == true;
      if (back != _canBack) _canBack = back;
      if (forward != _canForward) _canForward = forward;

      final url = map['url']?.toString();
      if (url != null && url.isNotEmpty) _urlC.add(url);

      final title = map['title']?.toString();
      if (title != null && title.isNotEmpty) _titleC.add(title);

      final loading = map['loading'] == true;
      if (!loading) {
        _progressC.add(1);
        if (url != null && url.isNotEmpty) {
          _nav.add(NavigationEvent(url, NavigationStage.finished));
        }
      }
    } catch (_) {
      // 状态消息异常时忽略，不影响渲染
    }
  }

  /// 向内核投递一条输入 / 控制消息
  void sendToKernel(Map<String, dynamic> message) {
    _link?.dispatchFromHost(jsonEncode(message));
  }

  Future<void> _attachSurface(int width, int height) async {
    try {
      final textureId = await _surfaceChannel.invokeMethod<int>(
        'createSurface',
        {'width': width, 'height': height},
      );
      if (textureId == null) {
        throw StateError('surface 插件未返回 textureId');
      }
      _textureId = textureId;
      _surfaceW = width;
      _surfaceH = height;

      // native surface 插件导出的帧入口（帧路径不经过 Dart）
      // Android：surface 是独立 jni 库，优先按名打开；
      // Windows：符号编译进主程序，从进程查找。
      DynamicLibrary surfaceLib;
      if (Platform.isAndroid) {
        try {
          surfaceLib = DynamicLibrary.open('libzb_native_surface.so');
        } catch (_) {
          surfaceLib = DynamicLibrary.process();
        }
      } else {
        surfaceLib = DynamicLibrary.process();
      }
      final submit = surfaceLib
          .lookup<NativeFunction<FrameSubmitC>>('zb_surface_submit_frame');

      _surfaceAvailable = _link!.attachSurface(
        textureId: textureId,
        frameSubmit: submit,
        width: width,
        height: height,
      );

      if (_surfaceAvailable) {
        _surfaceError = null;
        _texture.value = textureId;
        _ticker ??= Timer.periodic(
          const Duration(milliseconds: 33),
          (_) => _link?.tick(),
        );
      }
    } catch (e) {
      _surfaceAvailable = false;
      _surfaceError = e.toString();
      _texture.value = null;
    }
  }

  /// 视图尺寸变化：重建表面并按新尺寸重排版
  Future<void> _resizeSurface(int width, int height) async {
    if (_resizing || !_surfaceAvailable) return;
    // 尺寸变化很小时忽略，避免频繁重建纹理
    if ((width - _surfaceW).abs() < 8 && (height - _surfaceH).abs() < 8) {
      return;
    }
    _resizing = true;
    final oldTexture = _textureId;
    try {
      await _attachSurface(width, height);
      if (oldTexture != null && oldTexture != _textureId) {
        try {
          await _surfaceChannel
              .invokeMethod('destroySurface', {'textureId': oldTexture});
        } catch (_) {}
      }
    } finally {
      _resizing = false;
    }
  }

  @override
  Widget buildView() {
    return ValueListenableBuilder<int?>(
      valueListenable: _texture,
      builder: (context, textureId, __) {
        if (!_surfaceAvailable || textureId == null) {
          return _SurfaceFallback(error: _surfaceError);
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite
                ? constraints.maxWidth.round()
                : _surfaceW;
            final h = constraints.maxHeight.isFinite
                ? constraints.maxHeight.round()
                : _surfaceH;
            if ((w - _surfaceW).abs() >= 8 || (h - _surfaceH).abs() >= 8) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _resizeSurface(w, h),
              );
            }
            return _KernelInputLayer(
              kernel: this,
              child: Texture(textureId: textureId),
            );
          },
        );
      },
    );
  }

  @override
  Future<void> loadUrl(String url) async {
    final link = _link;
    if (link == null) return;

    if (url.startsWith('data:')) {
      // data: URL 由宿主解出 HTML 文本后直接交给内核
      try {
        link.loadUrl(UriData.parse(url).contentAsString());
      } catch (e) {
        _errorC.add(WebResourceError(description: '无法解析 data: 内容：$e'));
        return;
      }
    } else {
      link.loadUrl(url);
    }
    _canBack = true;
    _progressC.add(0.1);
    _nav.add(NavigationEvent(url, NavigationStage.start));
    link.tick();
    _urlC.add(url);
  }

  @override
  Future<void> goBack() async {
    if (_link?.goBack() == true) {
      _progressC.add(0.2);
    }
  }

  @override
  Future<void> goForward() async {
    if (_link?.goForward() == true) {
      _progressC.add(0.2);
    }
  }

  @override
  Future<void> reload() async {
    _progressC.add(0.1);
    _link?.reload();
  }

  @override
  Future<void> stopLoading() async {}
  @override
  Future<bool> canGoBack() async => _canBack;
  @override
  Future<bool> canGoForward() async => _canForward;

  @override
  Future<String?> evaluateJavascript(String script) async =>
      _link?.evalJs(script);

  @override
  void registerBridgeHandler(String method, BridgeHandler handler) =>
      _bridge.register(method, handler);

  // —— 增强能力 ——

  @override
  Future<void> setJavaScriptEnabled(bool enabled) async {
    // 软件内核不含 JS 引擎，本项对其无意义
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> setDesktopMode(DesktopModeConfig config) async {}

  /// 页面内查找：软件内核支持受限的文本查找命令。
  ///
  /// 约定由内核在 `window.find` 命令中返回 `{"ok":true,"count":N}`；
  /// 不支持时返回 0（不假装成功）。
  @override
  Future<int> findStart(String query) async {
    final raw = await evaluateJavascript(
        'window.find(${jsonEncode(query)})');
    if (raw == null || raw.isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['ok'] == true) {
        final count = decoded['count'];
        if (count is int) return count;
        if (count is num) return count.toInt();
      }
    } catch (_) {}
    return 0;
  }

  @override
  Future<void> findNext(bool forward) async {
    await evaluateJavascript('window.findNext(${forward ? 'true' : 'false'})');
  }

  @override
  Future<void> findClear() async {
    await evaluateJavascript('window.findClear()');
  }

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
    _texture.dispose();
    await _nav.close();
    await _progressC.close();
    await _urlC.close();
    await _titleC.close();
    await _errorC.close();
  }
}

/// 把 Flutter 侧的指针 / 滚轮 / 按键事件转成内核输入消息。
///
/// ABI v1 未定义输入符号，这里通过既有的 `dispatch_from_host` 通道投递，
/// 由内核解析 `{"event": ...}` 形式的 JSON。
class _KernelInputLayer extends StatefulWidget {
  final FfiBrowserKernel kernel;
  final Widget child;

  const _KernelInputLayer({required this.kernel, required this.child});

  @override
  State<_KernelInputLayer> createState() => _KernelInputLayerState();
}

class _KernelInputLayerState extends State<_KernelInputLayer> {
  final FocusNode _focus = FocusNode(debugLabel: 'ffi_kernel_input');

  void _pointer(PointerEvent event, String type) {
    widget.kernel.sendToKernel({
      'event': 'pointer',
      'type': type,
      'x': event.localPosition.dx.round(),
      'y': event.localPosition.dy.round(),
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // 注意：LogicalKeyboardKey 覆盖了 == / hashCode，不能作为 const map 的键
    final names = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.arrowUp: 'Up',
      LogicalKeyboardKey.arrowDown: 'Down',
      LogicalKeyboardKey.arrowLeft: 'Left',
      LogicalKeyboardKey.arrowRight: 'Right',
      LogicalKeyboardKey.pageUp: 'PageUp',
      LogicalKeyboardKey.pageDown: 'PageDown',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.enter: 'Enter',
    };
    final name = names[event.logicalKey];
    if (name == null) return KeyEventResult.ignored;
    widget.kernel.sendToKernel({'event': 'key', 'key': name});
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          widget.kernel.sendToKernel({
            'event': 'pointer',
            'type': 'down',
            'x': e.localPosition.dx.round(),
            'y': e.localPosition.dy.round(),
          });
        },
        onPointerUp: (e) => _pointer(e, 'up'),
        onPointerMove: (e) {
          // 仅在拖拽时上报，减少消息量
          widget.kernel.sendToKernel({
            'event': 'pointer',
            'type': e.buttons != 0 ? 'move' : 'hover',
            'x': e.localPosition.dx.round(),
            'y': e.localPosition.dy.round(),
          });
        },
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            widget.kernel.sendToKernel({
              'event': 'scroll',
              'dx': signal.scrollDelta.dx.round(),
              'dy': signal.scrollDelta.dy.round(),
            });
          }
        },
        child: widget.child,
      ),
    );
  }
}

/// surface 插件缺失时的降级提示
class _SurfaceFallback extends StatelessWidget {
  final String? error;
  const _SurfaceFallback({this.error});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_off_outlined,
                size: 52, color: scheme.error),
            const SizedBox(height: 14),
            const Text(
              '插件内核已加载，但缺少配套的原生表面插件',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              '请将 native_plugins/zb_native_surface 编译进宿主后重试\n'
              '（详见 docs/PLUGIN_KERNEL_GUIDE.md）',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: scheme.onSurfaceVariant, height: 1.6, fontSize: 13),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!,
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
            ],
          ],
        ),
      ),
    );
  }
}
