import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/build_flavor.dart';
import '../../core/constants.dart';
import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
import '../../core/tab/url_utils.dart';
import '../../services/ai_service.dart';
import '../../services/config_service.dart';
import '../../services/share_helper.dart';
import '../../services/session_service.dart';
import '../../services/translate_service.dart';
import '../../services/ui_state.dart';
import '../design/zb_design.dart';
import '../pages/bookmarks_page.dart';
import '../pages/devtools_page.dart';
import '../pages/downloads_page.dart';
import '../pages/history_page.dart';
import '../pages/ocr_page.dart';
import '../pages/qr_scan_page.dart';
import '../pages/settings_page.dart';
import '../pages/update_dialog.dart';
import '../pages/userscripts_page.dart';
import 'address_bar.dart';
import 'zb_tool_button.dart';

/// 主工具栏：导航控制 + 地址栏 + 工具箱 + 主菜单。
class MainToolbar extends StatelessWidget {
  const MainToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tab = tm.active;
    final config = context.watch<ConfigService>();
    // 底部导航模式（窄屏 + 设置开启）：顶栏只保留搜索框，
    // 后退/前进/主页/工具箱/菜单全部收到底部导航栏（BottomNavBar 已有对应按钮）。
    final width = MediaQuery.sizeOf(context).width;
    final minimal = width < 720 && config.bottomNavEnabled;

    return ZbGlassBox(
      height: ZbTokens.toolbarHeight,
      bottomBorder: true,
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
            const _MainMenuButton(),
          ],
        ],
      ),
    );
  }
}

/// 主菜单（⋮）。桌面 / 宽屏用 [MenuAnchor] + [SubmenuButton] 呈现二级菜单；
/// 动作处理抽为顶层共享函数（[handleMainMenuAction]），供底部导航栏复用。
class _MainMenuButton extends StatelessWidget {
  const _MainMenuButton();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        _Submenu(
          icon: Icons.tab_outlined,
          label: '标签页',
          children: [
            _item(context, '新建标签页', 'new_tab', Icons.add, hint: 'Ctrl+T'),
            _item(context, '新建隐私标签', 'new_private',
                Icons.visibility_off_outlined,
                hint: 'Ctrl+Shift+N'),
            Builder(builder: (context) {
              final canReopen = context.watch<TabManager>().canReopenClosedTab;
              return _item(
                context,
                canReopen ? '恢复关闭的标签页' : '恢复关闭的标签页（无）',
                'reopen',
                Icons.restore_page_outlined,
                hint: 'Ctrl+Shift+T',
                enabled: canReopen,
              );
            }),
            _item(context, '恢复上次会话', 'restore_session',
                Icons.history_toggle_off),
          ],
        ),
        _Submenu(
          icon: Icons.description_outlined,
          label: '页面',
          children: [
            _item(context, '刷新', 'reload', Icons.refresh, hint: 'F5'),
            _item(context, '强制刷新（忽略缓存）', 'hard_reload', Icons.cached,
                hint: 'Ctrl+Shift+R'),
            _item(context, '页面中查找', 'find', Icons.search, hint: 'Ctrl+F'),
            if (BuildFlavorInfo.current != BuildFlavor.none) ...[
              _item(context, '翻译网页 / 选中文本', 'translate', Icons.translate),
              _item(context, 'AI 解读本页', 'ai_read', Icons.auto_awesome),
            ],
          ],
        ),
        _Submenu(
          icon: Icons.folder_outlined,
          label: '数据',
          children: [
            _item(context, '书签', 'bookmarks', Icons.bookmark_outline,
                hint: 'Ctrl+Shift+O'),
            _item(context, '历史记录', 'history', Icons.history, hint: 'Ctrl+H'),
            _item(context, '下载内容', 'downloads', Icons.download_outlined,
                hint: 'Ctrl+J'),
            _item(context, '清除浏览数据', 'clear',
                Icons.cleaning_services_outlined),
          ],
        ),
        Builder(builder: (context) {
          final config = context.watch<ConfigService>();
          final ui = context.watch<BrowserUiState>();
          return _Submenu(
            icon: Icons.tune,
            label: '显示',
            children: [
              _toggle(context, '显示书签栏', 'bookmarks_bar',
                  config.showBookmarksBar,
                  hint: 'Ctrl+Shift+B'),
              _toggle(context, '自动嗅探媒体资源', 'sniff_auto', config.autoSniff),
              _toggle(context, '启用 JavaScript', 'js', config.jsEnabled),
              _toggle(context, '广告拦截', 'adblock', config.adBlockEnabled),
              _toggle(context, '全屏', 'fullscreen', ui.fullscreen, hint: 'F11'),
            ],
          );
        }),
        _Submenu(
          icon: Icons.build_outlined,
          label: '工具',
          children: [
            _item(context, '扫一扫', 'scan', Icons.qr_code_scanner),
            _item(context, '文字识别（图片取字）', 'ocr_text',
                Icons.document_scanner_outlined),
            _item(context, '分享', 'share', Icons.share),
            _item(context, '开发者工具箱', 'devtools', Icons.developer_mode),
            if (BuildFlavorInfo.current != BuildFlavor.none)
              _item(context, '用户脚本', 'userscripts', Icons.code),
          ],
        ),
        _Submenu(
          icon: Icons.settings_outlined,
          label: '系统',
          children: [
            _item(context, '检查更新', 'check_update', Icons.system_update_alt),
            _item(context, '设置', 'settings', Icons.settings),
            _item(context, '关于 Zip Browser', 'about', Icons.info_outline),
          ],
        ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: '菜单',
        splashRadius: 16,
        icon: const Icon(Icons.more_vert, size: 20),
        onPressed: () => controller.open(),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    String? hint,
    bool enabled = true,
  }) {
    return MenuItemButton(
      onPressed: enabled ? () => handleMainMenuAction(context, value) : null,
      leadingIcon: _LeadIcon(icon),
      trailingIcon: hint == null
          ? null
          : Text(hint, style: TextStyle(fontSize: 11, color: context.zb.textFaint)),
      child: Text(label,
          style: TextStyle(fontSize: 13.5, color: context.zb.textPrimary)),
    );
  }

  Widget _toggle(
    BuildContext context,
    String label,
    String value,
    bool checked, {
    String? hint,
  }) {
    return MenuItemButton(
      onPressed: () => handleMainMenuAction(context, value),
      leadingIcon: Icon(
        checked ? Icons.check_box : Icons.check_box_outline_blank,
        size: 17,
        color: checked ? Theme.of(context).colorScheme.primary : context.zb.textMuted,
      ),
      trailingIcon: hint == null
          ? null
          : Text(hint, style: TextStyle(fontSize: 11, color: context.zb.textFaint)),
      child: Text(label,
          style: TextStyle(fontSize: 13.5, color: context.zb.textPrimary)),
    );
  }
}

/// 二级菜单分组容器。
class _Submenu extends StatelessWidget {
  const _Submenu({
    required this.icon,
    required this.label,
    required this.children,
  });

  final IconData icon;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SubmenuButton(
      menuChildren: children,
      leadingIcon: Icon(icon, size: 17, color: context.zb.textMuted),
      child: Text(label, style: TextStyle(fontSize: 13.5, color: context.zb.textPrimary)),
    );
  }
}

/// 菜单图标统一着色。
class _LeadIcon extends StatelessWidget {
  const _LeadIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 17, color: context.zb.textMuted);
  }
}

/// 主菜单条目模型（底部弹层用；桌面端为二级菜单，见 [_MainMenuButton]）。
class MainMenuEntry {
  final String value;
  final IconData icon;
  final String label;
  final String? hint;
  final bool dividerBefore;
  const MainMenuEntry(this.value, this.icon, this.label,
      {this.hint, this.dividerBefore = false});
}

/// 组装主菜单条目列表（按「标签 → 页面 → 数据 → 开关 → 工具 → 系统」分组）。
List<MainMenuEntry> mainMenuEntries(
  BuildContext context, {
  required TabManager tm,
  required ConfigService config,
  required TabModel? tab,
}) {
  final flavor = BuildFlavorInfo.current;
  return [
    // —— 标签 ——
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
    // —— 页面 ——
    const MainMenuEntry('reload', Icons.refresh, '刷新',
        hint: 'F5', dividerBefore: true),
    const MainMenuEntry('hard_reload', Icons.cached, '强制刷新（忽略缓存）',
        hint: 'Ctrl+Shift+R'),
    const MainMenuEntry('find', Icons.search, '页面中查找', hint: 'Ctrl+F'),
    if (flavor != BuildFlavor.none) ...[
      const MainMenuEntry('translate', Icons.translate, '翻译网页 / 选中文本'),
      const MainMenuEntry('ai_read', Icons.auto_awesome, 'AI 解读本页'),
    ],
    // —— 数据 ——
    const MainMenuEntry('bookmarks', Icons.bookmark_outline, '书签',
        hint: 'Ctrl+Shift+O', dividerBefore: true),
    const MainMenuEntry('history', Icons.history, '历史记录', hint: 'Ctrl+H'),
    const MainMenuEntry('downloads', Icons.download_outlined, '下载内容', hint: 'Ctrl+J'),
    const MainMenuEntry('clear', Icons.cleaning_services_outlined, '清除浏览数据'),
    // —— 开关 ——
    const MainMenuEntry('bookmarks_bar', Icons.bookmarks_outlined, '显示书签栏',
        hint: 'Ctrl+Shift+B', dividerBefore: true),
    const MainMenuEntry('sniff_auto', Icons.satellite_alt_outlined, '自动嗅探媒体资源'),
    const MainMenuEntry('js', Icons.javascript_outlined, '启用 JavaScript'),
    const MainMenuEntry('adblock', Icons.block_outlined, '广告拦截'),
    const MainMenuEntry('fullscreen', Icons.fullscreen, '全屏', hint: 'F11'),
    // —— 工具 ——
    const MainMenuEntry('scan', Icons.qr_code_scanner, '扫一扫', dividerBefore: true),
    const MainMenuEntry('ocr_text', Icons.document_scanner_outlined, '文字识别（图片取字）'),
    const MainMenuEntry('share', Icons.share, '分享'),
    // —— 系统 ——
    if (flavor != BuildFlavor.none)
      const MainMenuEntry('userscripts', Icons.code, '用户脚本',
          dividerBefore: true),
    const MainMenuEntry('devtools', Icons.developer_mode, '开发者工具箱',
        dividerBefore: true),
    const MainMenuEntry('check_update', Icons.system_update_alt, '检查更新'),
    const MainMenuEntry('settings', Icons.settings, '设置'),
    const MainMenuEntry('about', Icons.info_outline, '关于 Zip Browser'),
  ];
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
    case 'translate':
      if (tab != null && context.mounted) {
        await _translatePage(context, tab);
      }
    case 'ai_read':
      if (tab != null && context.mounted) {
        await _aiReadPage(context, tab);
      }
    case 'ocr_text':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OcrPage()),
      );
    case 'check_update':
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('正在检查更新…'), duration: Duration(seconds: 2)),
      );
      try {
        final info = await UpdateCheckHelper.checkWithUi();
        if (info == null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已是最新版本')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('检查失败：$e')));
        }
      }
    case 'devtools':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DevToolsPage()),
      );
    case 'zoom_in':
      await tm.zoomIn();
    case 'zoom_out':
      await tm.zoomOut();
    case 'zoom_reset':
      await tm.resetZoom();
    case 'bookmarks_bar':
      await config.setShowBookmarksBar(!config.showBookmarksBar);
    case 'sniff_auto':
      await config.setAutoSniff(!config.autoSniff);
    case 'js':
      await config.setJsEnabled(!config.jsEnabled);
      if (tab != null) await tab.kernel.reload();
    case 'adblock':
      await config.setAdBlockEnabled(!config.adBlockEnabled);
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
            Text('版本 ${BrowserConstants.appVersion} · ${BuildFlavorInfo.label}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: ZbTokens.s4),
            Text(
              '可通过独立内核包（.zbk）扩展浏览器内核\n'
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

/// 页面工具共享入口：主菜单与二级工具栏「更多工具」共用。
Future<void> handlePageToolsAction(
    BuildContext context, String value, TabModel tab) async {
  switch (value) {
    case 'translate':
      await _translatePage(context, tab);
    case 'ai_read':
      await _aiReadPage(context, tab);
    case 'ocr_text':
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OcrPage()),
      );
  }
}

/// 翻译当前页（选中文本优先，否则取正文前 3000 字）。
Future<void> _translatePage(BuildContext context, TabModel tab) async {
  final messenger = ScaffoldMessenger.of(context);
  // 展示加载提示
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(width: 16),
        Text('正在翻译…'),
      ]),
    ),
  );
  try {
    final text = await TranslateService.extractText(
        (js) => tab.kernel.evaluateJavascript(js));
    if (text.isEmpty) throw Exception('页面上没有可翻译的文本');
    final result = await TranslateService.translate(text);
    if (!context.mounted) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.translate),
        title: const Text('翻译结果（中文）'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
          child: SingleChildScrollView(
            child: SelectableText(result,
                style: const TextStyle(fontSize: 13.5, height: 1.6)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result));
              if (dctx.mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('已复制'), duration: Duration(seconds: 1)),
                );
              }
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    messenger.showSnackBar(SnackBar(content: Text('翻译失败：$e')));
  }
}

/// AI 解读当前页（需在设置中配置 OpenAI 兼容接口）。
Future<void> _aiReadPage(BuildContext context, TabModel tab) async {
  final config = context.read<ConfigService>();
  if (!AiService.isConfigured(config)) {
    final go = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.auto_awesome),
        title: const Text('先配置 AI 接口'),
        content: const Text(
            'AI 解读需要一个 OpenAI 兼容接口（OpenAI / DeepSeek / Kimi 等均可）。\n\n'
            '到「设置 → AI 解读」填入 API 地址、Key 和模型名即可使用。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('去设置')),
        ],
      ),
    );
    if (go == true && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      );
    }
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(width: 16),
        Text('AI 正在阅读页面…'),
      ]),
    ),
  );
  try {
    final text = await AiService.extractPageText(
        (js) => tab.kernel.evaluateJavascript(js));
    if (text.isEmpty) throw Exception('页面上没有可读的文本');
    final answer = await AiService.chat(
      config,
      '请阅读以下网页内容，用中文总结要点（分条列出），'
          '并指出页面的主题、关键信息和值得注意的内容：\n\n$text',
      system: '你是网页解读助手，用简体中文、结构化地输出要点，不编造内容。',
    );
    if (!context.mounted) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.auto_awesome),
        title: const Text('AI 解读'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
          child: SingleChildScrollView(
            child: SelectableText(answer,
                style: const TextStyle(fontSize: 13.5, height: 1.6)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: answer));
              if (dctx.mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('已复制'), duration: Duration(seconds: 1)),
                );
              }
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    messenger.showSnackBar(SnackBar(content: Text('AI 解读失败：$e')));
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

