import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../kernel/kernel_source.dart';
import '../kernel/kernel_types.dart';
import '../../services/paths.dart';
import 'abi_utils.dart';
import 'extension_importer.dart';
import 'plugin_manifest.dart';
import 'plugin_package.dart';
import 'plugin_security.dart';

/// 权限名 -> 可调用的 bridge 方法
const Map<String, List<String>> kPermissionBridgeMethods = {
  'tabs': [
    'tabs.create', 'tabs.close', 'tabs.update', 'tabs.query', 'tabs.active',
  ],
  'storage': ['storage.get', 'storage.set', 'storage.remove', 'storage.keys'],
  'webNavigation': ['webNavigation.getFrame', 'webNavigation.getAllFrames'],
  'downloads': ['downloads.create', 'downloads.query'],
  'nativeMessaging': ['nativeMessaging.send', 'nativeMessaging.connect'],
  'menus': ['menus.create', 'menus.remove', 'menus.onClick'],
  'kernel': ['kernel.query', 'kernel.switch'],
  'cookies': ['cookies.get', 'cookies.set', 'cookies.remove'],
  'notifications': ['notifications.create'],
};

/// 平台上可用的插件内核描述
class PluginKernelOffer implements KernelSource {
  final InstalledPlugin plugin;
  final PluginKernelSpec spec;

  /// 原生库绝对路径（ffi 类型）
  @override
  final String? libraryPath;

  /// Fixed Version 运行时绝对目录（webview2_fixed 类型）
  @override
  final String? runtimeDir;

  const PluginKernelOffer({
    required this.plugin,
    required this.spec,
    this.libraryPath,
    this.runtimeDir,
  });

  @override
  String get kernelId => 'plugin.${plugin.id}';
  @override
  String get displayName => spec.displayName ?? '${plugin.manifest.name} 内核';
  @override
  String get type => spec.type;
  @override
  int get abiVersion => spec.abiVersion;
  @override
  KernelOrigin get origin => KernelOrigin.plugin;
  @override
  Set<KernelCapability> get capabilities => const {
        KernelCapability.loadUrl,
        KernelCapability.evaluateJs,
        KernelCapability.userScripts,
        KernelCapability.multiTab,
      };
}

/// 插件管理器：安装 / 卸载 / 启停 / 能力收集
class PluginManager extends ChangeNotifier {
  final Directory pluginsDir;
  final TrustedPlugins trusted;

  /// 被篡改而拒绝加载的插件目录名（用于 UI 告警）
  final List<String> tamperedPluginIds = [];

  PluginManager({
    required this.pluginsDir,
    this.trusted = const TrustedPlugins({}),
  });

  final List<InstalledPlugin> _plugins = [];

  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);

  List<InstalledPlugin> get enabledPlugins =>
      _plugins.where((e) => e.enabled && !e.isTampered).toList();

  InstalledPlugin? byId(String id) {
    for (final pl in _plugins) {
      if (pl.id == id) return pl;
    }
    return null;
  }

  /// 扫描插件目录
  void loadAll() {
    _plugins.clear();
    tamperedPluginIds.clear();
    if (!pluginsDir.existsSync()) {
      pluginsDir.createSync(recursive: true);
      return;
    }
    for (final entity in pluginsDir.listSync()) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }
      final installed = InstalledPlugin.load(entity);
      if (installed == null) continue;
      if (installed.isTampered) {
        tamperedPluginIds.add(installed.id);
        // 被篡改的插件强制停用
        installed.enabled = false;
      }
      _plugins.add(installed);
    }
    _plugins.sort((a, b) => a.manifest.name.compareTo(b.manifest.name));
    notifyListeners();
  }

  /// 从 zip 文件安装，返回新插件
  Future<InstalledPlugin> installFromZipFile(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    return installFromBytes(bytes);
  }

  /// 从浏览器扩展文件（.crx / .xpi / .zip）安装。
  /// 自动识别格式并转换为宿主插件清单后安装。
  Future<InstalledPlugin> installFromExtensionFile(File file) async {
    final bytes = await file.readAsBytes();
    final name = file.path.toLowerCase();
    final normalized = name.endsWith('.crx')
        ? ExtensionImporter.fromCrx(bytes)
        : name.endsWith('.xpi')
            ? ExtensionImporter.fromXpi(bytes)
            : ExtensionImporter.autoImport(bytes);
    return installFromBytes(normalized);
  }

  /// 从 zip 字节安装（处理同名升级：保留原启用状态）
  InstalledPlugin installFromBytes(List<int> zipBytes) {
    final previouslyEnabled = _enabledIds();
    final record = PluginPackage.install(
      zipBytes: zipBytes,
      pluginsDir: pluginsDir,
      trusted: trusted.isEmpty ? null : trusted,
    );
    record.enabled = previouslyEnabled.contains(record.id) || !_exists(record.id);
    _persistEnabled(record);
    loadAll();
    return record;
  }

  Future<void> uninstall(String id) async {
    final target = byId(id);
    target?.directory.deleteSync(recursive: true);
    loadAll();
  }

  void setEnabled(String id, bool enabled) {
    final target = byId(id);
    if (target == null || target.isTampered) return;
    target.enabled = enabled;
    _persistEnabled(target);
    notifyListeners();
  }

  Set<String> _enabledIds() =>
      _plugins.where((e) => e.enabled).map((e) => e.id).toSet();

  bool _exists(String id) => byId(id) != null;

  void _persistEnabled(InstalledPlugin plugin) {
    final recordFile = File(p.join(plugin.directory.path, 'install.json'));
    final raw = recordFile.existsSync()
        ? jsonDecode(recordFile.readAsStringSync()) as Map<String, dynamic>
        : plugin.installRecordJson();
    raw['enabled'] = plugin.enabled;
    recordFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(raw),
    );
  }

  // —— 能力收集 ——

  /// 汇总所有启用插件被授予的 bridge 方法
  Set<String> grantedBridgeMethods() {
    final result = <String>{};
    for (final plugin in enabledPlugins) {
      for (final permission in plugin.manifest.permissions) {
        result.addAll(kPermissionBridgeMethods[permission] ?? const []);
      }
    }
    return result;
  }

  /// 收集需要注入页面的全部用户脚本
  List<UserScript> collectUserScripts() {
    final scripts = <UserScript>[];
    for (final plugin in enabledPlugins) {
      for (final rule in plugin.manifest.contentScripts) {
        if (rule.js.isEmpty) continue;
        final buffer = StringBuffer();
        var ok = true;
        for (final jsPath in rule.js) {
          final file = plugin.resolveFile(jsPath);
          if (!file.existsSync()) {
            ok = false;
            break;
          }
          buffer.writeln('// ${plugin.id} :: $jsPath');
          buffer.writeln(file.readAsStringSync());
        }
        if (!ok) continue;
        scripts.add(UserScript(
          source: buffer.toString(),
          matches: rule.matches,
          timing: rule.runAt == 'document_start'
              ? UserScriptInjectionTiming.documentStart
              : UserScriptInjectionTiming.documentEnd,
          pluginId: plugin.id,
        ));
      }
    }
    return scripts;
  }

  /// 收集当前平台可使用的插件内核
  List<PluginKernelOffer> availablePluginKernels() {
    final offers = <PluginKernelOffer>[];
    final key = AppPaths.platformKey;
    for (final plugin in enabledPlugins) {
      final spec = plugin.manifest.kernel;
      if (spec == null || !plugin.manifest.hasPermission('kernel')) continue;

      if (spec.type == 'webview2_fixed' && key == 'windows') {
        final dir = spec.runtimeDir;
        offers.add(PluginKernelOffer(
          plugin: plugin,
          spec: spec,
          runtimeDir: dir == null
              ? null
              : p.join(plugin.directory.path, dir.replaceAll('/', p.separator)),
        ));
      } else if (spec.type == 'ffi') {
        final libRel =
            spec.libraryRelativeFor(key, abi: currentAndroidAbiFolder());
        if (libRel == null) continue;
        final libFile = plugin.resolveFile(libRel);
        if (!libFile.existsSync()) continue;
        offers.add(PluginKernelOffer(
          plugin: plugin,
          spec: spec,
          libraryPath: libFile.path,
        ));
      }
    }
    return offers;
  }

  /// 工具栏按钮扩展
  List<InstalledPlugin> toolbarPlugins() => enabledPlugins
      .where((e) => e.manifest.ui?.toolbarButton != null)
      .toList();
}
