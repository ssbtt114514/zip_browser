import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/history_service.dart';

/// 历史记录页（搜索 / 按天分组 / 清空）
class HistoryPage extends StatefulWidget {
  final void Function(String url) onOpen;
  const HistoryPage({super.key, required this.onOpen});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _query = '';

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff 天前';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<HistoryService>();
    final source = _query.isEmpty ? null : service.search(_query);
    final groups = service.grouped(source: source);

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        actions: [
          if (service.entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空历史',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('清空全部历史记录？'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('清空')),
                    ],
                  ),
                );
                if (ok == true) service.clear();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索历史记录',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Text('暂无历史记录',
                        style: TextStyle(color: Colors.black45)))
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, gi) {
                      final g = groups[gi];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: Text(_dayLabel(g.day),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5)),
                          ),
                          for (final e in g.entries)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.history,
                                  size: 20, color: Colors.black38),
                              title: Text(
                                  e.title.isEmpty ? e.url : e.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(e.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5)),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onOpen(e.url);
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => service.remove(e),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
