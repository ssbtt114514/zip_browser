import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/sniff/sniff_model.dart';
import '../../core/tab/tab_manager.dart';
import '../../services/ui_state.dart';
import 'resource_preview_page.dart';

/// 资源嗅探面板：展示当前页面嗅探到的媒体/资源，支持下载与复制链接。
class SniffPanel extends StatefulWidget {
  const SniffPanel({super.key});

  @override
  State<SniffPanel> createState() => _SniffPanelState();
}

class _SniffPanelState extends State<SniffPanel> {
  final List<SniffedResource> _resources = [];
  String? _boundTabId;
  StreamSubscription? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tab = tm.active;

    // 切换标签时重新订阅
    if (tab?.id != _boundTabId) {
      _boundTabId = tab?.id;
      _resources.clear();
      _sub?.cancel();
      // 订阅当前标签的嗅探流
      _sub = tab?.kernel.sniffedResources.listen((list) {
        if (mounted) {
          setState(() {
            for (final r in list) {
              if (!_resources.any((e) => e.url == r.url)) {
                _resources.add(r);
              }
            }
          });
        }
      });
    }

    final grouped = _groupByType(_resources);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 拖拽手柄
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.satellite_alt,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('资源嗅探',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (_resources.isNotEmpty)
                      Text('${_resources.length} 项',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    IconButton(
                      icon: Icon(
                        tm.config.autoSniff
                            ? Icons.travel_explore
                            : Icons.travel_explore_outlined,
                        size: 19,
                        color: tm.config.autoSniff
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      tooltip: tm.config.autoSniff
                          ? '自动嗅探：开（点击关闭）'
                          : '自动嗅探：关（点击开启）',
                      onPressed: () =>
                          tm.config.setAutoSniff(!tm.config.autoSniff),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: '重新扫描',
                      onPressed: () {
                        _resources.clear();
                        tab?.kernel.triggerSniff();
                        setState(() {});
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '关闭',
                      onPressed: () =>
                          context.read<BrowserUiState>().closeSniff(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _resources.isEmpty
                    ? const _EmptyState()
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final type in SniffType.values)
                            if (grouped[type]?.isNotEmpty ?? false) ...[
                              _SectionHeader(type.label, grouped[type]!.length),
                              for (final r in grouped[type]!)
                                _ResourceTile(
                                  resource: r,
                                  onPreview: () => _preview(r),
                                  onDownload: () {
                                    tm.downloadRunner.start(
                                      r.url,
                                      headers: {
                                        'Referer': tab?.url.value ?? '',
                                        'User-Agent': 'Mozilla/5.0',
                                      },
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('开始下载：${_nameOf(r)}')),
                                    );
                                  },
                                ),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<SniffType, List<SniffedResource>> _groupByType(
      List<SniffedResource> list) {
    final map = <SniffType, List<SniffedResource>>{};
    for (final r in list) {
      map.putIfAbsent(r.type, () => []).add(r);
    }
    return map;
  }

  String _nameOf(SniffedResource r) {
    final seg = r.url.split('?').first.split('#').last.split('/').last;
    return seg.isEmpty ? r.url : seg;
  }

  /// 预览资源：图片进入全屏预览页；视频/音频在新标签用系统内核播放
  void _preview(SniffedResource r) {
    if (r.type == SniffType.image) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResourcePreviewPage(url: r.url)),
      );
    } else {
      context.read<TabManager>().createTab(url: r.url);
      context.read<BrowserUiState>().closeSniff();
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader(this.label, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 6),
          Text('$count', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ResourceTile extends StatelessWidget {
  final SniffedResource resource;
  final VoidCallback onPreview;
  final VoidCallback onDownload;

  const _ResourceTile({
    required this.resource,
    required this.onPreview,
    required this.onDownload,
  });

  Widget _leading(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (resource.type == SniffType.image) {
      // 图片直接显示缩略图
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          resource.url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(_iconFor(resource.type), size: 22, color: primary),
          loadingBuilder: (_, child, p) =>
              p == null ? child : SizedBox(width: 44, height: 44, child: Icon(Icons.image_outlined, size: 22, color: primary)),
        ),
      );
    }
    return Icon(_iconFor(resource.type), size: 22, color: primary);
  }

  @override
  Widget build(BuildContext context) {
    final name = _filename(resource.url);
    final isMedia = resource.type == SniffType.video ||
        resource.type == SniffType.audio;
    return ListTile(
      dense: true,
      onTap: onPreview,
      leading: _leading(context),
      title: Text(name,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(resource.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isMedia ? Icons.play_circle_outline : Icons.visibility_outlined,
              size: 19,
              color: Theme.of(context).colorScheme.primary,
            ),
            tooltip: isMedia ? '播放预览' : '预览',
            onPressed: onPreview,
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 17),
            tooltip: '复制链接',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: resource.url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('链接已复制'), duration: Duration(seconds: 1)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 17),
            tooltip: '下载',
            onPressed: onDownload,
          ),
        ],
      ),
    );
  }

  String _filename(String url) {
    final seg = url.split('?').first.split('#').last.split('/').last;
    return seg.isEmpty ? url : seg;
  }

  IconData _iconFor(SniffType type) {
    switch (type) {
      case SniffType.video:
        return Icons.videocam_outlined;
      case SniffType.audio:
        return Icons.audiotrack_outlined;
      case SniffType.image:
        return Icons.image_outlined;
      case SniffType.css:
        return Icons.style_outlined;
      case SniffType.js:
        return Icons.javascript_outlined;
      case SniffType.font:
        return Icons.font_download_outlined;
      case SniffType.other:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.satellite_alt_outlined, size: 44, color: Colors.black26),
          SizedBox(height: 10),
          Text('未发现可嗅探的资源', style: TextStyle(color: Colors.black45)),
          SizedBox(height: 4),
          Text('点击右上角刷新按钮重新扫描',
              style: TextStyle(fontSize: 11.5, color: Colors.black38)),
        ],
      ),
    );
  }
}
