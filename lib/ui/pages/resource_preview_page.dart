import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../services/share_helper.dart';

/// 全屏资源预览：图片可捏合/双击缩放，支持下载与分享。
class ResourcePreviewPage extends StatelessWidget {
  final String url;
  const ResourcePreviewPage({super.key, required this.url});

  String get _name {
    final seg = url.split('?').first.split('#').last.split('/').last;
    return seg.isEmpty ? url : seg;
  }

  @override
  Widget build(BuildContext context) {
    final tm = context.read<TabManager>();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '下载',
            onPressed: () {
              tm.downloadRunner.start(url);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('开始下载')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享',
            onPressed: () => ShareHelper.share(url),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.6,
            maxScale: 5,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 44),
                  SizedBox(height: 10),
                  Text('无法加载该资源',
                      style: TextStyle(color: Colors.white60)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
