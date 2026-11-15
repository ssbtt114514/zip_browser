import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/kernel/kernel_manager.dart';
import '../../core/kernel/kernel_registry.dart';
import '../../core/kernel/kernel_types.dart';
import '../../services/config_service.dart';

/// 内核管理页：切换内核、安装 `.zbk` 内核包、卸载独立内核包。
///
/// 切换只影响新建标签页；已存在标签页保留原内核实例，界面上以提示语说明。
class KernelsPage extends StatelessWidget {
  const KernelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final km = context.watch<KernelManager>();
    final registry = context.read<KernelRegistry>();
    final config = context.watch<ConfigService>();
    final descriptors = registry.describe();
    final selectedId = config.selectedKernelId;

    final builtin =
        descriptors.where((d) => d.origin != KernelOrigin.standalone).toList();
    final standalone =
        descriptors.where((d) => d.origin == KernelOrigin.standalone).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览器内核'),
        actions: [
          IconButton(
            tooltip: '安装内核包（.zbk）',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _install(context),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              if (km.tamperedKernelIds.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.gpp_bad_outlined,
                          size: 18, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '检测到 ${km.tamperedKernelIds.length} 个内核包目录被修改，已拒绝加载：'
                          '${km.tamperedKernelIds.join('、')}',
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.red.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              const _SectionTitle('内核选择'),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    _DefaultKernelTile(
                      selected: selectedId == null,
                      onTap: () => _select(context, null),
                    ),
                    for (final d in builtin) ...[
                      const Divider(height: 1, indent: 56),
                      _KernelTile(
                        descriptor: d,
                        selected: selectedId == d.id,
                        onTap: d.available
                            ? () => _select(context, d.id)
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _SectionTitle('独立内核包'),
              Card(
                margin: EdgeInsets.zero,
                child: standalone.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 18),
                        child: Text(
                          '尚未安装独立内核包。点击右上角按钮安装 .zbk 内核包。',
                          style: TextStyle(fontSize: 13),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < standalone.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 56),
                            _KernelTile(
                              descriptor: standalone[i],
                              selected: selectedId == standalone[i].id,
                              onTap: standalone[i].available
                                  ? () => _select(context, standalone[i].id)
                                  : null,
                              onUninstall: standalone[i].available
                                  ? () => _uninstall(
                                      context,
                                      standalone[i],
                                      isSelected:
                                          selectedId == standalone[i].id,
                                    )
                                  : null,
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                '切换后新标签页使用所选内核，已打开的标签页保持原内核；'
                '可关闭并重新打开标签以立即切换。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _select(BuildContext context, String? id) async {
    final config = context.read<ConfigService>();
    await config.setSelectedKernelId(id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(id == null ? '已恢复平台默认内核' : '已切换内核，新标签页生效'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _install(BuildContext context) async {
    final km = context.read<KernelManager>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zbk'],
        withData: false,
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      await km.installFromFile(File(path));
      messenger.showSnackBar(
        const SnackBar(content: Text('内核包安装完成'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('安装失败：$e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _uninstall(
    BuildContext context,
    KernelDescriptor descriptor, {
    required bool isSelected,
  }) async {
    final km = context.read<KernelManager>();
    final config = context.read<ConfigService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载内核包'),
        content: Text('确定卸载「${descriptor.displayName}」？该操作会删除安装目录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (isSelected) await config.setSelectedKernelId(null);
    await km.uninstall(descriptor.packageId ?? '');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('内核包已卸载'), duration: Duration(seconds: 2)),
    );
  }
}

class _DefaultKernelTile extends StatelessWidget {
  const _DefaultKernelTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.auto_mode, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('平台默认', style: TextStyle(fontSize: 14.5)),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '由当前平台与构建风味决定，内核包卸载后回到此选项',
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? scheme.primary : scheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _KernelTile extends StatelessWidget {
  const _KernelTile({
    required this.descriptor,
    required this.selected,
    this.onTap,
    this.onUninstall,
  });

  final KernelDescriptor descriptor;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = descriptor;
    final meta = <String>[
      d.engine.label,
      if (d.version != null) 'v${d.version}',
      _originLabel(d.origin),
      if (d.sizeBytes != null) _sizeText(d.sizeBytes!),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              _engineIcon(d.engine),
              size: 20,
              color: d.available ? scheme.onSurfaceVariant : scheme.outline,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.displayName,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: d.available ? null : scheme.outline,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      meta,
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (!d.available && d.unavailableReason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        d.unavailableReason!,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.orange.shade800),
                      ),
                    ),
                ],
              ),
            ),
            if (onUninstall != null)
              IconButton(
                tooltip: '卸载',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onUninstall,
              ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: !d.available
                  ? scheme.outline
                  : (selected ? scheme.primary : scheme.outline),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
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

String _sizeText(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
