import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/plugin/plugin_manager.dart';
import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
import '../../services/share_helper.dart';
import '../../services/ui_state.dart';
import '../pages/bookmarks_page.dart';
import '../pages/downloads_page.dart';
import '../pages/history_page.dart';
import '../pages/kernels_page.dart';
import '../pages/manual_page.dart';
import '../pages/plugins_page.dart';
import '../pages/qr_scan_page.dart';
import '../pages/settings_page.dart';
import '../pages/userscripts_page.dart';
import 'address_bar.dart';
import 'zb_tool_button.dart';

/// 主工具栏：导航控制 + 地址栏 + 扩展按钮 + 菜单
class MainToolbar extends StatelessWidget {
  const MainToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tab = tm.active;

    return Container(
      height: 52,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          ZbToolButton(
            icon: Icons.arrow_back,
            tooltip: '后退',
            onTap: (tab?.canGoBack.value ?? false)
                ? () => tab?.kernel.goBack()
                : null,
          ),
          ZbToolButton(
            icon: Icons.arrow_forward,
            tooltip: '前进',
            onTap: (tab?.canGoForward.value ?? false)
                ? () => tab?.kernel.goForward()
                : null,
          ),
          const SizedBox(width: 2),
          const AddressBar(),
          const SizedBox(width: 2),
          // 工具箱：展开 / 收起二级工具栏
          Consumer<BrowserUiState>(
            builder: (_, ui, __) => ZbToolButton(
              icon: ui.secondaryOpen ? Icons.tune : Icons.tune_outlined,
              tooltip: '工具箱',
              selected: ui.secondaryOpen,
              onTap: ui.toggleSecondary,
            ),
          ),
          const _ExtensionButtons(),
          ZbToolButton(
            icon: Icons.menu_book_outlined,
            tooltip: '使用手册',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManualPage()),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '菜单',
            splashRadius: 16,
            icon: const Icon(Icons.more_vert, size: 19),
            onSelected: (value) => _onMenu(context, value),
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'reload', child: _MenuRow(Icons.refresh, '刷新')),
              PopupMenuItem(
                value: 'reopen',
                enabled: tm.canReopenClosedTab,
                child: _MenuRow(
                  Icons.restore_page_outlined,
                  tm.canReopenClosedTab
                      ? '恢复关闭的标签页'
                      : '恢复关闭的标签页（无）',
                ),
              ),
              const PopupMenuItem(
                  value: 'private',
                  child: _MenuRow(Icons.visibility_off_outlined, '新建隐私标签')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'bookmarks',
                  child: _MenuRow(Icons.bookmark_outline, '书签')),
              const PopupMenuItem(
                  value: 'history', child: _MenuRow(Icons.history, '历史记录')),
              const PopupMenuItem(
                  value: 'downloads',
                  child: _MenuRow(Icons.download_outlined, '下载内容')),
              const PopupMenuItem(
                  value: 'find', child: _MenuRow(Icons.search, '页面中查找')),
              const PopupMenuItem(
                  value: 'scan',
                  child: _MenuRow(Icons.qr_code_scanner, '扫一扫')),
              const PopupMenuItem(
                  value: 'share', child: _MenuRow(Icons.share, '分享')),
              CheckedPopupMenuItem(
                value: 'desktop',
                checked: tab?.desktopMode.value ?? false,
                child: const _MenuRow(Icons.desktop_windows, '桌面版网站'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'clear',
                  child: _MenuRow(Icons.cleaning_services_outlined, '清除浏览数据')),
              const PopupMenuItem(
                  value: 'kernels', child: _MenuRow(Icons.memory_outlined, '内核管理')),
              const PopupMenuItem(
                  value: 'plugins', child: _MenuRow(Icons.extension, '插件管理')),
              const PopupMenuItem(
                  value: 'userscripts',
                  child: _MenuRow(Icons.javascript_outlined, '用户脚本')),
              const PopupMenuItem(
                  value: 'settings', child: _MenuRow(Icons.settings, '设置')),
              const PopupMenuItem(
                  value: 'about', child: _MenuRow(Icons.info_outline, '关于')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    final tm = context.read<TabManager>();
    final TabModel? tab = tm.active;

    switch (value) {
      case 'reload':
        await tab?.kernel.reload();
      case 'reopen':
        await tm.reopenClosedTab();
      case 'private':
        await tm.createTab(private: true);
      case 'bookmarks':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                BookmarksPage(onOpen: (u) => tm.navigateActive(u)),
          ),
        );
      case 'history':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HistoryPage(onOpen: (u) => tm.navigateActive(u)),
          ),
        );
      case 'downloads':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DownloadsPage()),
        );
      case 'find':
        context.read<BrowserUiState>().openFind();
      case 'scan':
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
      case 'desktop':
        if (tab != null) await tm.toggleDesktopMode(tab);
      case 'clear':
        await _confirmClear(context, tm);
      case 'kernels':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const KernelsPage()),
        );
      case 'plugins':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PluginsPage()),
        );
      case 'userscripts':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UserscriptsPage()),
        );
      case 'settings':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
      case 'about':
        if (context.mounted) {
          await showDialog(
            context: context,
            builder: (dctx) => AlertDialog(
              icon: const Icon(Icons.language),
              title: const Text('Zip Browser'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('版本 0.5.0',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    '可通过 zip 插件扩展功能与内核\n'
                    'Android: System WebView · Windows: WebView2\n'
                    '当前平台：${Platform.operatingSystem}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('作者：ssbtt114514（访问主页）'),
                    onPressed: () {
                      Navigator.of(dctx).pop();
                      tm.createTab(
                          url: 'https://ssbtt114514.github.io');
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
            ),
          );
        }
    }
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
  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
