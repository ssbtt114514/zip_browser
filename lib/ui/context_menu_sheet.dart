import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_keys.dart';
import '../core/kernel/browser_kernel.dart';
import '../services/share_helper.dart';

/// 长按 / 右键菜单（使用全局 navigatorKey，无需持有 widget context）
class ContextMenuSheet {
  static Future<void> show(
    ContextMenuInfo info, {
    required void Function(String url) onOpenNewTab,
    required void Function(String url) onDownload,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final items = <Widget>[];

    void item(IconData icon, String label, VoidCallback onTap) {
      items.add(ListTile(
        leading: Icon(icon, size: 22),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      ));
    }

    void copied(String value) {
      Clipboard.setData(ClipboardData(text: value));
      messengerKey.currentState?.showSnackBar(
        const SnackBar(
            content: Text('已复制'), duration: Duration(seconds: 1)),
      );
    }

    if (info.hasLink) {
      item(Icons.open_in_new, '在新标签页打开链接',
          () => onOpenNewTab(info.linkUrl!));
      item(Icons.link, '复制链接地址', () => copied(info.linkUrl!));
      item(Icons.share, '分享链接',
          () => ShareHelper.share(info.linkUrl!));
    }

    if (info.hasImage) {
      if (items.isNotEmpty) items.add(const Divider(height: 1));
      item(Icons.save_alt, '保存图片', () => onDownload(info.imageUrl!));
      item(Icons.image_outlined, '在新标签页打开图片',
          () => onOpenNewTab(info.imageUrl!));
      item(Icons.content_copy, '复制图片地址', () => copied(info.imageUrl!));
    }

    if ((info.selectedText ?? '').trim().isNotEmpty) {
      if (items.isNotEmpty) items.add(const Divider(height: 1));
      item(Icons.content_copy, '复制所选文本',
          () => copied(info.selectedText!.trim()));
    }

    if (items.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }
}
