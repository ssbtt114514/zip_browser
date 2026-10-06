import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/script/userscript_manager.dart';

/// 用户脚本管理页：导入 / 启停 / 删除 / 查看
class UserscriptsPage extends StatelessWidget {
  const UserscriptsPage({super.key});

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['js', 'user'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    final source = String.fromCharCodes(result.files.single.bytes!);
    final manager = context.read<UserscriptManager>();
    final imported = manager.importFromSource(
      source,
      filename: result.files.single.name,
    );
    if (imported == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('导入失败：未找到有效的用户脚本元数据头')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('已导入：${imported.meta.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<UserscriptManager>();
    final scripts = manager.scripts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('用户脚本'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入 .user.js',
            onPressed: () => _import(context),
          ),
        ],
      ),
      body: scripts.isEmpty
          ? const _EmptyHint()
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: scripts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ScriptCard(script: scripts[i]),
            ),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  final InstalledUserScript script;
  const _ScriptCard({required this.script});

  @override
  Widget build(BuildContext context) {
    final meta = script.meta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.code, color: Colors.orange),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${meta.name}${meta.version != null ? '  v${meta.version}' : ''}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5),
                      ),
                      if (meta.author != null)
                        Text(meta.author!,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.black45)),
                    ],
                  ),
                ),
                Switch(
                  value: script.enabled,
                  onChanged: (v) => context
                      .read<UserscriptManager>()
                      .setEnabled(script.id, v),
                ),
              ],
            ),
            if (meta.description != null) ...[
              const SizedBox(height: 6),
              Text(meta.description!,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final m in meta.matches.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(m,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.blueGrey.shade600)),
                  ),
                if (meta.matches.length > 4)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('+${meta.matches.length - 4}',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.blueGrey.shade600)),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: Icon(Icons.visibility_outlined,
                      size: 17, color: Theme.of(context).colorScheme.primary),
                  label: Text('源码',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.primary)),
                  onPressed: () => _viewSource(context),
                ),
                TextButton.icon(
                  icon: Icon(Icons.delete_outline,
                      size: 17, color: Colors.red.shade400),
                  label: Text('删除',
                      style: TextStyle(
                          color: Colors.red.shade400, fontSize: 12.5)),
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewSource(BuildContext context) async {
    final source = script.meta.source;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${script.meta.name} · 源码')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              source,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12.5, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('删除 ${script.meta.name}？'),
        content: const Text('该脚本将被永久删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<UserscriptManager>().remove(script.id);
    }
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
          Icon(Icons.javascript_outlined, size: 56, color: Colors.black26),
          SizedBox(height: 14),
          Text('还没有用户脚本', style: TextStyle(color: Colors.black45)),
          SizedBox(height: 6),
          Text('点击右上角导入 .user.js 文件',
              style: TextStyle(color: Colors.black38, fontSize: 12.5)),
        ],
      ),
    );
  }
}
