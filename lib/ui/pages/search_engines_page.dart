import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/search_engines_service.dart';

/// 搜索引擎管理页：列表、设默认、添加自定义、删除
class SearchEnginesPage extends StatefulWidget {
  const SearchEnginesPage({super.key});

  @override
  State<SearchEnginesPage> createState() => _SearchEnginesPageState();
}

class _SearchEnginesPageState extends State<SearchEnginesPage> {
  @override
  Widget build(BuildContext context) {
    final service = context.watch<SearchEnginesService>();
    final engines = service.engines;

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索引擎'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加自定义',
            onPressed: () => _addEngine(context, service),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: engines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final e = engines[i];
          final isDefault = e.id == service.defaultEngine?.id;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Text(e.name),
                  if (isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('默认',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimary,
                              fontSize: 10.5)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(e.urlTemplate,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: e.builtin
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outline, size: 19),
                      color: Colors.red.shade400,
                      onPressed: () => service.remove(e.id),
                    ),
              onTap: () => service.setDefault(e.id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addEngine(
      BuildContext context, SearchEnginesService service) async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加搜索引擎'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：My Search',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL 模板',
                hintText: '用 {q} 表示关键词，如 https://x.com/search?q={q}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加')),
        ],
      ),
    );

    if (ok == true) {
      final name = nameCtrl.text.trim();
      final url = urlCtrl.text.trim();
      if (name.isEmpty || url.isEmpty || !url.contains('{q}')) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('名称与 URL（含 {q}）均必填')),
          );
        }
        return;
      }
      await service.add(name: name, urlTemplate: url);
    }
  }
}
