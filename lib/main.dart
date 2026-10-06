import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'core/kernel/kernel_manager.dart';
import 'core/kernel/kernel_registry.dart';
import 'core/plugin/plugin_manager.dart';
import 'core/tab/tab_manager.dart';
import 'core/script/userscript_manager.dart';
import 'core/theme/appearance_settings.dart';
import 'core/theme/theme_engine.dart';
import 'services/bookmarks_service.dart';
import 'services/config_service.dart';
import 'services/desktop_mode_config.dart';
import 'services/download_runner.dart';
import 'services/downloads_service.dart';
import 'services/history_service.dart';
import 'services/host_bridge_api.dart';
import 'services/paths.dart';
import 'services/search_engines_service.dart';
import 'services/session_service.dart';
import 'services/ui_state.dart';
import 'services/url_suggest_service.dart';
import 'services/web_enhance_service.dart';
import 'services/zoom_service.dart';

/// 监听应用生命周期：退出前落盘会话快照，便于下次「恢复上次会话」。
class _SessionLifecycleObserver extends WidgetsBindingObserver {
  final TabManager tabManager;
  final SessionService sessionService;

  _SessionLifecycleObserver(this.tabManager, this.sessionService);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      tabManager.flushSession();
      if (state == AppLifecycleState.detached) {
        sessionService.markCleanExit();
      }
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 目录
  await AppPaths.init();

  // 2. 配置
  final config = await ConfigService.create();

  // 2b. 外观设置
  final appearance = await AppearanceSettings.create();

  // 2b-2. 莫奈动态色板（Android 12+，其他平台返回 null）
  final MonetPalette? monetPalette =
      await DynamicColorPlugin.getCorePalette();

  // 2c. 搜索引擎
  final searchEngines = SearchEnginesService(config);

  // 2d. 桌面模式偏好
  final desktopModePrefs = DesktopModePreferences(config);

  // 2e. 网页缩放（按站点记忆）
  final zoomService = await ZoomService.create();

  // 2f. 会话（上次打开的标签页）
  final sessionService = await SessionService.create();

  // 3. 数据服务：书签 / 历史 / 下载
  final bookmarks = BookmarksService(
    File(p.join(AppPaths.profilesDir.path, 'bookmarks.json')),
  )..load();
  final history = HistoryService(
    File(p.join(AppPaths.profilesDir.path, 'history.json')),
  )..load();
  final downloads = DownloadsService(
    File(p.join(AppPaths.profilesDir.path, 'downloads.json')),
  )..load();
  final downloadRunner = DownloadRunner(
    service: downloads,
    downloadDir: AppPaths.downloadsDir,
  );
  final uiState = BrowserUiState();

  // 3b. 地址栏自动补全（本地历史 + 书签 + 搜索）
  final urlSuggest = UrlSuggestService(
    history: history,
    bookmarks: bookmarks,
    searchTemplate: () => config.searchEngine,
  );

  // 4. 插件系统
  final pluginManager = PluginManager(pluginsDir: AppPaths.pluginsDir)
    ..loadAll();

  // 4b. 用户脚本管理器
  final userscriptManager =
      UserscriptManager(scriptsDir: AppPaths.userscriptsDir);

  // 5. 独立内核包管理器（扫描已安装的 .zbk 内核包）
  final kernelManager = KernelManager(kernelsDir: AppPaths.kernelsDir)
    ..loadAll();

  // 5b. 内核注册表（系统内核 + 独立内核包 + 插件携带内核）
  final kernelRegistry = KernelRegistry(
    config: config,
    pluginManager: pluginManager,
    kernelManager: kernelManager,
  );

  // 5c. 网页阅读与显示增强（滤镜 / 阅读模式 / 字号行距）
  final webEnhance = WebEnhanceService(config);

  // 6. 标签页管理器 + 宿主 bridge API
  final tabManager = TabManager(
    kernelRegistry: kernelRegistry,
    pluginManager: pluginManager,
    config: config,
    history: history,
    bookmarks: bookmarks,
    downloadRunner: downloadRunner,
    appearance: appearance,
    userscriptManager: userscriptManager,
    desktopModePrefs: desktopModePrefs,
    webEnhance: webEnhance,
    zoomService: zoomService,
    sessionService: sessionService,
  );
  tabManager.hostApi = HostBridgeApi(
    tabManager: tabManager,
    config: config,
    kernelRegistry: kernelRegistry,
  );

  // 6b. 生命周期：退出时保存会话
  final lifecycle = _SessionLifecycleObserver(tabManager, sessionService);
  WidgetsBinding.instance.addObserver(lifecycle);

  // 7. 首个标签页：按启动设置决定打开主页还是恢复上次会话
  final snapshot = sessionService.readSnapshot();
  if (sessionService.startupMode == SessionStartupMode.restore &&
      snapshot.isNotEmpty) {
    await tabManager.restoreLastSession();
  } else {
    await tabManager.createTab();
  }

  runApp(ZipBrowserApp(
    config: config,
    pluginManager: pluginManager,
    kernelRegistry: kernelRegistry,
    kernelManager: kernelManager,
    tabManager: tabManager,
    bookmarks: bookmarks,
    history: history,
    downloads: downloads,
    uiState: uiState,
    appearance: appearance,
    monetPalette: monetPalette,
    searchEngines: searchEngines,
    userscriptManager: userscriptManager,
    desktopModePrefs: desktopModePrefs,
    webEnhance: webEnhance,
    zoomService: zoomService,
    sessionService: sessionService,
    urlSuggest: urlSuggest,
  ));
}
