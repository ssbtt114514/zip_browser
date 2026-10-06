import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../services/bookmarks_service.dart';
import '../design/zb_design.dart';

/// 书签栏：地址栏下方的一条快捷入口。
///
/// 由「菜单 → 显示书签栏」或 Ctrl+Shift+B 控制显隐（持久化在 ConfigService）。
class BookmarksBar extends StatelessWidget {
  const BookmarksBar({super.key});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final bm = context.watch<BookmarksService>();
    final tm = context.watch<TabManager>();
    final items = bm.items;

    return Container(
      height: ZbTokens.bookmarksBarHeight,
      decoration: BoxDecoration(
        color: zb.chromeElevated,
        border: Border(bottom: BorderSide(color: zb.hairline, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: ZbTokens.s4),
      child: Row(
        children: [
          // 加入当前页
          ZbIconAction(
            icon: Icons.star_border,
            tooltip: '将当前页面加入书签（Ctrl+D）',
            size: 16,
            extent: 26,
            onTap: () => _bookmarkCurrent(context, tm, bm),
          ),
          const SizedBox(width: ZbTokens.s3),
          Container(width: 1, height: 16, color: zb.hairline),
          const SizedBox(width: ZbTokens.s3),
          Expanded(
            child: items.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '书签栏为空：打开任意网页后点击左侧 ★ 即可添加',
                      style: TextStyle(fontSize: 11.5, color: zb.textFaint),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    itemBuilder: (_, i) => _BookmarkChip(
                      bookmark: items[i],
                      onOpen: (newTab) {
                        if (newTab) {
                          tm.createTab(url: items[i].url);
                        } else {
                          tm.navigateActive(items[i].url);
                        }
                      },
                      onRemove: () => bm.remove(items[i].id),
                    ),
                  ),
          ),
          if (items.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: '全部书签',
              splashRadius: 15,
              icon: Icon(Icons.more_horiz, size: 18, color: zb.textMuted),
              onSelected: (value) {
                if (value.startsWith('open:')) {
                  final url = value.substring(5);
                  tm.navigateActive(url);
                }
              },
              itemBuilder: (ctx) => [
                for (final b in items)
                  PopupMenuItem<String>(
                    value: 'open:${b.url}',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.public, size: 16, color: zb.textMuted),
                        const SizedBox(width: ZbTokens.s4),
                        Expanded(
                          child: Text(
                            b.title.isEmpty ? b.url : b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, color: zb.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _bookmarkCurrent(
    BuildContext context,
    TabManager tm,
    BookmarksService bm,
  ) async {
    final tab = tm.active;
    final messenger = ScaffoldMessenger.of(context);
    if (tab == null) return;
    final url = tab.url.value;
    if (url.startsWith('data:') || url == 'about:home') {
      messenger.showSnackBar(const SnackBar(
        content: Text('内置页面无法加入书签'),
        duration: Duration(milliseconds: 1400),
      ));
      return;
    }
    if (bm.isBookmarked(url)) {
      bm.removeByUrl(url);
      messenger.showSnackBar(const SnackBar(
        content: Text('已移除书签'),
        duration: Duration(milliseconds: 1200),
      ));
    } else {
      bm.add(title: tab.title.value, url: url);
      messenger.showSnackBar(const SnackBar(
        content: Text('已加入书签'),
        duration: Duration(milliseconds: 1200),
      ));
    }
  }
}

class _BookmarkChip extends StatefulWidget {
  final Bookmark bookmark;
  final void Function(bool newTab) onOpen;
  final VoidCallback onRemove;

  const _BookmarkChip({
    required this.bookmark,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  State<_BookmarkChip> createState() => _BookmarkChipState();
}

class _BookmarkChipState extends State<_BookmarkChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    return Padding(
      padding: const EdgeInsets.only(right: ZbTokens.s2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => widget.onOpen(false),
          onSecondaryTapUp: (details) =>
              _showMenu(context, details.globalPosition),
          child: AnimatedContainer(
            duration: ZbTokens.fast,
            padding: const EdgeInsets.symmetric(
                horizontal: ZbTokens.s4, vertical: ZbTokens.s2),
            margin: const EdgeInsets.symmetric(vertical: ZbTokens.s3),
            constraints: const BoxConstraints(maxWidth: 168),
            decoration: BoxDecoration(
              color: _hovered ? zb.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.public, size: 13, color: zb.textMuted),
                const SizedBox(width: ZbTokens.s3),
                Flexible(
                  child: Text(
                    widget.bookmark.title.isEmpty
                        ? widget.bookmark.url
                        : widget.bookmark.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: zb.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem<String>(
            value: 'open', height: 36, child: Text('在当前标签打开')),
        const PopupMenuItem<String>(
            value: 'new_tab', height: 36, child: Text('在新标签打开')),
        const PopupMenuItem<String>(
            value: 'copy', height: 36, child: Text('复制链接')),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'remove',
          height: 36,
          child: Text('删除书签',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    );
    switch (action) {
      case 'open':
        widget.onOpen(false);
      case 'new_tab':
        widget.onOpen(true);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: widget.bookmark.url));
      case 'remove':
        widget.onRemove();
    }
  }
}
