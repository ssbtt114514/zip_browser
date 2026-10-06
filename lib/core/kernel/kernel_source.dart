import 'kernel_types.dart';

/// 内核来源抽象：独立安装包内核与 zip 插件携带的内核共用同一套加载逻辑。
abstract class KernelSource {
  /// 宿主内唯一的内核 id
  String get kernelId;

  /// 展示名
  String get displayName;

  /// 加载方式：`ffi` / `webview2_fixed`
  String get type;

  /// FFI ABI 版本
  int get abiVersion;

  /// 内核来源类型
  KernelOrigin get origin;

  /// 声明的能力位（为空表示使用该加载方式的默认能力）
  Set<KernelCapability> get capabilities;

  /// FFI 原生库绝对路径（type == ffi 时有效）
  String? get libraryPath;

  /// Fixed Version 运行时目录绝对路径（type == webview2_fixed 时有效）
  String? get runtimeDir;
}
