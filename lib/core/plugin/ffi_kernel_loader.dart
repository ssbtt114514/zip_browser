import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// 宿主支持的 FFI 内核 ABI 版本。
/// 插件内核的 zb_abi_version() 必须与此完全一致。
const int kHostFfiAbiVersion = 1;

/// 内核请求宿主能力的回调（native -> Dart 控制面）
/// 参数：requestId、方法名、参数 JSON
typedef HostDispatchC = Void Function(
    Int64 requestId, Pointer<Utf8> method, Pointer<Utf8> paramsJson);
typedef HostDispatchDart = void Function(
    int requestId, Pointer<Utf8> method, Pointer<Utf8> paramsJson);

/// 帧提交回调：内核把 RGBA 帧交给表面（通常指向 native surface 插件的
/// `zb_surface_submit_frame`，帧路径全程不经过 Dart）
typedef FrameSubmitC = Void Function(Int64 textureId,
    Pointer<Uint8> rgba, Int32 width, Int32 height, Int32 stride);
typedef FrameSubmitDart = void Function(int textureId,
    Pointer<Uint8> rgba, int width, int height, int stride);

typedef _AbiVersionC = Int32 Function();
typedef _CreateC = Pointer<Void> Function(
    Pointer<Utf8> configJson, Pointer<NativeFunction<HostDispatchC>> hostDispatch);
typedef _Void1C = Void Function(Pointer<Void>);
typedef _Int1C = Int32 Function(Pointer<Void>);
typedef _Str1C = Pointer<Utf8> Function(Pointer<Void>);
typedef _LoadUrlC = Int32 Function(Pointer<Void>, Pointer<Utf8> url);
typedef _EvalC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8> script);
typedef _AttachC = Int32 Function(Pointer<Void>, Int64 textureId,
    Pointer<NativeFunction<FrameSubmitC>> frameCb, Int32 width, Int32 height);
typedef _DispatchC = Int32 Function(Pointer<Void>, Pointer<Utf8> messageJson);
typedef _FreeC = Void Function(Pointer<Void> ptr);

/// 与一个插件内核原生库的活动连接
class FfiKernelLink {
  final DynamicLibrary _lib;
  late final Pointer<Void> _handle;
  final NativeCallable<HostDispatchC>? _hostDispatchCallable;

  FfiKernelLink._(this._lib, this._hostDispatchCallable, this._handle);

  /// 打开并创建内核实例。
  /// [onHostDispatch] 接收内核的宿主能力请求（可转发给 JsBridgeHub）。
  factory FfiKernelLink.open({
    required String libraryPath,
    required String configJson,
    void Function(int requestId, String method, String paramsJson)?
        onHostDispatch,
  }) {
    final lib = DynamicLibrary.open(libraryPath);

    final abiVersion = lib.lookupFunction<_AbiVersionC, int Function()>('zb_abi_version')();
    if (abiVersion != kHostFfiAbiVersion) {
      throw StateError(
        '内核 ABI 版本不匹配：插件=$abiVersion，宿主=$kHostFfiAbiVersion',
      );
    }

    NativeCallable<HostDispatchC>? callable;
    Pointer<NativeFunction<HostDispatchC>> cbPtr = nullptr;
    if (onHostDispatch != null) {
      callable = NativeCallable<HostDispatchC>.listener((
        int requestId,
        Pointer<Utf8> method,
        Pointer<Utf8> params,
      ) {
        onHostDispatch(
          requestId,
          method == nullptr ? '' : method.toDartString(),
          params == nullptr ? '' : params.toDartString(),
        );
      });
      cbPtr = callable.nativeFunction;
    }

    final create = lib.lookupFunction<_CreateC,
        Pointer<Void> Function(Pointer<Utf8>, Pointer<NativeFunction<HostDispatchC>>)>(
      'zb_kernel_create',
    );
    final configPtr = configJson.toNativeUtf8();
    final handle = create(configPtr, cbPtr);
    calloc.free(configPtr);
    if (handle == nullptr) {
      callable?.close();
      throw StateError('zb_kernel_create 返回空句柄');
    }

    return FfiKernelLink._(lib, callable, handle);
  }

  /// 把一个帧提交函数（通常来自 native surface 插件）绑定到内核表面
  bool attachSurface({
    required int textureId,
    required Pointer<NativeFunction<FrameSubmitC>> frameSubmit,
    required int width,
    required int height,
  }) {
    final attach = _lib.lookupFunction<_AttachC,
        int Function(Pointer<Void>, int, Pointer<NativeFunction<FrameSubmitC>>, int,
            int)>('zb_kernel_attach_surface');
    return attach(_handle, textureId, frameSubmit, width, height) == 0;
  }

  /// 驱动一帧（软件渲染内核）；返回 0 表示成功
  int tick() => _lib.lookupFunction<_Int1C, int Function(Pointer<Void>)>(
      'zb_kernel_tick')(_handle);

  String? get name => _readString(_lib
      .lookupFunction<_Str1C, Pointer<Utf8> Function(Pointer<Void>)>(
          'zb_kernel_name')(_handle));

  String? get version => _readString(_lib
      .lookupFunction<_Str1C, Pointer<Utf8> Function(Pointer<Void>)>(
          'zb_kernel_version')(_handle));

  String? get currentUrl => _readString(_lib
      .lookupFunction<_Str1C, Pointer<Utf8> Function(Pointer<Void>)>(
          'zb_kernel_current_url')(_handle));

  String? get title => _readString(_lib
      .lookupFunction<_Str1C, Pointer<Utf8> Function(Pointer<Void>)>(
          'zb_kernel_title')(_handle));

  String? evalJs(String script) {
    final ptr = script.toNativeUtf8();
    final result = _readString(_lib
        .lookupFunction<_EvalC,
            Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>(
          'zb_kernel_eval_js',
        )(_handle, ptr));
    calloc.free(ptr);
    return result;
  }

  bool loadUrl(String url) {
    final ptr = url.toNativeUtf8();
    final ok = _lib
        .lookupFunction<_LoadUrlC, int Function(Pointer<Void>, Pointer<Utf8>)>(
            'zb_kernel_load_url')(_handle, ptr) ==
        0;
    calloc.free(ptr);
    return ok;
  }

  bool goBack() => _lib.lookupFunction<_Int1C, int Function(Pointer<Void>)>(
      'zb_kernel_go_back')(_handle) == 0;

  bool goForward() =>
      _lib.lookupFunction<_Int1C, int Function(Pointer<Void>)>(
          'zb_kernel_go_forward')(_handle) ==
      0;

  bool reload() => _lib.lookupFunction<_Int1C, int Function(Pointer<Void>)>(
      'zb_kernel_reload')(_handle) == 0;

  /// 宿主 -> 内核的消息（bridge 响应 / 事件）
  bool dispatchFromHost(String messageJson) {
    final ptr = messageJson.toNativeUtf8();
    final ok = _lib
            .lookupFunction<_DispatchC,
                int Function(Pointer<Void>, Pointer<Utf8>)>(
                'zb_kernel_dispatch_from_host')(_handle, ptr) ==
        0;
    calloc.free(ptr);
    return ok;
  }

  String? _readString(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return null;
    final value = ptr.toDartString();
    _lib.lookupFunction<_FreeC, void Function(Pointer<Void>)>('zb_free_ptr')(
        ptr.cast<Void>());
    return value;
  }

  void dispose() {
    _lib.lookupFunction<_Void1C, void Function(Pointer<Void>)>(
        'zb_kernel_destroy')(_handle);
    _hostDispatchCallable?.close();
  }
}
