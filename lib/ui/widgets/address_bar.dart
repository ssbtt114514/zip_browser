import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
import '../../services/bookmarks_service.dart';
import '../../services/zoom_service.dart';
import '../design/zb_design.dart';
import '../omnibox_controller.dart';
import '../shortcuts/browser_focus.dart';

/// 地址栏（Omnibox）。
///
/// 重新设计要点：
/// * 全部颜色取自 [ZbColors]，暗色主题下不再出现"白底黑字"的割裂感；
/// * 左侧安全状态胶囊可点击，弹出站点信息与站点级操作（缩放 / 复制链接）；
/// * 聚焦时展开联想下拉（由 [OmniboxController] 驱动，面板渲染在内容区顶部）；
/// * 支持 ↑/↓ 选择、Enter 打开、Esc 收起、Tab 补全；
/// * 右侧展示缩放倍率胶囊、停止/刷新、加书签。
class AddressBar extends StatelessWidget {
  const AddressBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final controller = context.watch<OmniboxController>();
    // 书签与缩放变化时刷新星标 / 倍率胶囊
    context.watch<BookmarksService>();
    context.watch<ZoomService>();

    final tab = tm.active;
    if (tab == null) {
      return const Expanded(child: SizedBox.shrink());
    }

    // 绑定活动标签：只重挂监听，不在 build 阶段改写文本
    controller.bindTab(tab);

    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          controller.setWidth(constraints.maxWidth);
          return CompositedTransformTarget(
            link: controller.layerLink,
            child: _OmniboxPill(tab: tab, controller: controller),
          );
        },
      ),
    );
  }
}

class _OmniboxPill extends StatelessWidget {
  final TabModel tab;
  final OmniboxController controller;

  const _OmniboxPill({
    required this.tab,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final scheme = Theme.of(context).colorScheme;
    final focused = controller.isFocused;

    return AnimatedContainer(
      duration: ZbTokens.fast,
      curve: ZbTokens.easeOut,
      height: ZbTokens.omniboxHeight,
      decoration: BoxDecoration(
        color: focused ? zb.omniboxFillFocused : zb.omniboxFill,
        borderRadius: BorderRadius.circular(ZbTokens.omniboxHeight / 2),
        border: Border.all(
          color: focused ? scheme.primary : zb.hairline,
          width: focused ? 1.6 : 1,
        ),
        boxShadow: zb.softShadow(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: ZbTokens.s2),
      child: Row(
        children: [
          _SecurityButton(tab: tab),
          Expanded(child: _OmniboxField(tab: tab, controller: controller)),
          _ZoomChip(tab: tab),
          _ReloadButton(tab: tab),
          _BookmarkButton(tab: tab),
          const SizedBox(width: ZbTokens.s2),
        ],
      ),
    );
  }
}

/// 左侧安全状态按钮：点击弹出站点信息
class _SecurityButton extends StatelessWidget {
  final TabModel tab;
  const _SecurityButton({required this.tab});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    return ValueListenableBuilder<String>(
      valueListenable: tab.url,
      builder: (context, url, __) {
        final state = _SiteSecurity.of(url);
        return Tooltip(
          message: state.tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showSiteInfo(context, tab, url, state),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: ZbTokens.s3, vertical: ZbTokens.s2),
              child: Icon(state.icon, size: 15, color: state.color(zb)),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSiteInfo(
    BuildContext context,
    TabModel tab,
    String url,
    _SiteSecurity state,
  ) async {
    final tm = context.read<TabManager>();
    final zoom = context.read<ZoomService>();
    final origin = ZoomService.originOf(url);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final zb2 = ctx.zb;
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(
              ZbTokens.s6, ZbTokens.s6, ZbTokens.s6, ZbTokens.s2),
          contentPadding: const EdgeInsets.fromLTRB(
              ZbTokens.s6, 0, ZbTokens.s6, ZbTokens.s4),
          title: Row(
            children: [
              Icon(state.icon, size: 18, color: state.color(zb2)),
              const SizedBox(width: ZbTokens.s4),
              Expanded(
                child: Text(
                  state.title,
                  style: const TextStyle(fontSize: 15.5),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  origin ?? (url.isEmpty ? '内置页面' : url),
                  style: TextStyle(fontSize: 12.5, color: zb2.textMuted),
                ),
                const SizedBox(height: ZbTokens.s5),
                Text(
                  state.detail,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.55, color: zb2.textPrimary),
                ),
                const SizedBox(height: ZbTokens.s5),
                const Divider(height: 1),
                const SizedBox(height: ZbTokens.s4),
                // 站点级缩放
                Row(
                  children: [
                    Icon(Icons.zoom_out_map, size: 17, color: zb2.textMuted),
                    const SizedBox(width: ZbTokens.s4),
                    Expanded(
                      child: Text(
                          '本站缩放：${ZoomService.label(tm.zoomFor(tab))}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 17),
                      tooltip: '缩小（Ctrl+-）',
                      onPressed: () async {
                        await tm.zoomOut();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 17),
                      tooltip: '放大（Ctrl++）',
                      onPressed: () async {
                        await tm.zoomIn();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
                if (origin != null)
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 17),
                    label: const Text('重置本站缩放'),
                    onPressed: () async {
                      await zoom.clearSite(url);
                      await tm.applyZoom(tab);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.link, size: 17),
              label: const Text('复制链接'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }
}

/// 站点安全状态
class _SiteSecurity {
  final IconData icon;
  final String title;
  final String detail;
  final String tooltip;
  final bool secure;
  final bool internal;

  const _SiteSecurity({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tooltip,
    required this.secure,
    required this.internal,
  });

  Color color(ZbColors zb) {
    if (internal) return zb.textMuted;
    return secure ? zb.secure : zb.insecure;
  }

  static _SiteSecurity of(String url) {
    if (url.isEmpty || url.startsWith('data:') || url.startsWith('about:')) {
      return const _SiteSecurity(
        icon: Icons.home_outlined,
        title: 'Zip Browser 内置页面',
        detail: '这是浏览器内置页面，不与网络通信。',
        tooltip: '内置页面',
        secure: true,
        internal: true,
      );
    }
    if (url.startsWith('https://')) {
      return const _SiteSecurity(
        icon: Icons.lock_outline,
        title: '连接是安全的',
        detail: '你与此网站之间的通信已使用 TLS 加密。',
        tooltip: '安全连接（HTTPS）',
        secure: true,
        internal: false,
      );
    }
    if (url.startsWith('http://')) {
      return const _SiteSecurity(
        icon: Icons.lock_open,
        title: '连接不安全',
        detail: '此网站使用未加密的 HTTP，输入的信息可能被第三方读取。',
        tooltip: '不安全连接（HTTP）',
        secure: false,
        internal: false,
      );
    }
    if (url.startsWith('file://')) {
      return const _SiteSecurity(
        icon: Icons.folder_outlined,
        title: '本地文件',
        detail: '正在浏览本机文件。',
        tooltip: '本地文件',
        secure: true,
        internal: false,
      );
    }
    return const _SiteSecurity(
      icon: Icons.public,
      title: '第三方内容',
      detail: '该地址由第三方应用或插件提供。',
      tooltip: '第三方内容',
      secure: false,
      internal: false,
    );
  }
}

/// 地址输入框本体
class _OmniboxField extends StatelessWidget {
  final TabModel tab;
  final OmniboxController controller;

  const _OmniboxField({required this.tab, required this.controller});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;

    // ↑/↓ 选择建议，Esc 收起，Tab 补全
    controller.focusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        controller.moveHighlight(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        controller.moveHighlight(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        controller.close();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.tab) {
        final s = controller.suggestions;
        if (s.isNotEmpty && controller.highlight >= 0) {
          final picked = s[controller.highlight];
          controller.text.value = TextEditingValue(
            text: picked.url,
            selection: TextSelection.collapsed(offset: picked.url.length),
          );
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    return TextField(
      controller: controller.text,
      focusNode: controller.focusNode,
      textInputAction: TextInputAction.go,
      maxLines: 1,
      style: TextStyle(fontSize: 14.5, color: zb.textPrimary),
      cursorColor: Theme.of(context).colorScheme.primary,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: '搜索或输入网址',
        hintStyle: TextStyle(fontSize: 14, color: zb.textFaint),
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
      ),
      onChanged: controller.onQueryChanged,
      onSubmitted: (value) {
        final picked = controller.commitTarget(value);
        controller.close();
        if (picked != null) {
          context.read<TabManager>().navigateActive(picked.url);
        }
        // 收起地址栏后把焦点收回根节点，保证快捷键继续可用
        BrowserFocus.take(context);
      },
    );
  }
}

/// 缩放倍率胶囊（仅非 100% 时显示）
class _ZoomChip extends StatelessWidget {
  final TabModel tab;
  const _ZoomChip({required this.tab});

  @override
  Widget build(BuildContext context) {
    final tm = context.read<TabManager>();
    return ValueListenableBuilder<double>(
      valueListenable: tab.zoom,
      builder: (context, zoom, __) {
        if ((zoom - 1.0).abs() < 0.001) return const SizedBox.shrink();
        return Tooltip(
          message: '页面缩放 ${ZoomService.label(zoom)}（点击重置）',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => tm.resetZoom(),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: ZbTokens.s4, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                ZoomService.label(zoom),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 停止加载 / 刷新
class _ReloadButton extends StatelessWidget {
  final TabModel tab;
  const _ReloadButton({required this.tab});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: tab.isLoading,
      builder: (context, loading, __) => ZbIconAction(
        icon: loading ? Icons.close : Icons.refresh,
        tooltip: loading ? '停止加载' : '刷新（F5 / Ctrl+R）',
        size: 17,
        extent: 30,
        onTap: () => loading ? tab.kernel.stopLoading() : tab.kernel.reload(),
      ),
    );
  }
}

/// 加入 / 取消书签
class _BookmarkButton extends StatelessWidget {
  final TabModel tab;
  const _BookmarkButton({required this.tab});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: tab.url,
      builder: (context, url, __) {
        final internal = url.startsWith('data:') || url == 'about:home';
        final marked =
            !internal && context.read<BookmarksService>().isBookmarked(url);
        final zb = context.zb;
        return ZbIconAction(
          icon: marked ? Icons.star : Icons.star_border,
          tooltip: marked ? '已加入书签（点击移除）' : '加入书签（Ctrl+D）',
          size: 17,
          extent: 30,
          selectedColor: const Color(0xFFF5A623),
          color: marked ? const Color(0xFFF5A623) : zb.textMuted,
          selected: marked,
          onTap: internal
              ? null
              : () {
                  final bm = context.read<BookmarksService>();
                  if (marked) {
                    bm.removeByUrl(url);
                  } else {
                    bm.add(title: tab.title.value, url: url);
                  }
                },
        );
      },
    );
  }
}
