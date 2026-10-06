import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/sniff/sniff_model.dart';
import '../core/tab/tab_manager.dart';
import '../services/ui_state.dart';
import 'context_menu_sheet.dart';
import 'find_bar.dart';
import 'pages/sniff_panel.dart';
import 'widgets/browser_tab_bar.dart';
import 'widgets/main_toolbar.dart';
import 'widgets/secondary_toolbar.dart';

/// 浏览器主外壳
class BrowserShell extends StatelessWidget {
  const BrowserShell({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // 窄屏（手机竖屏）：工具栏在上，标签栏在下
    final compact = width < 720;

    final tm = context.watch<TabManager>();
    final tab = tm.active;
    final uiState = context.watch<BrowserUiState>();
    final findOpen = uiState.findOpen;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (!compact) const BrowserTabBar(),
            const MainToolbar(),
            // 二级工具栏（工具箱），展开/收起带尺寸动画
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
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
                  }
                },
              ),
            Expanded(
              child: Stack(
                children: [
                  const _ContentArea(),
                  const _SniffHintBar(),
                  if (uiState.sniffOpen)
                    const Positioned.fill(child: SniffPanel()),
                ],
              ),
            ),
            // 长按菜单绑定（不可见，高度为 0）
            const _ContextMenuBinder(child: SizedBox.shrink()),
            // 用户脚本安装提示绑定
            const _UserscriptBinder(child: SizedBox.shrink()),
            // 扩展通知绑定
            const _ExtensionNotificationBinder(child: SizedBox.shrink()),
          ],
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

    return ValueListenableBuilder<double>(
      valueListenable: tab?.progress ?? ValueNotifier<double>(0),
      builder: (_, value, __) {
        final show = value > 0 && value < 1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: show ? 3 : 0,
          child: show
              ? LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.transparent,
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
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 10,
      left: 12,
      right: 12,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position:
                Tween(begin: const Offset(0, -0.6), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: h == null
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Material(
                key: const ValueKey('hint'),
                elevation: 3,
                borderRadius: BorderRadius.circular(12),
                color: scheme.primaryContainer,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _open,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.satellite_alt,
                          size: 19, color: scheme.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(h.message,
                            style: TextStyle(
                                fontSize: 13,
                                color: scheme.onPrimaryContainer)),
                      ),
                      Icon(Icons.chevron_right,
                          size: 20, color: scheme.onPrimaryContainer),
                    ]),
                  ),
                ),
              ),
      ),
    );
  }
}
