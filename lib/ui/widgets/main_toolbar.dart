import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/plugin/plugin_manager.dart';
import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
import '../../services/share_helper.dart';
import '../../services/ui_state.dart';
import '../../services/web_enhance_service.dart';
import '../pages/bookmarks_page.dart';
import '../pages/downloads_page.dart';
import '../pages/history_page.dart';
import '../pages/kernels_page.dart';
import '../pages/plugins_page.dart';
import '../pages/settings_page.dart';
import '../pages/userscripts_page.dart';
import 'address_bar.dart';

/// 主工具栏：导航控制 + 地址栏 + 扩展按钮 + 菜单
class MainToolbar extends StatelessWidget {
  const MainToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tab = tm.active;

    return Container(
      height: 44,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          _NavButton(
            icon: Icons.arrow_back,
            enabled: tab?.canGoBack.value ?? false,
            tooltip: '后退',
            onTap: () => tab?.kernel.goBack(),
          ),
          _NavButton(
            icon: Icons.arrow_forward,
            enabled: tab?.canGoForward.value ?? false,
            tooltip: '前进',
            onTap: () => tab?.kernel.goForward(),
          ),
          const SizedBox(width: 2),
          const AddressBar(),
          const SizedBox(width: 4),
          // 资源嗅探按钮
          Consumer<BrowserUiState>(
            builder: (_, ui, __) => IconButton(
              icon: Icon(
                ui.sniffOpen ? Icons.satellite_alt : Icons.satellite_alt_outlined,
                size: 19,
                color: ui.sniffOpen
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: '资源嗅探',
              splashRadius: 15,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () {
                ui.toggleSniff();
                if (ui.sniffOpen) {
                  // 打开面板时触发一次扫描
                  context.read<TabManager>().active?.kernel.triggerSniff();
                }
              },
            ),
          ),
          // 阅读模式（切换当前页）
          IconButton(
            icon: const Icon(Icons.chrome_reader_mode_outlined, size: 19),
            tooltip: '阅读模式',
            splashRadius: 15,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: tab == null
                ? null
                : () => context
                    .read<WebEnhanceService>()
                    .toggleReader(tab.kernel),
          ),
          const _ExtensionButtons(),
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
          showAboutDialog(
            context: context,
            applicationName: 'Zip Browser',
            applicationVersion: '0.2.0',
            applicationLegalese:
                '可通过 zip 插件扩展功能与内核\nAndroid: System WebView · Windows: WebView2\n${Platform.operatingSystem}',
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

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 19),
      tooltip: tooltip,
      splashRadius: 15,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.3),
      onPressed: enabled ? onTap : null,
    );
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: IconButton(
              tooltip: plugin.manifest.name,
              splashRadius: 15,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.extension, size: 18),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${plugin.manifest.name} v${plugin.manifest.version}'),
                  duration: const Duration(seconds: 1),
                ));
              },
            ),
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
