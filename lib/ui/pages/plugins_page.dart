import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/plugin/extension_importer.dart';
import '../../core/plugin/plugin_manager.dart';
import '../../core/plugin/plugin_package.dart';

/// 插件管理页：安装 zip / 启停 / 卸载 / 查看权限与指纹
class PluginsPage extends StatelessWidget {
  const PluginsPage({super.key});

  Future<void> _install(BuildContext context) async {
    // await 之前取齐 context 依赖，避免 async gap 后使用 BuildContext
    final pm = context.read<PluginManager>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'crx', 'xpi'],
      withData: true,
    );
    if (result == null) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return;

    try {
      final lower = picked.name.toLowerCase();
      // 浏览器扩展包走转换导入
      final record = (lower.endsWith('.crx') || lower.endsWith('.xpi'))
          ? pm.installFromBytes(
              _convertExtension(bytes, lower.endsWith('.crx')))
          : pm.installFromBytes(bytes);
      messenger.showSnackBar(
        SnackBar(
            content: Text(
                '已安装：${record.manifest.name} v${record.manifest.version}'
                '（来源 ${record.manifest.source}）')),
      );
    } on PluginInstallException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('插件安装失败：${e.reasons.join('；')}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('安装失败：$e')));
    }
  }

  List<int> _convertExtension(List<int> bytes, bool isCrx) {
    return isCrx
        ? ExtensionImporter.fromCrx(bytes)
        : ExtensionImporter.fromXpi(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.watch<PluginManager>();
    final plugins = pm.plugins;

    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.file_upload_outlined, size: 19),
            label: const Text('导入扩展'),
            onPressed: () => _install(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (pm.tamperedPluginIds.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.gpp_bad, color: Colors.red.shade400, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '检测到 ${pm.tamperedPluginIds.length} 个插件目录被篡改，已强制停用：'
                      '${pm.tamperedPluginIds.join(", ")}',
                      style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: plugins.isEmpty
                ? const _EmptyHint()
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: plugins.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PluginCard(plugin: plugins[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  final InstalledPlugin plugin;
  const _PluginCard({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    final iconPath = manifest.ui?.toolbarButton?.icon;
    Widget? iconWidget;
    if (iconPath != null) {
      final file = plugin.resolveFile(iconPath);
      if (file.existsSync()) {
        iconWidget = Image.file(file, width: 38, height: 38, fit: BoxFit.contain);
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                iconWidget ??
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.extension, color: Colors.teal),
                    ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${manifest.name}  v${manifest.version}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5),
                      ),
                      if (manifest.author != null)
                        Text(manifest.author!,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.black45)),
                    ],
                  ),
                ),
                Switch(
                  value: plugin.enabled,
                  onChanged: plugin.isTampered
                      ? null
                      : (v) => context
                          .read<PluginManager>()
                          .setEnabled(plugin.id, v),
                ),
              ],
            ),
            if (manifest.description != null) ...[
              const SizedBox(height: 6),
              Text(manifest.description!,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            ],
            if (plugin.isTampered)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('插件内容与安装时不一致，已阻止加载',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final permission in manifest.permissions)
                  _PermissionChip(permission),
                if (manifest.kernel != null)
                  const _PermissionChip('kernel', highlight: true),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SHA-256：${plugin.zipSha256.length > 20 ? plugin.zipSha256.substring(0, 20) : plugin.zipSha256}…',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black38),
                ),
                TextButton.icon(
                  icon: Icon(Icons.delete_outline,
                      size: 17, color: Colors.red.shade400),
                  label: Text('卸载',
                      style: TextStyle(color: Colors.red.shade400, fontSize: 12.5)),
                  onPressed: () => _confirmUninstall(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUninstall(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('卸载 ${plugin.manifest.name}？'),
        content: const Text('将删除该插件的全部文件，其存储分区数据可保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('卸载')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<PluginManager>().uninstall(plugin.id);
    }
  }
}

class _PermissionChip extends StatelessWidget {
  final String label;
  final bool highlight;
  const _PermissionChip(this.label, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: highlight ? Colors.orange.shade50 : Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: highlight ? Colors.orange.shade700 : Colors.blueGrey.shade600,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: Colors.black26),
          SizedBox(height: 14),
          Text('还没有安装插件', style: TextStyle(color: Colors.black45)),
          SizedBox(height: 6),
          Text('点击右上角“导入扩展”选择 .zip / .crx / .xpi',
              style: TextStyle(color: Colors.black38, fontSize: 12.5)),
        ],
      ),
    );
  }
}
