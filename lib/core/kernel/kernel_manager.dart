import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../services/paths.dart';
import '../plugin/abi_utils.dart';
import '../plugin/plugin_security.dart';
import 'kernel_package.dart';
import 'kernel_source.dart';
import 'kernel_types.dart';

/// 独立安装包内核在某平台上的可加载来源
class StandaloneKernelOffer implements KernelSource {
  final InstalledKernel package;

  final String? _libraryPath;
  final String? _runtimeDir;

  StandaloneKernelOffer(this.package)
      : _libraryPath = package.libraryPathFor(
          AppPaths.platformKey,
          abi: Platform.isAndroid ? currentAndroidAbiFolder() : null,
        ),
        _runtimeDir = package.runtimeDirPath;

  InstalledKernel get installed => package;

  @override
  String get kernelId => package.kernelId;
  @override
  String get displayName => package.manifest.title;
  @override
  String get type => package.manifest.type;
  @override
  int get abiVersion => package.manifest.abiVersion;
  @override
  KernelOrigin get origin => KernelOrigin.standalone;
  @override
  Set<KernelCapability> get capabilities => package.manifest.capabilitySet;
  @override
  String? get libraryPath => _libraryPath;
  @override
  String? get runtimeDir => _runtimeDir;
}

/// 独立内核包管理器：扫描 / 安装 / 卸载 / 平台可用性判定。
///
/// 内核以独立安装包（.zbk）形式分发，安装到 `AppPaths.kernelsDir/<id>`，
/// 与 zip 插件相互解耦：插件负责功能扩展，内核包负责渲染引擎。
class KernelManager extends ChangeNotifier {
  final Directory kernelsDir;
  final TrustedPlugins trusted;

  /// 因目录被篡改而拒绝加载的包 id（用于 UI 告警）
  final List<String> tamperedKernelIds = [];

  KernelManager({
    required this.kernelsDir,
    this.trusted = const TrustedPlugins({}),
  });

  final List<InstalledKernel> _kernels = [];

  List<InstalledKernel> get kernels => List.unmodifiable(_kernels);

  /// 可正常加载的包（未被篡改）
  List<InstalledKernel> get trustedKernels =>
      _kernels.where((k) => !k.isTampered).toList();

  InstalledKernel? byId(String id) {
    for (final k in _kernels) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// 按宿主内核 id（`kernel.<pkgId>`）查找
  InstalledKernel? byKernelId(String kernelId) {
    if (!kernelId.startsWith('kernel.')) return null;
    return byId(kernelId.substring('kernel.'.length));
  }

  static String? get _platformKey => AppPaths.platformKey;

  static String? get _androidAbi {
    if (!Platform.isAndroid) return null;
    return currentAndroidAbiFolder();
  }

  /// 当前平台开箱可用（声明且产物存在）的内核包
  List<InstalledKernel> availableHere() {
    final key = _platformKey;
    if (key == null) return const [];
    return trustedKernels
        .where((k) => k.availableOn(key, abi: _androidAbi))
        .toList();
  }

  /// 已安装但当前平台缺少产物（例如只装了 Windows 版）的内核包
  List<InstalledKernel> unavailableHere() {
    final key = _platformKey;
    if (key == null) return trustedKernels.toList();
    return trustedKernels
        .where((k) => !k.availableOn(key, abi: _androidAbi))
        .toList();
  }

  /// 扫描内核目录（启动时调用）
  void loadAll() {
    _kernels.clear();
    tamperedKernelIds.clear();
    if (!kernelsDir.existsSync()) {
      kernelsDir.createSync(recursive: true);
      notifyListeners();
      return;
    }
    for (final entity in kernelsDir.listSync()) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      // 跳过暂存目录与隐藏目录
      if (name.startsWith('.')) continue;
      final installed = InstalledKernel.load(entity);
      if (installed == null) continue;
      if (installed.isTampered) {
        tamperedKernelIds.add(installed.id);
      }
      _kernels.add(installed);
    }
    _kernels.sort((a, b) => a.manifest.name.compareTo(b.manifest.name));
    notifyListeners();
  }

  /// 从文件安装
  Future<InstalledKernel> installFromFile(File file) async {
    final bytes = await file.readAsBytes();
    return installFromBytes(bytes);
  }

  /// 从字节安装，安装后自动刷新
  InstalledKernel installFromBytes(List<int> bytes) {
    final record = KernelPackage.install(
      zipBytes: bytes,
      kernelsDir: kernelsDir,
      trusted: trusted.isEmpty ? null : trusted,
    );
    loadAll();
    return record;
  }

  /// 卸载内核包
  Future<void> uninstall(String id) async {
    final target = byId(id);
    if (target == null) return;
    if (target.directory.existsSync()) {
      target.directory.deleteSync(recursive: true);
    }
    loadAll();
  }
}
