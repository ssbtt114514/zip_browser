import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../services/downloads_service.dart';

enum _Filter { all, running, completed, failed }

/// 下载管理页
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  _Filter _filter = _Filter.all;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _bytes(int n) {
    if (n <= 0) return '';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  IconData _iconFor(DownloadRecord r) {
    final name = r.filename.toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(name)) return Icons.folder_zip;
    if (RegExp(r'\.(mp3|flac|wav)$').hasMatch(name)) return Icons.audio_file;
    if (RegExp(r'\.(mp4|avi|mkv|mov|webm)$').hasMatch(name)) return Icons.video_file;
    if (RegExp(r'\.(apk|exe|msi)$').hasMatch(name)) return Icons.apps;
    if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$').hasMatch(name)) return Icons.image;
    return Icons.insert_drive_file;
  }

  bool _matches(DownloadRecord r) {
    if (_filter == _Filter.running && r.status != DownloadStatus.running) {
      return false;
    }
    if (_filter == _Filter.completed && r.status != DownloadStatus.completed) {
      return false;
    }
    if (_filter == _Filter.failed && r.status != DownloadStatus.failed) {
      return false;
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty && !r.filename.toLowerCase().contains(q)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DownloadsService>();
    final all = svc.items;
    final filtered = all.where(_matches).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载内容'),
        actions: [
          if (all.any((r) => r.status == DownloadStatus.completed))
            IconButton(
              tooltip: '清除已完成',
              icon: const Icon(Icons.cleaning_services_outlined, size: 20),
              onPressed: () => svc.clearCompleted(),
            ),
        ],
      ),
      body: Column(
        children: [
          // 搜索 + 筛选
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索下载项…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip(_Filter.all, '全部 ${all.length}'),
                const SizedBox(width: 6),
                _chip(
                    _Filter.running,
                    '进行中 ${all.where((r) => r.status == DownloadStatus.running).length}'),
                const SizedBox(width: 6),
                _chip(
                    _Filter.completed,
                    '已完成 ${all.where((r) => r.status == DownloadStatus.completed).length}'),
                const SizedBox(width: 6),
                _chip(
                    _Filter.failed,
                    '失败 ${all.where((r) => r.status == DownloadStatus.failed).length}'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_done, size: 56, color: Colors.black26),
                        SizedBox(height: 12),
                        Text('没有匹配的下载项',
                            style: TextStyle(color: Colors.black45)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 64),
                    itemBuilder: (context, i) {
                      final r = filtered[i];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: Icon(_iconFor(r),
                                color: r.status == DownloadStatus.failed
                                    ? Colors.red
                                    : Theme.of(context).colorScheme.primary),
                            title: Text(r.filename,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: _subtitle(context, r),
                            onTap: r.status == DownloadStatus.completed &&
                                    r.filePath != null
                                ? () async {
                                    final result = await OpenFilex.open(r.filePath!);
                                    if (result.type != ResultType.done &&
                                        context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '无法打开：${result.message}')),
                                      );
                                    }
                                  }
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  context.read<DownloadsService>().remove(r),
                            ),
                          ),
                          if (r.status == DownloadStatus.running)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                              child: LinearProgressIndicator(
                                value: r.progress,
                                minHeight: 3,
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

  Widget _chip(_Filter f, String label) {
    final selected = _filter == f;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = f),
    );
  }

  Widget _subtitle(BuildContext context, DownloadRecord r) {
    switch (r.status) {
      case DownloadStatus.running:
        final pct = r.progress == null
            ? _bytes(r.receivedBytes)
            : '${(r.progress! * 100).toStringAsFixed(0)}%  ${_bytes(r.receivedBytes)}/${_bytes(r.totalBytes)}';
        return Text(pct, style: const TextStyle(fontSize: 11.5));
      case DownloadStatus.completed:
        return Text(r.filePath ?? '已完成',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5));
      case DownloadStatus.failed:
        return Text('下载失败：${r.error ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Colors.red));
      default:
        return Text(r.status.name, style: const TextStyle(fontSize: 11.5));
    }
  }
}
