import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../services/bookmarks_service.dart';
import '../../services/config_service.dart';
import '../../services/desktop_mode_config.dart';
import '../../services/download_runner.dart';
import '../../services/history_service.dart';
import '../../services/host_bridge_api.dart';
import '../../services/web_enhance_service.dart';
import '../constants.dart';
import '../kernel/kernel_registry.dart';
import '../kernel/kernel_types.dart';
import '../plugin/plugin_manager.dart';
import '../script/userscript_manager.dart';
import '../theme/appearance_settings.dart';
import 'home_page.dart';
import 'tab_model.dart';
import 'url_utils.dart';

/// 已关闭标签页（用于「恢复关闭的标签页」）
class _ClosedTab {
  final String url;
  final String title;
  final String? groupId;
  const _ClosedTab({required this.url, required this.title, this.groupId});
}

/// 标签页管理器
class TabManager extends ChangeNotifier {
  final KernelRegistry kernelRegistry;
  final PluginManager pluginManager;
  final ConfigService config;
  final HistoryService history;
  final BookmarksService bookmarks;
  final DownloadRunner downloadRunner;
  final AppearanceSettings? appearance;
  final UserscriptManager? userscriptManager;
  final DesktopModePreferences? desktopModePrefs;
  final WebEnhanceService? webEnhance;
  late final HostBridgeApi hostApi;

  final List<TabModel> _tabs = [];
  final List<TabGroup> _groups = [];
  final List<_ClosedTab> _closedTabs = [];
  int _activeIndex = -1;
  int _seq = 0;
  int _groupSeq = 0;

  /// 恢复关闭标签页的栈上限
  static const int _maxClosedStack = 25;

  /// 检测到可安装的用户脚本链接（供 UI 提示安装）
  final _userscriptRequestCtrl = StreamController<String>.broadcast();
  Stream<String> get userscriptInstallRequests => _userscriptRequestCtrl.stream;

  /// 扩展通过 bridge 触发的通知（供 UI 以 SnackBar 呈现）
  final _notificationCtrl = StreamController<String>.broadcast();
  Stream<String> get extensionNotifications => _notificationCtrl.stream;

  /// 供 host bridge 推送扩展通知
  void notifyExtension(String message) => _notificationCtrl.add(message);

  TabManager({
    required this.kernelRegistry,
    required this.pluginManager,
    required this.config,
    required this.history,
    required this.bookmarks,
    required this.downloadRunner,
    this.appearance,
    this.userscriptManager,
    this.desktopModePrefs,
    this.webEnhance,
  });

  List<TabModel> get tabs => List.unmodifiable(_tabs);

  List<TabGroup> get groups => List.unmodifiable(_groups);

  TabModel? get active =>
      (_activeIndex >= 0 && _activeIndex < _tabs.length)
          ? _tabs[_activeIndex]
          : null;

  /// 是否可以恢复关闭的标签页
  bool get canReopenClosedTab => _closedTabs.isNotEmpty;

  /// 最近关闭的标签页标题（用于菜单提示）
  String? get lastClosedTitle =>
      _closedTabs.isEmpty ? null : _closedTabs.last.title;

  TabModel? byTabId(String id) {
    for (final t in _tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  TabGroup? groupById(String? id) {
    if (id == null) return null;
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// 当前选中的内核描述（供工具栏展示）
  KernelDescriptor get effectiveKernel =>
      kernelRegistry.effectiveDescriptor();

  // —— 标签组 ——

  TabGroup createGroup({String? name}) {
    _groupSeq++;
    final group = TabGroup(
      id: 'g${DateTime.now().microsecondsSinceEpoch}_$_groupSeq',
      name: name ?? '标签组 $_groupSeq',
      colorIndex: _groupSeq % 8,
    );
    _groups.add(group);
    notifyListeners();
    return group;
  }

  void renameGroup(String groupId, String name) {
    final g = groupById(groupId);
    if (g == null) return;
    g.name = name.trim().isEmpty ? g.name : name.trim();
    notifyListeners();
  }

  void setGroupColor(String groupId, int colorIndex) {
    final g = groupById(groupId);
    if (g == null) return;
    g.colorIndex = colorIndex;
    notifyListeners();
  }

  void toggleGroupCollapsed(String groupId) {
    final g = groupById(groupId);
    if (g == null) return;
    g.collapsed = !g.collapsed;
    notifyListeners();
  }

  /// 解散标签组（组内标签保留，仅解除归属）
  void removeGroup(String groupId) {
    _groups.removeWhere((g) => g.id == groupId);
    for (final t in _tabs) {
      if (t.groupId.value == groupId) t.groupId.value = null;
    }
    notifyListeners();
  }

  void assignGroup(String tabId, String? groupId) {
    final tab = byTabId(tabId);
    if (tab == null) return;
    tab.groupId.value = groupId;
    notifyListeners();
  }

  // —— 标签生命周期 ——

  /// 新建标签页并加载 [url]（为 null 时加载主页）
  Future<TabModel> createTab({String? url, bool private = false}) async {
    final tabId =
        'tab_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final kernel = kernelRegistry.createKernel(tabId);
    final tab = TabModel(id: tabId, kernel: kernel, isPrivate: private);

    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    notifyListeners();

    try {
      await _initialize(tab, url ?? config.homePage);
    } catch (e, st) {
      debugPrint('内核初始化失败：$e\n$st');
    }
    return tab;
  }

  Future<void> _initialize(TabModel tab, String address) async {
    final pluginScripts = pluginManager.collectUserScripts();
    final userScripts = userscriptManager?.collectScripts() ?? const [];
    final scripts = [...pluginScripts, ...userScripts];
    final granted = pluginManager.grantedBridgeMethods();

    await tab.kernel.initialize(KernelViewConfig(
      tabId: tab.id,
      userScripts: scripts,
      allowedBridgeMethods: granted,
    ));

    tab.kernel.bridge.registerAll(hostApi.handlers());
    _wireStreams(tab);

    // 应用桌面模式（UA / 视口 / DPR）
    final dm = desktopModePrefs?.config;
    if (dm != null && dm.enabled) {
      try {
        await tab.kernel.setDesktopMode(dm);
        tab.desktopMode.value = true;
      } catch (e) {
        debugPrint('应用桌面模式失败：$e');
      }
    }

    final start = UrlInput.resolve(
      address,
      searchEngineTemplate: config.searchEngine,
      homeDataUri: homeDataUri(),
    );
    await tab.kernel.loadUrl(start);
  }

  /// 生成全新的内置新标签页地址（含快捷方式与最近访问快照）
  String homeDataUri() => HomePage.dataUri(
        config.searchEngine,
        bookmarks: bookmarks.items,
        recent: history.entries,
        shortcutCount: config.homeShortcutCount,
        showRecent: config.homeShowRecent,
        bgColor: appearance?.homeBgColor,
        bgImage: appearance?.homeBgImage,
        accentColor: appearance?.accentColor ?? appearance?.seedColor,
      );

  void _wireStreams(TabModel tab) {
    tab.kernel.urlChanges.listen((u) => tab.url.value = u);
    tab.kernel.titleChanges.listen((t) {
      if (t.isNotEmpty) tab.title.value = t;
    });
    tab.kernel.progress.listen((p) {
      tab.progress.value = p;
      tab.isLoading.value = p > 0 && p < 1;
    });
    tab.kernel.navigationEvents.listen((event) async {
      if (event.stage == NavigationStage.finished) {
        tab.isLoading.value = false;
        tab.canGoBack.value = await tab.kernel.canGoBack();
        tab.canGoForward.value = await tab.kernel.canGoForward();
        // 隐私标签不写入历史
        if (!tab.isPrivate) {
          history.recordVisit(tab.url.value, tab.title.value);
        }
        // 应用网页增强（阅读/滤镜/无图/字号）
        await webEnhance?.applyTo(tab.kernel);
        // 通知工具栏刷新前进/后退可用状态
        notifyListeners();
      }
      if (event.stage == NavigationStage.start) {
        tab.isLoading.value = true;
        notifyListeners();
      }
    });
    tab.kernel.resourceErrors.listen((_) => tab.isLoading.value = false);
    // 下载接管
    tab.kernel.downloadRequests.listen(downloadRunner.start);
    // 用户脚本检测：转发给 UI 提示安装
    tab.kernel.userscriptDetected.listen((url) {
      _userscriptRequestCtrl.add(url);
    });
  }

  /// 从 URL 下载并安装用户脚本
  Future<bool> installUserscriptFromUrl(String url) async {
    final manager = userscriptManager;
    if (manager == null) return false;
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode >= 400) return false;
      final source = utf8.decode(resp.bodyBytes);
      final segs = Uri.parse(url).pathSegments;
      final filename = segs.isEmpty ? null : segs.last;
      final installed =
          manager.importFromSource(source, filename: filename);
      notifyListeners();
      return installed != null;
    } catch (e) {
      debugPrint('安装用户脚本失败：$e');
      return false;
    }
  }

  /// 切换桌面版 / 移动版网站
  Future<void> toggleDesktopMode(TabModel tab) async {
    final next = !tab.desktopMode.value;
    tab.desktopMode.value = next;
    final cfg = desktopModePrefs?.config;
    if (cfg != null) {
      await tab.kernel.setDesktopMode(cfg.copyWith(enabled: next));
    } else {
      await tab.kernel.setUserAgent(
          next ? BrowserConstants.desktopUserAgent : null);
    }
    await tab.kernel.reload();
    notifyListeners();
  }

  /// 清除浏览数据
  Future<void> clearBrowsingData({
    bool cookies = true,
    bool cache = true,
    bool historyFlag = true,
  }) async {
    if (historyFlag) history.clear();
    for (final tab in _tabs) {
      if (cookies) await tab.kernel.clearCookies();
      if (cache) await tab.kernel.clearCache();
    }
  }

  Future<void> closeTab(String id) async {
    final idx = _tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final removed = _tabs.removeAt(idx);

    // 记录到「最近关闭」，供恢复
    _closedTabs.add(_ClosedTab(
      url: removed.url.value,
      title: removed.title.value,
      groupId: removed.groupId.value,
    ));
    if (_closedTabs.length > _maxClosedStack) {
      _closedTabs.removeAt(0);
    }

    await removed.close();

    if (_tabs.isEmpty) {
      _activeIndex = -1;
      notifyListeners();
      await createTab();
      return;
    }

    if (idx <= _activeIndex) {
      _activeIndex = math.max(0, _activeIndex - 1);
    }
    if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    notifyListeners();
  }

  /// 恢复最近关闭的标签页
  Future<TabModel?> reopenClosedTab() async {
    if (_closedTabs.isEmpty) return null;
    final last = _closedTabs.removeLast();
    final url = last.url.startsWith('about:') ? null : last.url;
    final tab = await createTab(url: url);
    if (last.groupId != null &&
        _groups.any((g) => g.id == last.groupId)) {
      tab.groupId.value = last.groupId;
    }
    notifyListeners();
    return tab;
  }

  void activate(String id) {
    final idx = _tabs.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      _activeIndex = idx;
      notifyListeners();
    }
  }

  /// 拖拽排序
  void moveTab(int from, int to) {
    if (from < 0 || from >= _tabs.length) return;
    if (to < 0 || to >= _tabs.length) return;
    if (from == to) return;
    final activeTab = active;
    final tab = _tabs.removeAt(from);
    _tabs.insert(to, tab);
    if (activeTab != null) {
      final newIndex = _tabs.indexOf(activeTab);
      if (newIndex >= 0) _activeIndex = newIndex;
    }
    notifyListeners();
  }

  /// 在当前活动标签执行地址导航
  Future<void> navigateActive(String input) async {
    final tab = active;
    if (tab == null) return;
    final resolved = UrlInput.resolve(
      input,
      searchEngineTemplate: config.searchEngine,
      homeDataUri: homeDataUri(),
    );
    await tab.kernel.loadUrl(resolved);
  }

  @override
  void dispose() {
    _userscriptRequestCtrl.close();
    _notificationCtrl.close();
    super.dispose();
  }
}
