import 'dart:io';

import '../../platform/android_system_kernel.dart';
import '../../platform/linux_webkit_kernel.dart';
import '../../platform/plugin_ffi_kernel.dart';
import '../../platform/stub_kernel.dart';
import '../../platform/windows_system_kernel.dart';
import '../../services/config_service.dart';
import '../plugin/abi_utils.dart';
import '../plugin/plugin_manager.dart';
import 'browser_kernel.dart';
import 'kernel_manager.dart';
import 'kernel_types.dart';

/// 可选用内核描述（供内核管理页与设置页展示）
class KernelDescriptor {
  final String id;
  final String displayName;
  final KernelOrigin origin;
  final String? note;

  /// 引擎谱系
  final KernelEngine engine;

  /// 引擎/内核版本
  final String? version;

  /// 当前平台是否可直接使用
  final bool available;

  /// 声明的能力位
  final Set<KernelCapability> capabilities;

  /// 独立内核包 id（origin == standalone 时非空）
  final String? packageId;

  /// 独立内核包占用字节数
  final int? sizeBytes;

  /// 不可用原因（available == false 时展示）
  final String? unavailableReason;

  const KernelDescriptor({
    required this.id,
    required this.displayName,
    required this.origin,
    this.note,
    this.engine = KernelEngine.custom,
    this.version,
    this.available = true,
    this.capabilities = const {},
    this.packageId,
    this.sizeBytes,
    this.unavailableReason,
  });
}

/// 内核注册表：枚举可用内核（系统 / 独立安装包 / 插件携带）、按配置实例化
class KernelRegistry {
  final ConfigService config;
  final PluginManager pluginManager;

  /// 独立内核包管理器（可为空：单元测试等场景）
  final KernelManager? kernelManager;

  KernelRegistry({
    required this.config,
    required this.pluginManager,
    this.kernelManager,
  });

  /// 平台默认系统内核 id
  static String get defaultSystemKernelId {
    if (Platform.isAndroid) return 'system.android_webview';
    if (Platform.isWindows) return 'system.windows_webview2';
    if (Platform.isLinux) return 'system.linux_webkit';
    return 'system.unsupported';
  }

  /// 当前平台是否已支持（系统内核）
  static bool get platformSupported =>
      Platform.isAndroid || Platform.isWindows || Platform.isLinux;

  /// 系统内核是否可用（自动探测）
  static bool systemKernelAvailable() {
    if (Platform.isAndroid) return true; // 系统组件，恒可用
    if (Platform.isWindows) {
      return WindowsSystemKernel.environmentWarning == null;
    }
    if (Platform.isLinux) return LinuxWebKitKernel.nativeAvailable;
    return false;
  }

  static String? _systemUnavailableReason() {
    if (Platform.isWindows) return WindowsSystemKernel.environmentWarning;
    if (Platform.isLinux && !LinuxWebKitKernel.nativeAvailable) {
      return '未检测到 WebKitGTK 原生视图（需 libwebkit2gtk-4.1 并启用平台插件）';
    }
    return null;
  }

  /// 枚举全部可用内核：系统内核 + 已安装独立内核包 + 插件携带内核
  List<KernelDescriptor> describe() {
    final result = <KernelDescriptor>[];

    result.add(_systemDescriptor());

    // 独立安装包内核
    final km = kernelManager;
    if (km != null) {
      final key = _platformKeyFor();
      final abi = Platform.isAndroid ? currentAndroidAbiFolder() : null;
      for (final pkg in km.kernels) {
        final ok = !pkg.isTampered && pkg.availableOn(key, abi: abi);
        result.add(KernelDescriptor(
          id: pkg.kernelId,
          displayName: pkg.manifest.title,
          origin: KernelOrigin.standalone,
          engine: pkg.manifest.engine,
          version: pkg.manifest.version,
          available: ok,
          capabilities: pkg.manifest.capabilitySet,
          packageId: pkg.id,
          sizeBytes: pkg.sizeBytes,
          note: pkg.manifest.description,
          unavailableReason: pkg.isTampered
              ? '安装目录已被修改，已拒绝加载'
              : (ok
                  ? null
                  : '该内核包未包含当前平台（$key）的产物'),
        ));
      }
    }

    // zip 插件携带的内核
    for (final offer in pluginManager.availablePluginKernels()) {
      final isFixed = offer.spec.type == 'webview2_fixed';
      result.add(KernelDescriptor(
        id: offer.kernelId,
        displayName: offer.displayName,
        origin: KernelOrigin.plugin,
        engine: isFixed ? KernelEngine.chromium : KernelEngine.custom,
        available: true,
        capabilities: offer.capabilities,
        note: isFixed
            ? '插件携带的 WebView2 Fixed Version 固定内核'
            : '插件 FFI 原生内核（ABI v${offer.spec.abiVersion}）',
      ));
    }

    return result;
  }

  KernelDescriptor _systemDescriptor() {
    final available = systemKernelAvailable();
    final reason = _systemUnavailableReason();
    if (Platform.isAndroid) {
      return KernelDescriptor(
        id: 'system.android_webview',
        displayName: 'Android System WebView（系统）',
        origin: KernelOrigin.system,
        engine: KernelEngine.system,
        available: available,
        capabilities: const {
          KernelCapability.loadUrl,
          KernelCapability.evaluateJs,
          KernelCapability.userScripts,
          KernelCapability.multiTab,
          KernelCapability.download,
          KernelCapability.privateSession,
        },
        note: '由系统组件 com.google.android.webview 提供',
        unavailableReason: reason,
      );
    }
    if (Platform.isWindows) {
      return KernelDescriptor(
        id: 'system.windows_webview2',
        displayName: 'WebView2 · Evergreen（系统）',
        origin: KernelOrigin.system,
        engine: KernelEngine.chromium,
        available: available,
        capabilities: const {
          KernelCapability.loadUrl,
          KernelCapability.evaluateJs,
          KernelCapability.userScripts,
          KernelCapability.multiTab,
          KernelCapability.download,
          KernelCapability.schemeIntercept,
          KernelCapability.privateSession,
        },
        note: '由系统 Edge Chromium Runtime 提供',
        unavailableReason: reason,
      );
    }
    if (Platform.isLinux) {
      return KernelDescriptor(
        id: 'system.linux_webkit',
        displayName: 'WebKitGTK（系统）',
        origin: KernelOrigin.system,
        engine: KernelEngine.system,
        available: available,
        capabilities: const {
          KernelCapability.loadUrl,
          KernelCapability.evaluateJs,
          KernelCapability.userScripts,
          KernelCapability.download,
        },
        note: '依赖 libwebkit2gtk-4.1；未就绪时可改用独立内核包',
        unavailableReason: reason,
      );
    }
    return const KernelDescriptor(
      id: 'system.unsupported',
      displayName: '当前平台暂不支持',
      origin: KernelOrigin.system,
      engine: KernelEngine.system,
      available: false,
      note: '可安装独立内核包以启用网页渲染',
      unavailableReason: '宿主未提供该平台的系统 WebView',
    );
  }

  /// 创建一个内核实例（每个标签页一个）
  BrowserKernel createKernel(String tabId) {
    final selected = config.selectedKernelId;

    if (selected != null && selected.startsWith('kernel.')) {
      final pkg = kernelManager?.byKernelId(selected);
      if (pkg != null) {
        final offer = StandaloneKernelOffer(pkg);
        if (offer.type == 'webview2_fixed' && offer.runtimeDir != null) {
          return WindowsSystemKernel(fixedRuntimeDir: offer.runtimeDir);
        }
        return FfiBrowserKernel(source: offer);
      }
      // 已安装包被删除/损坏：回退系统内核，避免开标签页失败
      return createSystemKernel();
    }

    if (selected != null && selected.startsWith('plugin.')) {
      for (final offer in pluginManager.availablePluginKernels()) {
        if (offer.kernelId == selected) {
          if (offer.spec.type == 'webview2_fixed' && offer.runtimeDir != null) {
            return WindowsSystemKernel(fixedRuntimeDir: offer.runtimeDir);
          }
          return FfiBrowserKernel(source: offer);
        }
      }
    }
    return createSystemKernel();
  }

  /// 直接创建系统内核
  BrowserKernel createSystemKernel() {
    if (Platform.isAndroid) return AndroidSystemKernel();
    if (Platform.isWindows) return WindowsSystemKernel();
    if (Platform.isLinux) return LinuxWebKitKernel();
    return StubKernel();
  }

  /// 当前生效的内核描述（找不到时回退系统内核描述）
  KernelDescriptor effectiveDescriptor() {
    final selected = config.selectedKernelId;
    final all = describe();
    if (selected != null) {
      for (final d in all) {
        if (d.id == selected) return d;
      }
    }
    for (final d in all) {
      if (d.id == defaultSystemKernelId) return d;
    }
    return all.first;
  }

  static String _platformKeyFor() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }
}
