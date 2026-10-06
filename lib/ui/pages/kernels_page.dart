import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/kernel/kernel_manager.dart';
import '../../core/kernel/kernel_manifest.dart';
import '../../core/kernel/kernel_package.dart';
import '../../core/kernel/kernel_registry.dart';
import '../../core/kernel/kernel_types.dart';
import '../../services/config_service.dart';
import '../../services/paths.dart';

/// 内核管理页：以「独立安装包」为单位安装 / 切换 / 卸载浏览器内核。
///
/// 内核来源有三类：
///   * 系统内核（Android System WebView / WebView2 / WebKitGTK）
///   * 独立内核包（.zbk，本页主推）
///   * zip 插件携带的内核
class KernelsPage extends StatelessWidget {
  const KernelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<KernelManager>();
    final registry = context.read<KernelRegistry>();
    final config = context.watch<ConfigService>();
    final selected = config.selectedKernelId ??
        KernelRegistry.defaultSystemKernelId;
    final kernels = registry.describe();

    return Scaffold(
      appBar: AppBar(
        title: const Text('内核管理'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add_box_outlined, size: 19),
            label: const Text('安装'),
            onPressed: () => _installKernel(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const _IntroCard(),
          if (manager.tamperedKernelIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            _TamperBanner(count: manager.tamperedKernelIds.length),
          ],
          const SizedBox(height: 18),

          const _SectionTitle('选择内核'),
          for (final d in kernels)
            _KernelTile(
              descriptor: d,
              selected: d.id == selected,
              onSelect: d.available
                  ? () => _selectKernel(context, d)
                  : null,
            ),
          const SizedBox(height: 20),

          const _SectionTitle('已安装的独立内核包'),
          if (manager.kernels.isEmpty)
            _EmptyPackages(onInstall: () => _installKernel(context))
          else
            for (final pkg in manager.kernels)
              _PackageCard(
                package: pkg,
                available: manager.availableHere().any((k) => k.id == pkg.id),
                selected: pkg.kernelId == selected,
                onSelect: () => _selectKernelById(context, pkg.kernelId),
                onUninstall: () => _uninstall(context, pkg),
              ),
          const SizedBox(height: 18),

          const _SectionTitle('内核包目录'),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: Text(
                AppPaths.kernelsDir.path,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('手动放入 .zbk 解压后的目录同样会被自动探测',
                  style: TextStyle(fontSize: 11.5)),
            ),
          ),
        ],
      ),
    );
  }

  // —— 动作 ——

  Future<void> _installKernel(BuildContext context) async {
    // async gap 前取齐依赖
    final manager = context.read<KernelManager>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zbk', 'zip'],
      withData: true,
    );
    if (result == null) return;
    final picked = result.files.single;

    try {
      final InstalledKernel record;
      if (picked.bytes != null) {
        record = manager.installFromBytes(picked.bytes!);
      } else if (picked.path != null) {
        record = await manager.installFromFile(File(picked.path!));
      } else {
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text('已安装内核：${record.manifest.title} '
            'v${record.manifest.version}'),
      ));
    } on KernelInstallException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('内核包安装失败：${e.reasons.join('；')}'),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('安装失败：$e')));
    }
  }

  Future<void> _selectKernel(BuildContext context, KernelDescriptor d) =>
      _selectKernelById(context, d.id, label: d.displayName);

  Future<void> _selectKernelById(
    BuildContext context,
    String id, {
    String? label,
  }) async {
    final config = context.read<ConfigService>();
    final messenger = ScaffoldMessenger.of(context);
    await config.setSelectedKernelId(id);
    messenger.showSnackBar(SnackBar(
      content: Text('已切换内核：${label ?? id}（新建标签页生效）'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _uninstall(BuildContext context, InstalledKernel pkg) async {
    final manager = context.read<KernelManager>();
    final config = context.read<ConfigService>();
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('卸载 ${pkg.manifest.title}？'),
        content: const Text('将删除该内核包的全部文件；已打开的标签页不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('卸载')),
        ],
      ),
    );
    if (ok != true) return;

    if (config.selectedKernelId == pkg.kernelId) {
      await config.setSelectedKernelId(null);
    }
    await manager.uninstall(pkg.id);
    messenger.showSnackBar(
        const SnackBar(content: Text('内核包已卸载'), duration: Duration(seconds: 2)));
  }
}

// —— 顶部说明卡 ——

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.memory_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '浏览器内核以「独立安装包」（.zbk）分发，与功能插件相互解耦。\n'
              '安装后自动探测并按平台加载：FFI 原生库或 WebView2 固定版本运行时。\n'
              '「引擎适配包」（type: engine_adapter）是例外：它只探测本机引擎运行时，'
              '不提供网页渲染。',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _TamperBanner extends StatelessWidget {
  final int count;
  const _TamperBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.gpp_bad, color: Colors.red.shade400, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '检测到 $count 个内核包目录与安装记录不一致，已拒绝加载。',
              style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

// —— 单个内核选项 ——

class _KernelTile extends StatelessWidget {
  final KernelDescriptor descriptor;
  final bool selected;
  final VoidCallback? onSelect;

  const _KernelTile({
    required this.descriptor,
    required this.selected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = descriptor;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.black12,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_engineIcon(d.engine),
                      size: 20,
                      color: d.available ? scheme.primary : Colors.black26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.displayName,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${d.engine.label}'
                          '${d.version == null ? '' : ' · v${d.version}'}'
                          ' · ${_originLabel(d.origin)}'
                          '${d.sizeBytes == null ? '' : ' · ${_fmtSize(d.sizeBytes!)}'}',
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, size: 20, color: scheme.primary)
                  else if (!d.available)
                    Tooltip(
                      message: d.unavailableReason ?? '当前平台不可用',
                      child: const Icon(Icons.error_outline,
                          size: 18, color: Colors.orange),
                    ),
                ],
              ),
              if (d.note != null) ...[
                const SizedBox(height: 6),
                Text(d.note!,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.black54)),
              ],
              if (!d.available && d.unavailableReason != null) ...[
                const SizedBox(height: 4),
                Text(d.unavailableReason!,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.orange)),
              ],
              if (d.capabilities.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final c in d.capabilities) _CapChip(c),
                  ],
                ),
              ],
              // 引擎适配包：明确告知它不渲染网页，避免"已选中=能上网"的误解
              if (d.packageType == 'engine_adapter') ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber,
                        size: 15, color: Colors.amber.shade800),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '引擎适配包：只探测本机引擎运行时，不提供网页渲染',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.brown.shade700),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CapChip extends StatelessWidget {
  final KernelCapability capability;
  const _CapChip(this.capability);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        capability.label,
        style: TextStyle(fontSize: 10.5, color: Colors.blueGrey.shade600),
      ),
    );
  }
}

// —— 已安装内核包卡片 ——

class _PackageCard extends StatelessWidget {
  final InstalledKernel package;
  final bool available;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onUninstall;

  const _PackageCard({
    required this.package,
    required this.available,
    required this.selected,
    required this.onSelect,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final m = package.manifest;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${m.title}  v${m.version}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle,
                        size: 18, color: Colors.teal),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${m.id} · ${m.engine.label} · '
              '${kernelTypeLabel(m.type, abiVersion: m.abiVersion)}',
              style: const TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              '占用 ${_fmtSize(package.sizeBytes)} · 安装于 '
              '${package.installedAt.toLocal().toString().split(".").first}',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
            const SizedBox(height: 4),
            Text(
              '平台支持：${_platformSummary(m)}'
              '${available ? '' : '（当前平台缺少产物，不可用）'}',
              style: TextStyle(
                fontSize: 11,
                color: available ? Colors.black45 : Colors.orange.shade700,
              ),
            ),
            if (package.isTampered)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('内容与安装记录不一致，已阻止加载',
                    style:
                        TextStyle(fontSize: 11.5, color: Colors.red.shade400)),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SHA-256 ${_shortHash(package.zipSha256)}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black38),
                ),
                Row(
                  children: [
                    if (available && !selected)
                      TextButton(
                        onPressed: onSelect,
                        child: const Text('设为当前',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    TextButton.icon(
                      icon: Icon(Icons.delete_outline,
                          size: 17, color: Colors.red.shade400),
                      label: Text('卸载',
                          style: TextStyle(
                              color: Colors.red.shade400, fontSize: 12.5)),
                      onPressed: onUninstall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPackages extends StatelessWidget {
  final VoidCallback onInstall;
  const _EmptyPackages({required this.onInstall});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Colors.black26),
            const SizedBox(height: 12),
            const Text('还没有安装独立内核包',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            const Text('当前使用系统自带内核，可安装更多内核以获得更完整的渲染能力',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black38, fontSize: 12.5)),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text('导入内核包 (.zbk)'),
              onPressed: onInstall,
            ),
          ],
        ),
      ),
    );
  }
}

// —— 小组件与工具 ——

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

IconData _engineIcon(KernelEngine engine) {
  switch (engine) {
    case KernelEngine.chromium:
      return Icons.travel_explore;
    case KernelEngine.gecko:
      return Icons.local_fire_department_outlined;
    case KernelEngine.system:
      return Icons.android;
    case KernelEngine.custom:
      return Icons.memory;
  }
}

String _originLabel(KernelOrigin origin) {
  switch (origin) {
    case KernelOrigin.system:
      return '系统内核';
    case KernelOrigin.standalone:
      return '独立安装包';
    case KernelOrigin.plugin:
      return '插件携带';
  }
}

String _fmtSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

String _shortHash(String hash) =>
    hash.length > 16 ? '${hash.substring(0, 16)}…' : hash;

String _platformSummary(KernelManifest manifest) {
  // 引擎适配包不携带平台产物，它在所有平台都可安装/可选（但不渲染网页）
  if (manifest.type == 'engine_adapter') return '全平台（适配器，无平台产物）';
  final libs = manifest.libraries;
  final parts = <String>[];
  for (final entry in libs.entries) {
    if (entry.value is Map) {
      final abis = (entry.value as Map).keys.join('/');
      parts.add('${entry.key}($abis)');
    } else {
      parts.add(entry.key);
    }
  }
  if (manifest.runtimeDir != null) parts.add('runtime');
  return parts.isEmpty ? '未声明' : parts.join('、');
}
