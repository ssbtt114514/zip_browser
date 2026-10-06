import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/kernel/kernel_manager.dart';
import 'core/kernel/kernel_registry.dart';
import 'core/plugin/plugin_manager.dart';
import 'core/script/userscript_manager.dart';
import 'core/tab/tab_manager.dart';
import 'core/theme/appearance_settings.dart';
import 'core/theme/theme_engine.dart';
import 'services/bookmarks_service.dart';
import 'services/config_service.dart';
import 'services/desktop_mode_config.dart';
import 'services/downloads_service.dart';
import 'services/history_service.dart';
import 'services/search_engines_service.dart';
import 'services/session_service.dart';
import 'services/ui_state.dart';
import 'services/url_suggest_service.dart';
import 'services/web_enhance_service.dart';
import 'services/zoom_service.dart';
import 'ui/browser_shell.dart';
import 'ui/omnibox_controller.dart';
import 'ui/widgets/theme_builder.dart';

class ZipBrowserApp extends StatelessWidget {
  final ConfigService config;
  final PluginManager pluginManager;
  final KernelRegistry kernelRegistry;
  final KernelManager kernelManager;
  final TabManager tabManager;
  final BookmarksService bookmarks;
  final HistoryService history;
  final DownloadsService downloads;
  final BrowserUiState uiState;
  final AppearanceSettings appearance;
  final MonetPalette? monetPalette;
  final SearchEnginesService searchEngines;
  final UserscriptManager userscriptManager;
  final DesktopModePreferences desktopModePrefs;
  final WebEnhanceService webEnhance;
  final ZoomService zoomService;
  final SessionService sessionService;
  final UrlSuggestService urlSuggest;

  const ZipBrowserApp({
    super.key,
    required this.config,
    required this.pluginManager,
    required this.kernelRegistry,
    required this.kernelManager,
    required this.tabManager,
    required this.bookmarks,
    required this.history,
    required this.downloads,
    required this.uiState,
    required this.appearance,
    this.monetPalette,
    required this.searchEngines,
    required this.userscriptManager,
    required this.desktopModePrefs,
    required this.webEnhance,
    required this.zoomService,
    required this.sessionService,
    required this.urlSuggest,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ConfigService>.value(value: config),
        Provider<PluginManager>.value(value: pluginManager),
        Provider<KernelRegistry>.value(value: kernelRegistry),
        ChangeNotifierProvider<KernelManager>.value(value: kernelManager),
        ChangeNotifierProvider<WebEnhanceService>.value(value: webEnhance),
        ChangeNotifierProvider<TabManager>.value(value: tabManager),
        ChangeNotifierProvider<BookmarksService>.value(value: bookmarks),
        ChangeNotifierProvider<HistoryService>.value(value: history),
        ChangeNotifierProvider<DownloadsService>.value(value: downloads),
        ChangeNotifierProvider<BrowserUiState>.value(value: uiState),
        ChangeNotifierProvider<AppearanceSettings>.value(value: appearance),
        Provider<MonetPalette?>.value(value: monetPalette),
        ChangeNotifierProvider<SearchEnginesService>.value(value: searchEngines),
        ChangeNotifierProvider<UserscriptManager>.value(value: userscriptManager),
        ChangeNotifierProvider<DesktopModePreferences>.value(
            value: desktopModePrefs),
        ChangeNotifierProvider<ZoomService>.value(value: zoomService),
        Provider<SessionService>.value(value: sessionService),
        Provider<UrlSuggestService>.value(value: urlSuggest),
        // 地址栏控制器：输入框与联想面板共享同一份状态
        ChangeNotifierProvider<OmniboxController>(
          create: (ctx) =>
              OmniboxController()..attach(ctx.read<UrlSuggestService>()),
        ),
      ],
      child: const ThemeBuilder(
        child: BrowserShell(),
      ),
    );
  }
}
