import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/sniff/sniff_model.dart';
import '../core/tab/tab_manager.dart';
import '../services/clipboard_link_detector.dart';
import '../services/config_service.dart';
import '../services/ui_state.dart';
import 'context_menu_sheet.dart';
import 'design/zb_design.dart';
import 'find_bar.dart';
import 'pages/sniff_panel.dart';
import 'shortcuts/browser_focus.dart';
import 'shortcuts/browser_shortcuts.dart';
import 'widgets/bookmarks_bar.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/browser_tab_bar.dart';
import 'widgets/main_toolbar.dart';
import 'widgets/omnibox_suggestions.dart';
import 'widgets/secondary_toolbar.dart';

/// 浏览器主外壳。
///
/// 布局（宽屏）：标签栏 → 工具栏 → 书签栏（可选）→ 二级工具栏（可折叠）
/// → 进度条 → 查找栏（可选）→ 内容区；
/// 布局（窄屏）：工具栏 → 二级工具栏 → 进度条 → 标签栏 → 内容区。
///
/// 同时是键盘快捷键与根焦点的宿主。
class BrowserShell extends StatefulWidget {
  const BrowserShell({super.key});

  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell> {
  /// 快捷键的焦点落点（当焦点无处可去时收回此处）
  final FocusNode _rootFocus =
      FocusNode(debugLabel: 'browser_root', skipTraversal: true);

  /// 剪贴板链接检测：复制了链接后回浏览器，横幅提示直接访问
  final ClipboardLinkDetector _clipboard = ClipboardLinkDetector();
  StreamSubscription<String>? _clipboardSub;
  bool _clipboardEnabled = false;

  @override
  void initState() {
    super.initState();
    // 启动后再按配置启停（首次 build 会同步一次）
  }

  /// 按设置启停剪贴板检测（设置页关闭后不再轮询/弹提示）
  void _syncClipboard(bool enabled) {
    if (enabled == _clipboardEnabled) return;
    _clipboardEnabled = enabled;
    if (enabled) {
      _clipboardSub?.cancel();
      _clipboardSub = _clipboard.links.listen(_onClipboardLink);
      _clipboard.start();
    } else {
      _clipboardSub?.cancel();
      _clipboardSub = null;
      _clipboard.stop();
    }
  }

  /// 剪贴板出现新链接：横幅提示，点击访问
  void _onClipboardLink(String url) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('检测到剪贴板链接：$url',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '访问',
          onPressed: () =>
              context.read<TabManager>().navigateActive(url),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _clipboardSub?.cancel();
    _clipboard.dispose();
    _rootFocus.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // 窄屏（手机竖屏）：工具栏在上，标签栏在下
    final compact = width < 720;

    final tm = context.watch<TabManager>();
    final tab = tm.active;
    final uiState = context.watch<BrowserUiState>();
    final config = context.watch<ConfigService>();
    final findOpen = uiState.findOpen;

    // 剪贴板检测按设置实时启停
    _syncClipboard(config.clipboardDetectEnabled);
    // 底部导航模式：顶栏只留搜索框（书签栏也一并收起）
    final minimal = compact && config.bottomNavEnabled;

    // 快捷键绑定表：随活动标签/配置变化重建
    final bindings = browserShortcutBindings(context);

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        child: BrowserFocus(
          rootFocus: _rootFocus,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  if (!compact) const BrowserTabBar(),
                  const MainToolbar(),
                  if (!minimal && config.showBookmarksBar)
                    const BookmarksBar(),
                  // 二级工具栏（工具箱），展开/收起带尺寸动画
                  AnimatedSize(
                    duration: ZbTokens.normal,
                    curve: ZbTokens.easeInOut,
                    alignment: Alignment.topCenter,
                    child: uiState.secondaryOpen
                        ? const SecondaryToolbar()
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                  const _ProgressStrip(),
                  if (compact) const BrowserTabBar(compact: true),
                  if (findOpen && tab != null)
                    FindBar(
                      onFind: tab.kernel.findStart,
                      onNext: tab.kernel.findNext,
                      onClose: () async {
                        await tab.kernel.findClear();
                        if (context.mounted) {
                          context.read<BrowserUiState>().closeFind();
                          BrowserFocus.ensureHeld(context);
                        }
                      },
                    ),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      // 点击网页内容后若焦点已丢失，收回根节点以保证快捷键可用
                      onPointerDown: (_) => BrowserFocus.ensureHeld(context),
                      child: Stack(
                        // 地址栏联想下拉需要绘制到工具栏之外的区域
                        clipBehavior: Clip.none,
                        children: [
                          const _ContentArea(),
                          const _SniffHintBar(),
                          const OmniboxSuggestions(),
                          if (uiState.sniffOpen)
                            const Positioned.fill(child: SniffPanel()),
                        ],
                      ),
                    ),
                  ),
                  // 长按菜单绑定（不可见，高度为 0）
                  const _ContextMenuBinder(child: SizedBox.shrink()),
                  // 用户脚本安装提示绑定
                  const _UserscriptBinder(child: SizedBox.shrink()),
                  // 扩展通知绑定
                  const _ExtensionNotificationBinder(child: SizedBox.shrink()),
                  // Firefox 风格底部导航栏（窄屏 + 设置开启时显示）
                  if (compact && config.bottomNavEnabled) const BottomNavBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 绑定当前活动标签的长按菜单流（标签切换时重新订阅）
class _ContextMenuBinder extends StatefulWidget {
  final Widget child;
  const _ContextMenuBinder({required this.child});

  @override
  State<_ContextMenuBinder> createState() => _ContextMenuBinderState();
}

class _ContextMenuBinderState extends State<_ContextMenuBinder> {
  String? _boundTabId;
  StreamSubscription? _sub;

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tab = tm.active;

    if (tab?.id != _boundTabId) {
      _boundTabId = tab?.id;
      _sub?.cancel();
      if (tab != null) {
        _sub = tab.kernel.contextMenu.listen((info) {
          ContextMenuSheet.show(
            info,
            onOpenNewTab: (url) => tm.createTab(url: url),
            onDownload: (url) => tm.downloadRunner.start(url),
          );
        });
      }
    }
    return widget.child;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// 用户脚本安装提示绑定
class _UserscriptBinder extends StatefulWidget {
  final Widget child;
  const _UserscriptBinder({required this.child});

  @override
  State<_UserscriptBinder> createState() => _UserscriptBinderState();
}

class _UserscriptBinderState extends State<_UserscriptBinder> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final tm = context.read<TabManager>();
    _sub = tm.userscriptInstallRequests.listen((url) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('检测到用户脚本：${_nameOf(url)}'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '安装',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await tm.installUserscriptFromUrl(url);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(ok ? '用户脚本已安装' : '安装失败'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      );
    });
  }

  String _nameOf(String url) {
    final segs = Uri.tryParse(url)?.pathSegments ?? const [];
    return segs.isEmpty ? url : segs.last;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 扩展通知绑定（将 bridge 通知以 SnackBar 呈现）
class _ExtensionNotificationBinder extends StatefulWidget {
  final Widget child;
  const _ExtensionNotificationBinder({required this.child});

  @override
  State<_ExtensionNotificationBinder> createState() =>
      _ExtensionNotificationBinderState();
}

class _ExtensionNotificationBinderState
    extends State<_ExtensionNotificationBinder> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final tm = context.read<TabManager>();
    _sub = tm.extensionNotifications.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 地址栏下方的加载进度条
class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip();

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tab = tm.active;
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<double>(
      valueListenable: tab?.progress ?? ValueNotifier<double>(0),
      builder: (_, value, __) {
        final show = value > 0 && value < 1;
        return AnimatedContainer(
          duration: ZbTokens.fast,
          height: show ? 2.5 : 0,
          child: show
              ? LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.transparent,
                  color: scheme.primary,
                )
              : null,
        );
      },
    );
  }
}

/// 网页内容区：IndexedStack 保持所有标签页内核状态存活
class _ContentArea extends StatelessWidget {
  const _ContentArea();

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tabs = tm.tabs;
    if (tabs.isEmpty) return const SizedBox.expand();

    final active = tm.active;
    final index = active == null ? 0 : tabs.indexOf(active);

    return IndexedStack(
      index: index < 0 ? 0 : index,
      children: [
        for (final tab in tabs)
          SizedBox.expand(
            key: PageStorageKey('content_${tab.id}'),
            child: tab.kernel.buildView(),
          ),
      ],
    );
  }
}

/// 自动嗅探提示横幅：发现视频/音频时浮在内容顶部，点击打开嗅探面板
class _SniffHintBar extends StatefulWidget {
  const _SniffHintBar();

  @override
  State<_SniffHintBar> createState() => _SniffHintBarState();
}

class _SniffHintBarState extends State<_SniffHintBar> {
  SniffHint? _hint;
  StreamSubscription? _sub;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sub = context.read<TabManager>().sniffHints.listen(_show);
    });
  }

  void _show(SniffHint h) {
    _hide?.cancel();
    setState(() => _hint = h);
    _hide = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  void _open() {
    context.read<BrowserUiState>().openSniff();
    context.read<TabManager>().active?.kernel.triggerSniff();
    setState(() => _hint = null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _hint;
    final zb = context.zb;
    return Positioned(
      top: 12,
      left: 14,
      right: 14,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: ZbTokens.normal,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                      begin: const Offset(0, -0.6), end: Offset.zero)
                  .animate(anim),
              child: child,
            ),
          ),
          child: h == null
              ? const SizedBox.shrink(key: ValueKey('empty'))
              : Material(
                  key: const ValueKey('hint'),
                  elevation: 4,
                  borderRadius: BorderRadius.circular(24),
                  color: zb.chromeElevated,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _open,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: ZbTokens.s6, vertical: ZbTokens.s5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: zb.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.satellite_alt,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: ZbTokens.s4),
                          Text(h.message,
                              style: TextStyle(
                                  fontSize: 12.5, color: zb.textPrimary)),
                          const SizedBox(width: ZbTokens.s4),
                          Icon(Icons.chevron_right,
                              size: 18, color: zb.textMuted),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
