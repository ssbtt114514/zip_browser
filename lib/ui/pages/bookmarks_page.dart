import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/bookmarks_service.dart';

/// 书签管理页
class BookmarksPage extends StatelessWidget {
  final void Function(String url) onOpen;
  const BookmarksPage({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final bookmarks = context.watch<BookmarksService>().items;

    return Scaffold(
      appBar: AppBar(title: const Text('书签')),
      body: bookmarks.isEmpty
          ? const _EmptyHint()
          : ListView.separated(
              itemCount: bookmarks.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 64),
              itemBuilder: (context, i) {
                final b = bookmarks[i];
                final host = Uri.tryParse(b.url)?.host ?? '';
                return ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      (b.title.isNotEmpty ? b.title[0] : '?').toUpperCase(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  title: Text(b.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(host.isNotEmpty ? host : b.url,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    onOpen(b.url);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除书签',
                    onPressed: () =>
                        context.read<BookmarksService>().remove(b.id),
                  ),
                );
              },
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
          Icon(Icons.bookmark_border, size: 56, color: Colors.black26),
          SizedBox(height: 12),
          Text('还没有书签', style: TextStyle(color: Colors.black45)),
          SizedBox(height: 4),
          Text('浏览网页时点地址栏右侧的星标添加',
              style: TextStyle(color: Colors.black38, fontSize: 12.5)),
        ],
      ),
    );
  }
}
