import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
import '../design/zb_design.dart';

/// 标签组配色板（与 [TabGroup.colorIndex] 对应）
const List<Color> kTabGroupColors = [
  Color(0xFF5B8DEF),
  Color(0xFF34A853),
  Color(0xFFF2994A),
  Color(0xFFEB5757),
  Color(0xFF9B51E0),
  Color(0xFF00A3A3),
  Color(0xFFE45FA6),
  Color(0xFF7A7A7A),
];

/// 标签栏。
///
/// 视觉：跟随主题的外壳底色 + 活动标签"浮起"卡片 + 悬停反馈；
/// 交互：拖拽排序（跨固定区自动固定/取消固定）、固定标签、标签组、
/// 标签搜索、右键/长按菜单（复制、关闭其他、关闭右侧等）。
class BrowserTabBar extends StatelessWidget {
  final bool compact;
  const BrowserTabBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final tm = context.watch<TabManager>();
    final tabs = tm.tabs;
    final active = tm.active;

    return Container(
      height: compact ? ZbTokens.compactTabStripHeight : ZbTokens.tabStripHeight,
      decoration: BoxDecoration(
        color: zb.chrome,
        border: Border(bottom: BorderSide(color: zb.hairline, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: tabs.isEmpty
                ? const SizedBox.expand()
                : ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? ZbTokens.s2 : ZbTokens.s3,
                      vertical: ZbTokens.s1,
                    ),
                    itemCount: tabs.length,
                    // 保留 onReorder 以兼容 Flutter < 3.41（onReorderItem 为 3.41 新增）
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      tm.moveTab(oldIndex, newIndex);
                    },
                    itemBuilder: (_, i) {
                      final tab = tabs[i];
                      final selected = tab == active;
                      final group = tm.groupById(tab.groupId.value);
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(tab.id),
                        index: i,
                        child: _TabChip(
                          tab: tab,
                          compact: compact,
                          selected: selected,
                          group: group,
                          onTap: () => tm.activate(tab.id),
                          onClose: () => tm.closeTab(tab.id),
                          onMenu: (position) =>
                              _showTabMenu(context, tm, tab, position),
                        ),
                      );
                    },
                  ),
          ),
          _StripActions(compact: compact),
        ],
      ),
    );
  }

  // —— 标签菜单 ——

  /// 弹出单标签操作菜单。
  ///
  /// 桌面端在鼠标位置弹出（右键），移动端从底部弹出（长按 ⋮）。
  Future<void> _showTabMenu(
    BuildContext context,
    TabManager tm,
    TabModel tab,
    Offset? position,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: position == null
          ? null
          : RelativeRect.fromLTRB(
              position.dx,
              position.dy,
              position.dx,
              position.dy,
            ),
      items: _menuItems(context, tm, tab),
    );
    if (action == null || !context.mounted) return;
    await _handleMenuAction(context, tm, tab, action);
  }

  List<PopupMenuEntry<String>> _menuItems(
    BuildContext context,
    TabManager tm,
    TabModel tab,
  ) {
    final idx = tm.tabs.indexOf(tab);
    final group = tm.groupById(tab.groupId.value);
    final canCloseRight = idx >= 0 && idx < tm.tabs.length - 1;
    return [
      PopupMenuItem<String>(
        enabled: false,
        height: 44,
        child: SizedBox(
          width: 226,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.title.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.zb.textPrimary,
                ),
              ),
              Text(
                tab.url.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.zb.textMuted),
              ),
            ],
          ),
        ),
      ),
      const PopupMenuDivider(height: 1),
      _menuRow('pin', tab.isPinned.value ? '取消固定' : '固定标签',
          tab.isPinned.value ? Icons.push_pin : Icons.push_pin_outlined, context),
      _menuRow('duplicate', '复制标签', Icons.content_copy_outlined, context),
      _menuRow('new_right', '在右侧新建标签', Icons.add, context),
      _menuRow('reload', '重新加载', Icons.refresh, context),
      _menuRow('copy_url', '复制链接', Icons.link, context),
      const PopupMenuDivider(height: 1),
      _menuRow('group_new', '移入新标签组', Icons.create_new_folder_outlined,
          context),
      if (tm.groups.isNotEmpty)
        _menuRow('group_pick', '移入已有标签组', Icons.folder_outlined, context),
      if (group != null)
        _menuRow('group_out', '移出标签组', Icons.folder_off_outlined, context),
      const PopupMenuDivider(height: 1),
      _menuRow('close_others', '关闭其他标签', Icons.close_fullscreen, context),
      _menuRow(
        'close_right',
        '关闭右侧标签',
        Icons.keyboard_tab_outlined,
        context,
        enabled: canCloseRight,
      ),
      _menuRow('close', '关闭标签', Icons.close, context, danger: true),
    ];
  }

  PopupMenuItem<String> _menuRow(
    String value,
    String label,
    IconData icon,
    BuildContext context, {
    bool enabled = true,
    bool danger = false,
  }) {
    final zb = context.zb;
    final color = danger
        ? Theme.of(context).colorScheme.error
        : (enabled ? zb.textPrimary : zb.textFaint);
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 17, color: color.withValues(alpha: 0.85)),
          const SizedBox(width: ZbTokens.s5),
          Text(label, style: TextStyle(fontSize: 13.5, color: color)),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    TabManager tm,
    TabModel tab,
    String action,
  ) async {
    switch (action) {
      case 'pin':
        tm.togglePin(tab.id);
      case 'duplicate':
        await tm.duplicateTab(tab.id);
      case 'new_right':
        await tm.newTabToRight(tab.id);
      case 'reload':
        await tab.kernel.reload();
      case 'copy_url':
        await Clipboard.setData(ClipboardData(text: tab.url.value));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('链接已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      case 'group_new':
        final g = tm.createGroup();
        tm.assignGroup(tab.id, g.id);
      case 'group_pick':
        await _pickGroup(context, tm, tab);
      case 'group_out':
        tm.assignGroup(tab.id, null);
      case 'close_others':
        await tm.closeOtherTabs(tab.id);
      case 'close_right':
        await tm.closeTabsToRight(tab.id);
      case 'close':
        await tm.closeTab(tab.id);
    }
  }

  Future<void> _pickGroup(
    BuildContext context,
    TabManager tm,
    TabModel tab,
  ) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移入标签组'),
        children: [
          for (final g in tm.groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.id),
              child: Row(
                children: [
                  _GroupDot(colorIndex: g.colorIndex),
                  const SizedBox(width: ZbTokens.s5),
                  Text(g.name),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) tm.assignGroup(tab.id, selected);
  }
}

/// 标签栏右侧的固定操作：标签搜索、新建标签
class _StripActions extends StatelessWidget {
  final bool compact;
  const _StripActions({required this.compact});

  @override
  Widget build(BuildContext context) {
    final tm = context.read<TabManager>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZbIconAction(
          icon: Icons.search,
          tooltip: '搜索标签页（Ctrl+Shift+A）',
          size: 17,
          extent: compact ? 34 : 30,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _TabSearchSheet(tm: tm),
          ),
        ),
        GestureDetector(
          onLongPress: () => _newPrivateTab(context, tm),
          child: ZbIconAction(
            icon: Icons.add,
            tooltip: '新建标签（Ctrl+T）· 长按新建隐私标签',
            size: 18,
            extent: compact ? 34 : 30,
            onTap: () => tm.createTab(),
          ),
        ),
        const SizedBox(width: ZbTokens.s3),
      ],
    );
  }

  /// 新建隐私标签（不记入历史，关闭即清除 Cookie / 缓存）
  void _newPrivateTab(BuildContext context, TabManager tm) {
    final messenger = ScaffoldMessenger.of(context);
    tm.createTab(private: true);
    messenger.showSnackBar(const SnackBar(
      content: Text('已新建隐私标签：不记录历史，关闭时清除 Cookie 与缓存'),
      duration: Duration(seconds: 3),
    ));
  }
}

/// 单个标签（卡片式）
class _TabChip extends StatefulWidget {
  final TabModel tab;
  final bool compact;
  final bool selected;
  final TabGroup? group;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final void Function(Offset? position) onMenu;

  const _TabChip({
    required this.tab,
    required this.compact,
    required this.selected,
    required this.group,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
  });

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final scheme = Theme.of(context).colorScheme;
    final tab = widget.tab;
    final pinned = tab.isPinned.value;

    final groupColor = widget.group == null
        ? null
        : kTabGroupColors[
            widget.group!.colorIndex % kTabGroupColors.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: () => widget.onMenu(null),
          onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
          child: AnimatedContainer(
            duration: ZbTokens.fast,
            curve: ZbTokens.easeOut,
            width: pinned
                ? ZbTokens.pinnedTabWidth
                : (widget.compact
                    ? ZbTokens.tabWidthCompact
                    : ZbTokens.tabWidth),
            margin: EdgeInsets.only(top: widget.selected ? 3 : 5),
            decoration: BoxDecoration(
              color: _backgroundColor(zb, pinned),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
                bottom: Radius.circular(4),
              ),
              border: Border.all(
                color: widget.selected ? zb.hairline : Colors.transparent,
                width: 1,
              ),
              boxShadow: widget.selected ? zb.softShadow() : const [],
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // 标签组色条
                if (groupColor != null)
                  Container(width: 3, color: groupColor),
                Expanded(
                  child: pinned
                      ? _buildPinnedBody(zb, scheme)
                      : _buildBody(zb, scheme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor(ZbColors zb, bool pinned) {
    final tab = widget.tab;
    if (tab.isPrivate) {
      // 隐私标签：底色固定为紫色系，活动态更亮
      return widget.selected
          ? Color.alphaBlend(
              zb.privateAccent.withValues(alpha: 0.30), zb.privateSurface)
          : zb.privateSurface;
    }
    if (widget.selected) return zb.tabActive;
    if (_hovered) return zb.hover;
    return zb.tabInactive;
  }

  /// 固定标签：仅图标 + 状态点
  Widget _buildPinnedBody(ZbColors zb, ColorScheme scheme) {
    final tab = widget.tab;
    return ValueListenableBuilder<String>(
      valueListenable: tab.url,
      builder: (_, url, __) => Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            _tabIcon(url, tab.isPrivate),
            size: 16,
            color: widget.selected ? scheme.primary : zb.textPrimary.withValues(alpha: 0.72),
          ),
          // 加载中的小圆点
          Positioned(
            right: 6,
            child: ValueListenableBuilder<bool>(
              valueListenable: tab.isLoading,
              builder: (_, loading, __) => loading
                  ? SizedBox(
                      width: 7,
                      height: 7,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.4,
                        color: scheme.primary,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ZbColors zb, ColorScheme scheme) {
    final tab = widget.tab;
    final showClose = widget.selected || _hovered;
    return Row(
      children: [
        const SizedBox(width: ZbTokens.s4),
        ValueListenableBuilder<bool>(
          valueListenable: tab.isLoading,
          builder: (_, loading, __) => loading
              ? SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: scheme.primary,
                  ),
                )
              : ValueListenableBuilder<String>(
                  valueListenable: tab.url,
                  builder: (_, url, __) => Icon(
                    _tabIcon(url, tab.isPrivate),
                    size: 14,
                    color: widget.selected
                        ? scheme.primary.withValues(alpha: 0.9)
                        : zb.textMuted,
                  ),
                ),
        ),
        const SizedBox(width: ZbTokens.s4),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: tab.title,
            builder: (_, title, __) => Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight:
                    widget.selected ? FontWeight.w600 : FontWeight.w400,
                color: widget.selected ? zb.textPrimary : zb.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(width: ZbTokens.s2),
        // 关闭按钮：活动/悬停时出现
        AnimatedOpacity(
          duration: ZbTokens.fast,
          opacity: showClose ? 1 : 0,
          child: IgnorePointer(
            ignoring: !showClose,
            child: _ChipIconButton(
              icon: Icons.close,
              tooltip: '关闭标签（Ctrl+W）',
              size: 13,
              onTap: widget.onClose,
            ),
          ),
        ),
        const SizedBox(width: ZbTokens.s3),
      ],
    );
  }

  /// 依据 URL 与隐私状态挑选标签图标
  static IconData _tabIcon(String url, bool isPrivate) {
    if (isPrivate) return Icons.visibility_off_outlined;
    if (url.startsWith('https://')) return Icons.lock_outline;
    if (url.startsWith('http://')) return Icons.public;
    if (url.startsWith('about:') || url.startsWith('data:')) {
      return Icons.home_outlined;
    }
    if (url.startsWith('file://')) return Icons.folder_outlined;
    return Icons.public;
  }
}

/// 标签内的小图标按钮（关闭按钮）
class _ChipIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback onTap;

  const _ChipIconButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onTap,
  });

  @override
  State<_ChipIconButton> createState() => _ChipIconButtonState();
}

class _ChipIconButtonState extends State<_ChipIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: ZbTokens.fast,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _hovered ? zb.pressed : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.size,
              color: _hovered
                  ? Theme.of(context).colorScheme.error
                  : zb.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupDot extends StatelessWidget {
  final int colorIndex;
  const _GroupDot({required this.colorIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: kTabGroupColors[colorIndex % kTabGroupColors.length],
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 标签搜索 / 切换面板：网格化视觉，支持按标题与网址过滤。
class _TabSearchSheet extends StatefulWidget {
  final TabManager tm;
  const _TabSearchSheet({required this.tm});

  @override
  State<_TabSearchSheet> createState() => _TabSearchSheetState();
}

class _TabSearchSheetState extends State<_TabSearchSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final tm = widget.tm;
    final q = _query.trim().toLowerCase();
    final tabs = tm.tabs.where((t) {
      if (q.isEmpty) return true;
      return t.title.value.toLowerCase().contains(q) ||
          t.url.value.toLowerCase().contains(q);
    }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.74,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZbTokens.s6, 0, ZbTokens.s6, ZbTokens.s4),
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search, size: 19),
                hintText: '按标题或网址搜索标签页',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: ZbTokens.s6),
              children: [
                if (tabs.isEmpty)
                  const ZbEmptyState(
                    icon: Icons.tab_unselected_outlined,
                    title: '没有匹配的标签页',
                    subtitle: '试试其他关键词',
                  ),
                for (final t in tabs)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      t.isPinned.value
                          ? Icons.push_pin
                          : (t.isPrivate
                              ? Icons.visibility_off_outlined
                              : Icons.tab),
                      size: 19,
                      color: t == tm.active
                          ? Theme.of(context).colorScheme.primary
                          : zb.textMuted,
                    ),
                    title: Text(
                      t.title.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: t == tm.active
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: zb.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      t.url.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: zb.textMuted),
                    ),
                    trailing: t.groupId.value == null
                        ? null
                        : _GroupDot(
                            colorIndex:
                                tm.groupById(t.groupId.value)?.colorIndex ?? 0,
                          ),
                    onTap: () {
                      tm.activate(t.id);
                      Navigator.pop(context);
                    },
                  ),
                if (tm.groups.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        ZbTokens.s6, ZbTokens.s5, ZbTokens.s6, ZbTokens.s2),
                    child: Text(
                      '标签组',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  for (final g in tm.groups) _GroupTile(tm: tm, group: g),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final TabManager tm;
  final TabGroup group;
  const _GroupTile({required this.tm, required this.group});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final count = tm.tabs.where((t) => t.groupId.value == group.id).length;
    return ListTile(
      dense: true,
      leading: _GroupDot(colorIndex: group.colorIndex),
      title: Text(group.name,
          style: TextStyle(fontSize: 13.5, color: zb.textPrimary)),
      subtitle: Text('$count 个标签',
          style: TextStyle(fontSize: 11, color: zb.textMuted)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              group.collapsed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
            ),
            tooltip: group.collapsed ? '展开' : '折叠',
            onPressed: () => tm.toggleGroupCollapsed(group.id),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline, size: 18),
            tooltip: '重命名 / 换色',
            onPressed: () => _rename(context),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: Theme.of(context).colorScheme.error),
            tooltip: '解散标签组',
            onPressed: () => tm.removeGroup(group.id),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: group.name);
    var colorIndex = group.colorIndex;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('重命名标签组'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: ZbTokens.s6),
              Text('配色',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(ctx).colorScheme.primary)),
              const SizedBox(height: ZbTokens.s4),
              Wrap(
                spacing: ZbTokens.s4,
                runSpacing: ZbTokens.s4,
                children: [
                  for (var i = 0; i < kTabGroupColors.length; i++)
                    GestureDetector(
                      onTap: () => setLocal(() => colorIndex = i),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: kTabGroupColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorIndex == i
                                ? Theme.of(ctx).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: colorIndex == i
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (name != null) tm.renameGroup(group.id, name);
    tm.setGroupColor(group.id, colorIndex);
  }
}
