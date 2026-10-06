import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/plugin/plugin_manager.dart';
import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
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

    return Container(
      height: ZbTokens.toolbarHeight,
      decoration: BoxDecoration(
        color: zb.chromeElevated,
        border: Border(bottom: BorderSide(color: zb.hairline, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: ZbTokens.s4),
      child: Row(
        children: [
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
          const AddressBar(),
          const SizedBox(width: ZbTokens.s2),
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
      ),
    );
  }
}

/// 主菜单（⋮）
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
      onSelected: (value) => _onMenu(context, value),
      itemBuilder: (_) => [
        _row('new_tab', Icons.add, '新建标签页', hint: 'Ctrl+T'),
        _row('new_private', Icons.visibility_off_outlined, '新建隐私标签',
            hint: 'Ctrl+Shift+N'),
        PopupMenuItem<String>(
          value: 'reopen',
          enabled: tm.canReopenClosedTab,
          height: 38,
          child: _MenuRow(
            Icons.restore_page_outlined,
            tm.canReopenClosedTab ? '恢复关闭的标签页' : '恢复关闭的标签页（无）',
            hint: 'Ctrl+Shift+T',
          ),
        ),
        _row('restore_session', Icons.history_toggle_off, '恢复上次会话'),
        const PopupMenuDivider(height: 1),
        _row('reload', Icons.refresh, '刷新', hint: 'F5'),
        _row('hard_reload', Icons.cached, '强制刷新（忽略缓存）', hint: 'Ctrl+Shift+R'),
        const PopupMenuDivider(height: 1),
        _row('bookmarks', Icons.bookmark_outline, '书签', hint: 'Ctrl+Shift+O'),
        _row('history', Icons.history, '历史记录', hint: 'Ctrl+H'),
        _row('downloads', Icons.download_outlined, '下载内容', hint: 'Ctrl+J'),
        _row('find', Icons.search, '页面中查找', hint: 'Ctrl+F'),
        const PopupMenuDivider(height: 1),
        // 缩放
        PopupMenuItem<String>(
          enabled: false,
          height: 34,
          child: _MenuRow(
            Icons.zoom_out_map,
            '缩放 ${ZoomService.label(tm.active == null ? 1.0 : tm.zoomFor(tm.active!))}',
          ),
        ),
        _row('zoom_in', Icons.add, '放大', hint: 'Ctrl++', indent: true),
        _row('zoom_out', Icons.remove, '缩小', hint: 'Ctrl+-', indent: true),
        _row('zoom_reset', Icons.restart_alt, '重置缩放', hint: 'Ctrl+0',
            indent: true),
        const PopupMenuDivider(height: 1),
        CheckedPopupMenuItem<String>(
          value: 'desktop',
          checked: tab?.desktopMode.value ?? false,
          height: 38,
          child: const _MenuRow(Icons.desktop_windows, '桌面版网站'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'bookmarks_bar',
          checked: config.showBookmarksBar,
          height: 38,
          child: const _MenuRow(Icons.bookmarks_outlined, '显示书签栏',
              hint: 'Ctrl+Shift+B'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'sniff_auto',
          checked: config.autoSniff,
          height: 38,
          child: const _MenuRow(Icons.satellite_alt_outlined, '自动嗅探媒体资源'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'js',
          checked: config.jsEnabled,
          height: 38,
          child: const _MenuRow(Icons.javascript_outlined, '启用 JavaScript'),
        ),
        const PopupMenuDivider(height: 1),
        _row('scan', Icons.qr_code_scanner, '扫一扫'),
        _row('share', Icons.share, '分享'),
        _row('fullscreen', Icons.fullscreen, '全屏', hint: 'F11'),
        const PopupMenuDivider(height: 1),
        _row('clear', Icons.cleaning_services_outlined, '清除浏览数据'),
        _row('kernels', Icons.memory_outlined, '内核管理'),
        _row('plugins', Icons.extension, '插件管理'),
        _row('userscripts', Icons.code, '用户脚本'),
        _row('settings', Icons.settings, '设置'),
        _row('about', Icons.info_outline, '关于 Zip Browser'),
      ],
    );
  }

  PopupMenuItem<String> _row(
    String value,
    IconData icon,
    String label, {
    String? hint,
    bool indent = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Padding(
        padding: EdgeInsets.only(left: indent ? ZbTokens.s6 : 0),
        child: _MenuRow(icon, label, hint: hint),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
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
        if (!context.mounted) return;
        final raw = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const QrScanPage()),
        );
        if (raw != null && raw.isNotEmpty) {
          await tm.navigateActive(raw);
        }
      case 'share':
        if (tab != null) {
          final u = tab.url.value;
          await ShareHelper.share(
              u.startsWith('data:') ? tab.title.value : u);
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
        await _showAbout(context, tm);
    }
  }

  /// 关于对话框
  Future<void> _showAbout(BuildContext context, TabManager tm) async {
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
              const Text('版本 0.6.0',
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
