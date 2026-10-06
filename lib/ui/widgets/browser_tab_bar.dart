import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';

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

/// 标签栏（桌面：顶部通栏；窄屏：紧凑模式）。
///
/// 增强能力：
///   * 拖拽排序（长按标签拖动）
///   * 标签组（彩色标识 / 归组 / 重命名 / 解散）
///   * 标签搜索（含标签组管理）
///   * 隐私标签标识
///   * 单标签操作菜单（关闭其他 / 关闭右侧 / 复制链接）
class BrowserTabBar extends StatelessWidget {
  final bool compact;
  const BrowserTabBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tabs = tm.tabs;
    final active = tm.active;

    return Container(
      height: compact ? 36 : 40,
      color: const Color(0xFFE7EDF2),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: tabs.length,
              // 保留 onReorder 以兼容 Flutter < 3.41（onReorderItem 为 3.41 新增）
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                tm.moveTab(oldIndex, newIndex);
              },
              itemBuilder: (_, i) {
                final tab = tabs[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(tab.id),
                  index: i,
                  child: _TabChip(
                    tab: tab,
                    compact: compact,
                    selected: tab == active,
                    group: tm.groupById(tab.groupId.value),
                    onTap: () => tm.activate(tab.id),
                    onClose: () => tm.closeTab(tab.id),
                    onMenu: () => _showTabMenu(context, tm, tab),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, size: 18),
            tooltip: '搜索标签页',
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _showTabSearch(context, tm),
          ),
          GestureDetector(
            onLongPress: () => _newPrivateTab(context, tm),
            child: IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: '新建标签（长按新建隐私标签）',
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => tm.createTab(),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// 新建隐私标签（不记入历史，关闭即清除 Cookie / 缓存）
  Future<void> _newPrivateTab(BuildContext context, TabManager tm) async {
    final messenger = ScaffoldMessenger.of(context);
    await tm.createTab(private: true);
    messenger.showSnackBar(const SnackBar(
      content: Text('已新建隐私标签：不记录历史，关闭时清除 Cookie 与缓存'),
      duration: Duration(seconds: 3),
    ));
  }

  // —— 单标签菜单 ——

  Future<void> _showTabMenu(
    BuildContext context,
    TabManager tm,
    TabModel tab,
  ) async {
    final idx = tm.tabs.indexOf(tab);
    final group = tm.groupById(tab.groupId.value);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: Icon(
                  tab.isPrivate ? Icons.visibility_off : Icons.public,
                  size: 20,
                ),
                title: Text(
                  tab.title.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
                subtitle: Text(
                  tab.url.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined, size: 20),
                title: const Text('移入新标签组'),
                onTap: () {
                  Navigator.pop(ctx);
                  final g = tm.createGroup();
                  tm.assignGroup(tab.id, g.id);
                },
              ),
              if (tm.groups.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.folder_outlined, size: 20),
                  title: const Text('移入已有标签组'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickGroup(context, tm, tab);
                  },
                ),
              if (group != null)
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined, size: 20),
                  title: const Text('移出标签组'),
                  onTap: () {
                    Navigator.pop(ctx);
                    tm.assignGroup(tab.id, null);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.copy_outlined, size: 20),
                title: const Text('复制链接'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: tab.url.value));
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_fullscreen, size: 20),
                title: const Text('关闭其他标签'),
                onTap: () {
                  Navigator.pop(ctx);
                  for (final t in tm.tabs.where((t) => t.id != tab.id).toList()) {
                    tm.closeTab(t.id);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.close, size: 20),
                title: const Text('关闭右侧标签'),
                enabled: idx >= 0 && idx < tm.tabs.length - 1,
                onTap: () {
                  Navigator.pop(ctx);
                  for (final t in tm.tabs.skip(idx + 1).toList()) {
                    tm.closeTab(t.id);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    size: 20, color: Colors.red.shade400),
                title: Text('关闭标签',
                    style: TextStyle(color: Colors.red.shade400)),
                onTap: () {
                  Navigator.pop(ctx);
                  tm.closeTab(tab.id);
                },
              ),
            ],
          ),
        );
      },
    );
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
                  const SizedBox(width: 10),
                  Text(g.name),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) tm.assignGroup(tab.id, selected);
  }

  // —— 标签搜索 ——

  Future<void> _showTabSearch(BuildContext context, TabManager tm) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TabSearchSheet(tm: tm),
    );
  }
}

/// 单个标签
class _TabChip extends StatelessWidget {
  final TabModel tab;
  final bool compact;
  final bool selected;
  final TabGroup? group;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onMenu;

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
  Widget build(BuildContext context) {
    final groupColor =
        group == null ? null : kTabGroupColors[group!.colorIndex % kTabGroupColors.length];
    final bg = tab.isPrivate
        ? const Color(0xFF3A3A4A)
        : (selected ? Colors.white : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: (_) => onMenu(),
        child: Container(
          width: compact ? 134 : 202,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(
              color: selected
                  ? const Color(0xFFCCD8E0)
                  : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // 标签组色条
              Container(
                width: 3,
                height: double.infinity,
                color: groupColor ?? Colors.transparent,
              ),
              const SizedBox(width: 5),
              Icon(
                tab.isPrivate ? Icons.visibility_off : Icons.public,
                size: 14,
                color: tab.isPrivate
                    ? Colors.white70
                    : (selected ? Colors.black54 : Colors.black38),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: tab.title,
                  builder: (_, t, __) => Text(
                    t,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: tab.isPrivate
                          ? Colors.white
                          : (selected ? Colors.black87 : Colors.black54),
                    ),
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onMenu,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.more_vert,
                      size: 14,
                      color: tab.isPrivate ? Colors.white60 : Colors.black45),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Icon(Icons.close,
                      size: 13,
                      color: tab.isPrivate ? Colors.white60 : Colors.black45),
                ),
              ),
              const SizedBox(width: 4),
            ],
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

/// 标签搜索面板：搜索标签 + 管理标签组
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
    final tm = widget.tm;
    final q = _query.trim().toLowerCase();
    final tabs = tm.tabs.where((t) {
      if (q.isEmpty) return true;
      return t.title.value.toLowerCase().contains(q) ||
          t.url.value.toLowerCase().contains(q);
    }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '按标题或网址搜索标签页',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (tabs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('没有匹配的标签页',
                          style: TextStyle(color: Colors.black45)),
                    ),
                  ),
                for (final t in tabs)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      t.isPrivate ? Icons.visibility_off : Icons.tab,
                      size: 20,
                      color: t == tm.active
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(t.title.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(t.url.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                    trailing: t.groupId.value == null
                        ? null
                        : _GroupDot(
                            colorIndex: tm
                                    .groupById(t.groupId.value)
                                    ?.colorIndex ??
                                0,
                          ),
                    onTap: () {
                      tm.activate(t.id);
                      Navigator.pop(context);
                    },
                  ),
                if (tm.groups.isNotEmpty) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('标签组',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                  for (final g in tm.groups)
                    _GroupTile(tm: tm, group: g),
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
    final count = tm.tabs.where((t) => t.groupId.value == group.id).length;
    return ListTile(
      dense: true,
      leading: _GroupDot(colorIndex: group.colorIndex),
      title: Text(group.name, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text('$count 个标签',
          style: const TextStyle(fontSize: 11)),
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
            tooltip: '重命名',
            onPressed: () => _rename(context),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: Colors.red.shade400),
            tooltip: '解散标签组',
            onPressed: () => tm.removeGroup(group.id),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null) tm.renameGroup(group.id, name);
  }
}
