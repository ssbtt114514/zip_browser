import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/plugin/plugin_manager.dart';
import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
import '../../core/tab/url_utils.dart';
import '../../services/config_service.dart';
import '../../services/share_helper.dart';
import '../../services/session_service.dart';
import '../../services/ui_state.dart';
import '../../services/zoom_service.dart';
import '../design/zb_design.dart';
import '../pages/bookmarks_page.dart';
import '../pages/downloads_page.dart';
import '../pages/history_page.dart';
import '../pages/kernels_page.dart';
import '../pages/plugins_page.dart';
import '../pages/qr_scan_page.dart';
import '../pages/settings_page.dart';
import '../pages/userscripts_page.dart';
import 'address_bar.dart';
import 'zb_tool_button.dart';

/// 主工具栏：导航控制 + 地址栏 + 工具箱 + 扩展按钮 + 主菜单。
class MainToolbar extends StatelessWidget {
  const MainToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final tm = context.watch<TabManager>();
    final tab = tm.active;
    final config = context.watch<ConfigService>();
    // 底部导航模式（窄屏 + 设置开启）：顶栏只保留搜索框，
    // 后退/前进/主页/工具箱/扩展/菜单全部收到底部导航栏（BottomNavBar 已有对应按钮）。
    final width = MediaQuery.sizeOf(context).width;
    final minimal = width < 720 && config.bottomNavEnabled;

    return Container(
      height: ZbTokens.toolbarHeight,
      decoration: BoxDecoration(
        color: zb.chromeElevated,
        border: Border(bottom: BorderSide(color: zb.hairline, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: ZbTokens.s4),
      child: Row(
        children: [
          if (!minimal) ...[
            ZbToolButton(
              icon: Icons.arrow_back,
              tooltip: '后退（Alt+←）',
              size: 19,
              onTap: (tab?.canGoBack.value ?? false)
                  ? () => tab?.kernel.goBack()
                  : null,
            ),
            ZbToolButton(
              icon: Icons.arrow_forward,
              tooltip: '前进（Alt+→）',
              size: 19,
              onTap: (tab?.canGoForward.value ?? false)
                  ? () => tab?.kernel.goForward()
                  : null,
            ),
            ZbToolButton(
              icon: Icons.home_outlined,
              tooltip: '主页（Alt+Home）',
              size: 18,
              onTap: () {
                final tm2 = context.read<TabManager>();
                tm2.navigateActive(context.read<ConfigService>().homePage);
              },
            ),
            const SizedBox(width: ZbTokens.s2),
          ],
          const AddressBar(),
          const SizedBox(width: ZbTokens.s2),
          if (!minimal) ...[
            // 工具箱：展开 / 收起二级工具栏
            Consumer<BrowserUiState>(
              builder: (_, ui, __) => ZbToolButton(
                icon: ui.secondaryOpen ? Icons.tune : Icons.tune_outlined,
                tooltip: '工具箱（阅读模式 / 嗅探 / 滤镜）',
                size: 19,
                selected: ui.secondaryOpen,
                onTap: ui.toggleSecondary,
              ),
            ),
            const _ExtensionButtons(),
            const _MainMenuButton(),
          ],
        ],
      ),
    );
  }
}

/// 主菜单（⋮）。菜单项与处理逻辑抽为顶层共享函数（[mainMenuEntries] /
/// [handleMainMenuAction]），供底部导航栏（Firefox 风格）复用。
class _MainMenuButton extends StatelessWidget {
  const _MainMenuButton();

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final config = context.watch<ConfigService>();
    final tab = tm.active;

    return PopupMenuButton<String>(
      tooltip: '菜单',
      splashRadius: 16,
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) => handleMainMenuAction(context, value),
      itemBuilder: (_) => _popupItems(context, tm, config, tab),
    );
  }
}

/// 主菜单条目模型（PopupMenu 与底部弹层共用）
class MainMenuEntry {
  final String value;
  final IconData icon;
  final String label;
  final String? hint;
  final bool dividerBefore;
  const MainMenuEntry(this.value, this.icon, this.label,
      {this.hint, this.dividerBefore = false});
}

/// 组装主菜单条目列表。
List<MainMenuEntry> mainMenuEntries(
  BuildContext context, {
  required TabManager tm,
  required ConfigService config,
  required TabModel? tab,
}) {
  return [
    const MainMenuEntry('new_tab', Icons.add, '新建标签页', hint: 'Ctrl+T'),
    const MainMenuEntry('new_private', Icons.visibility_off_outlined,
        '新建隐私标签', hint: 'Ctrl+Shift+N'),
    MainMenuEntry(
      'reopen',
      Icons.restore_page_outlined,
      tm.canReopenClosedTab ? '恢复关闭的标签页' : '恢复关闭的标签页（无）',
      hint: 'Ctrl+Shift+T',
    ),
    const MainMenuEntry('restore_session', Icons.history_toggle_off, '恢复上次会话'),
    const MainMenuEntry('reload', Icons.refresh, '刷新',
        hint: 'F5', dividerBefore: true),
    const MainMenuEntry('hard_reload', Icons.cached, '强制刷新（忽略缓存）',
        hint: 'Ctrl+Shift+R'),
    const MainMenuEntry('bookmarks', Icons.bookmark_outline, '书签',
        hint: 'Ctrl+Shift+O', dividerBefore: true),
    const MainMenuEntry('history', Icons.history, '历史记录', hint: 'Ctrl+H'),
    const MainMenuEntry('downloads', Icons.download_outlined, '下载内容', hint: 'Ctrl+J'),
    const MainMenuEntry('find', Icons.search, '页面中查找', hint: 'Ctrl+F'),
    MainMenuEntry(
      'zoom_show',
      Icons.zoom_out_map,
      '缩放 ${ZoomService.label(tm.active == null ? 1.0 : tm.zoomFor(tm.active!))}',
      dividerBefore: true,
    ),
    const MainMenuEntry('zoom_in', Icons.add, '放大', hint: 'Ctrl++'),
    const MainMenuEntry('zoom_out', Icons.remove, '缩小', hint: 'Ctrl+-'),
    const MainMenuEntry('zoom_reset', Icons.restart_alt, '重置缩放', hint: 'Ctrl+0'),
    const MainMenuEntry('desktop', Icons.desktop_windows, '桌面版网站',
        dividerBefore: true),
    const MainMenuEntry('bookmarks_bar', Icons.bookmarks_outlined, '显示书签栏',
        hint: 'Ctrl+Shift+B'),
    const MainMenuEntry('sniff_auto', Icons.satellite_alt_outlined, '自动嗅探媒体资源'),
    const MainMenuEntry('js', Icons.javascript_outlined, '启用 JavaScript'),
    const MainMenuEntry('scan', Icons.qr_code_scanner, '扫一扫', dividerBefore: true),
    const MainMenuEntry('share', Icons.share, '分享'),
    const MainMenuEntry('fullscreen', Icons.fullscreen, '全屏', hint: 'F11'),
    const MainMenuEntry('clear', Icons.cleaning_services_outlined, '清除浏览数据',
        dividerBefore: true),
    const MainMenuEntry('kernels', Icons.memory_outlined, '内核管理'),
    const MainMenuEntry('plugins', Icons.extension, '插件管理'),
    const MainMenuEntry('userscripts', Icons.code, '用户脚本'),
    const MainMenuEntry('settings', Icons.settings, '设置'),
    const MainMenuEntry('about', Icons.info_outline, '关于 Zip Browser'),
  ];
}

/// 把 [mainMenuEntries] 转成 PopupMenu 项（桌面/宽屏下拉菜单用）。
List<PopupMenuEntry<String>> _popupItems(
  BuildContext context,
  TabManager tm,
  ConfigService config,
  TabModel? tab,
) {
  final entries = mainMenuEntries(context, tm: tm, config: config, tab: tab);
  final items = <PopupMenuEntry<String>>[];
  for (final e in entries) {
    if (e.dividerBefore) items.add(const PopupMenuDivider(height: 1));
    if (e.value == 'reopen') {
      items.add(PopupMenuItem<String>(
        value: e.value,
        enabled: tm.canReopenClosedTab,
        height: 38,
        child: _MenuRow(e.icon, e.label, hint: e.hint),
      ));
      continue;
    }
    if (e.value == 'desktop' ||
        e.value == 'bookmarks_bar' ||
        e.value == 'sniff_auto' ||
        e.value == 'js') {
      final checked = switch (e.value) {
        'desktop' => tab?.desktopMode.value ?? false,
        'bookmarks_bar' => config.showBookmarksBar,
        'sniff_auto' => config.autoSniff,
        'js' => config.jsEnabled,
        _ => false,
      };
      items.add(CheckedPopupMenuItem<String>(
        value: e.value,
        checked: checked,
        height: 38,
        child: _MenuRow(e.icon, e.label, hint: e.hint),
      ));
      continue;
    }
    if (e.value == 'zoom_show') {
      items.add(PopupMenuItem<String>(
        enabled: false,
        height: 34,
        child: _MenuRow(e.icon, e.label, hint: e.hint),
      ));
      continue;
    }
    items.add(PopupMenuItem<String>(
      value: e.value,
      height: 38,
      child: _MenuRow(e.icon, e.label, hint: e.hint),
    ));
  }
  return items;
}

/// 处理主菜单动作（主菜单与底部导航共用）。
Future<void> handleMainMenuAction(BuildContext context, String value) async {
  final tm = context.read<TabManager>();
  final config = context.read<ConfigService>();
  final uiState = context.read<BrowserUiState>();
  final TabModel? tab = tm.active;

  switch (value) {
    case 'new_tab':
      await tm.createTab();
    case 'new_private':
      await tm.createTab(private: true);
    case 'reopen':
      await tm.reopenClosedTab();
    case 'restore_session':
      await tm.restoreLastSession();
    case 'reload':
      await tab?.kernel.reload();
    case 'hard_reload':
      await tab?.kernel.clearCache();
      await tab?.kernel.reload();
    case 'bookmarks':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookmarksPage(onOpen: (u) => tm.navigateActive(u)),
        ),
      );
    case 'history':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HistoryPage(onOpen: (u) => tm.navigateActive(u)),
        ),
      );
    case 'downloads':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DownloadsPage()),
      );
    case 'find':
      uiState.openFind();
    case 'zoom_in':
      await tm.zoomIn();
    case 'zoom_out':
      await tm.zoomOut();
    case 'zoom_reset':
      await tm.resetZoom();
    case 'desktop':
      if (tab != null) await tm.toggleDesktopMode(tab);
    case 'bookmarks_bar':
      await config.setShowBookmarksBar(!config.showBookmarksBar);
    case 'sniff_auto':
      await config.setAutoSniff(!config.autoSniff);
    case 'js':
      await config.setJsEnabled(!config.jsEnabled);
      if (tab != null) await tab.kernel.reload();
    case 'scan':
      await openQrScan(context);
    case 'share':
      if (tab != null) {
        final u = tab.url.value;
        await ShareHelper.share(u.startsWith('data:') ? tab.title.value : u);
      }
    case 'fullscreen':
      final isFull = uiState.fullscreen;
      await uiState.setFullscreen(!isFull);
    case 'clear':
      if (!context.mounted) return;
      await _confirmClear(context, tm);
    case 'kernels':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const KernelsPage()),
      );
    case 'plugins':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PluginsPage()),
      );
    case 'userscripts':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UserscriptsPage()),
      );
    case 'settings':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      );
    case 'about':
      if (!context.mounted) return;
      await showAboutDialog(context, tm);
  }
}

/// 打开二维码扫描页并处理结果。
Future<void> openQrScan(BuildContext context) async {
  final raw = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const QrScanPage()),
  );
  if (raw == null || raw.isEmpty || !context.mounted) return;
  await handleScanResult(context, raw);
}

/// 扫描结果智能处理：是地址直接访问；纯文本弹窗选择「复制 / 搜索 / 取消」。
Future<void> handleScanResult(BuildContext context, String raw) async {
  final tm = context.read<TabManager>();
  final url = UrlInput.tryResolveUrl(raw);
  if (url != null) {
    await tm.navigateActive(url);
    return;
  }

  final trimmed = raw.trim();
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.qr_code_2),
      title: const Text('扫描结果不是链接'),
      content: Text(
        trimmed,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'copy'),
          child: const Text('复制文本'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'search'),
          child: const Text('搜索'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('取消'),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'copy':
      await Clipboard.setData(ClipboardData(text: trimmed));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
        );
      }
    case 'search':
      await tm.navigateActive(trimmed); // 走地址栏解析：域名补全 / 搜索词
  }
}

/// 关于对话框（版本号取自 [BrowserConstants.appVersion]，不再写死）
Future<void> showAboutDialog(BuildContext context, TabManager tm) async {
  final session = context.read<SessionService>();
  await showDialog<void>(
    context: context,
    builder: (dctx) {
      final zb = dctx.zb;
      return AlertDialog(
        icon: const Icon(Icons.travel_explore),
        title: const Text('Zip Browser'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('版本 ${BrowserConstants.appVersion}',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: ZbTokens.s4),
            Text(
              '可通过 zip 插件扩展功能与内核\n'
              'Android: System WebView · Windows: WebView2\n'
              '当前平台：${Platform.operatingSystem}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, height: 1.6, color: zb.textMuted),
            ),
            const SizedBox(height: ZbTokens.s5),
            Text(
              session.hasSnapshot
                  ? '已保存 ${session.readSnapshot().length} 个标签的会话快照'
                  : '暂无会话快照',
              style: TextStyle(fontSize: 11.5, color: zb.textFaint),
            ),
            const SizedBox(height: ZbTokens.s5),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('作者：ssbtt114514（访问主页）'),
              onPressed: () {
                Navigator.of(dctx).pop();
                tm.createTab(url: 'https://ssbtt114514.github.io');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}

/// 清除浏览数据确认框
Future<void> _confirmClear(BuildContext context, TabManager tm) async {
  bool cookies = true, cache = true, historyFlag = true;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      Widget row(bool value, String label, ValueChanged<bool?> onChanged) {
        return CheckboxListTile(
          dense: true,
          value: value,
          onChanged: onChanged,
          title: Text(label, style: const TextStyle(fontSize: 13.5)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        );
      }

      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('清除浏览数据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(cookies, 'Cookie 与登录状态',
                  (v) => setState(() => cookies = v ?? true)),
              row(cache, '缓存的图片与文件',
                  (v) => setState(() => cache = v ?? true)),
              row(historyFlag, '历史记录',
                  (v) => setState(() => historyFlag = v ?? true)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('清除')),
          ],
        ),
      );
    },
  );

  if (ok == true) {
    await tm.clearBrowsingData(
        cookies: cookies, cache: cache, historyFlag: historyFlag);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('浏览数据已清除'), duration: Duration(seconds: 1)),
      );
    }
  }
}

/// 已启用插件的工具栏按钮
class _ExtensionButtons extends StatelessWidget {
  const _ExtensionButtons();

  @override
  Widget build(BuildContext context) {
    final pm = context.watch<PluginManager>();
    final plugins = pm.toolbarPlugins();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final plugin in plugins)
          ZbToolButton(
            size: 18,
            icon: Icons.extension,
            tooltip: '${plugin.manifest.name} v${plugin.manifest.version}',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('${plugin.manifest.name} v${plugin.manifest.version}'),
                duration: const Duration(seconds: 1),
              ));
            },
          ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? hint;
  const _MenuRow(this.icon, this.label, {this.hint});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    return Row(
      children: [
        Icon(icon, size: 17, color: zb.textMuted),
        const SizedBox(width: ZbTokens.s5),
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 13.5, color: zb.textPrimary)),
        ),
        if (hint != null) ...[
          const SizedBox(width: ZbTokens.s5),
          Text(hint!, style: TextStyle(fontSize: 11, color: zb.textFaint)),
        ],
      ],
    );
  }
}
