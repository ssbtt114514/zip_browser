import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../services/ad_blocker_service.dart';
import '../../services/bookmarks_service.dart';
import '../../services/config_service.dart';
import '../../services/desktop_mode_config.dart';
import '../../services/download_runner.dart';
import '../../services/history_service.dart';
import '../../services/host_bridge_api.dart';
import '../../services/session_service.dart';
import '../../services/web_enhance_service.dart';
import '../../services/zoom_service.dart';
import '../constants.dart';
import '../kernel/kernel_registry.dart';
import '../kernel/kernel_types.dart';
import '../plugin/plugin_manager.dart';
import '../sniff/sniff_model.dart';
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
  final bool pinned;
  const _ClosedTab({
    required this.url,
    required this.title,
    this.groupId,
    this.pinned = false,
  });
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
  final ZoomService? zoomService;
  final SessionService? sessionService;
  final AdBlockerService? adBlocker;
  late final HostBridgeApi hostApi;

  final List<TabModel> _tabs = [];
  final List<TabGroup> _groups = [];
  final List<_ClosedTab> _closedTabs = [];
  int _activeIndex = -1;
  int _seq = 0;
  int _groupSeq = 0;

  /// 会话快照写入的防抖计时器
  Timer? _sessionTimer;

  /// 恢复关闭标签页的栈上限
  static const int _maxClosedStack = 25;

  /// 检测到可安装的用户脚本链接（供 UI 提示安装）
  final _userscriptRequestCtrl = StreamController<String>.broadcast();
  Stream<String> get userscriptInstallRequests => _userscriptRequestCtrl.stream;

  /// 扩展通过 bridge 触发的通知（供 UI 以 SnackBar 呈现）
  final _notificationCtrl = StreamController<String>.broadcast();
  Stream<String> get extensionNotifications => _notificationCtrl.stream;

  /// 自动嗅探发现媒体后的提示横幅
  final _sniffHintCtrl = StreamController<SniffHint>.broadcast();
  Stream<SniffHint> get sniffHints => _sniffHintCtrl.stream;

  /// 每个标签累积的嗅探资源（url 去重）
  final Map<String, Map<String, SniffedResource>> _sniffAcc = {};

  /// 每个标签本次导航是否已发过提示
  final Map<String, bool> _sniffHinted = {};

  /// 供 host bridge 推送扩展通知
  void notifyExtension(String message) => _notificationCtrl.add(message);

  /// 标签数量达到上限时的提示
  void _notifyTabLimitReached(int maxTabs) {
    notifyExtension('已达标签页上限（$maxTabs），请先关闭部分标签');
  }

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
    this.zoomService,
    this.sessionService,
    this.adBlocker,
  }) {
    // 配置变化（如 JS 开关、风格）时实时同步到所有标签内核
    config.addListener(_applyConfigToKernels);
    // 缩放设置变化时立即作用于当前页
    zoomService?.addListener(_applyZoomToAllTabs);
  }

  void _applyConfigToKernels() {
    for (final t in _tabs) {
      t.kernel.setJavaScriptEnabled(config.jsEnabled);
    }
  }

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

  /// 固定标签（始终排在最前）
  List<TabModel> get pinnedTabs =>
      _tabs.where((t) => t.isPinned.value).toList(growable: false);

  /// 未固定标签
  List<TabModel> get normalTabs =>
      _tabs.where((t) => !t.isPinned.value).toList(growable: false);

  /// 标签总数
  int get tabCount => _tabs.length;

  /// 活动标签下标
  int get activeIndex => _activeIndex;

  // —— 标签固定 ——

  /// 固定 / 取消固定标签；固定标签会被移到最前
  void togglePin(String tabId) {
    final tab = byTabId(tabId);
    if (tab == null) return;
    tab.isPinned.value = !tab.isPinned.value;
    _normalizeOrder();
    notifyListeners();
  }

  /// 保证「固定标签在前」，并修正活动下标
  void _normalizeOrder() {
    final activeTab = active;
    final pinned = _tabs.where((t) => t.isPinned.value).toList();
    final normal = _tabs.where((t) => !t.isPinned.value).toList();
    _tabs
      ..clear()
      ..addAll(pinned)
      ..addAll(normal);
    if (activeTab != null) {
      final idx = _tabs.indexOf(activeTab);
      if (idx >= 0) _activeIndex = idx;
    }
    if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
  }

  /// 把 [tabId] 移到最前（供「移到最左」使用）
  void moveToFront(String tabId) {
    final idx = _tabs.indexWhere((t) => t.id == tabId);
    if (idx <= 0) return;
    final activeTab = active;
    final tab = _tabs.removeAt(idx);
    _tabs.insert(0, tab);
    if (activeTab != null) {
      final i = _tabs.indexOf(activeTab);
      if (i >= 0) _activeIndex = i;
    }
    notifyListeners();
  }

  // —— 缩放 ——

  /// 某标签当前生效的缩放倍率
  double zoomFor(TabModel tab) {
    final svc = zoomService;
    if (svc == null) return tab.zoom.value;
    final url = tab.url.value;
    return svc.forUrl(url.startsWith('about:') || url.startsWith('data:')
        ? ''
        : url);
  }

  /// 把缩放脚本注入指定标签
  Future<void> applyZoom(TabModel tab) async {
    final z = zoomFor(tab);
    tab.zoom.value = z;
    try {
      await tab.kernel.evaluateJavascript(ZoomService.scriptFor(z));
    } catch (e) {
      debugPrint('应用缩放失败：$e');
    }
  }

  void _applyZoomToAllTabs() {
    for (final t in _tabs) {
      applyZoom(t);
    }
    notifyListeners();
  }

  /// 设置当前标签缩放（按站点记忆）
  Future<void> setZoom(double value) async {
    final tab = active;
    if (tab == null) return;
    await zoomService?.setForUrl(tab.url.value, value);
    tab.zoom.value = value;
    await applyZoom(tab);
    notifyListeners();
  }

  Future<void> zoomIn() async {
    final tab = active;
    if (tab == null) return;
    final cur = zoomFor(tab);
    await setZoom(zoomService?.stepUp(cur) ?? (cur + 0.1));
  }

  Future<void> zoomOut() async {
    final tab = active;
    if (tab == null) return;
    final cur = zoomFor(tab);
    await setZoom(zoomService?.stepDown(cur) ?? (cur - 0.1));
  }

  Future<void> resetZoom() async {
    final tab = active;
    if (tab == null) return;
    await setZoom(1.0);
  }

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
  /// [pinned] 固定标签；[activate] 是否切换过去（恢复会话时可设 false）。
  Future<TabModel> createTab({
    String? url,
    bool private = false,
    bool pinned = false,
    bool activate = true,
  }) async {
    // 标签上限保护：移动端每个标签持有一个 WebView，防止低端机内存爆掉
    const maxTabs = 32;
    if (_tabs.length >= maxTabs) {
      _notifyTabLimitReached(maxTabs);
      final existing = _tabs.last;
      if (activate) {
        _activeIndex = _tabs.length - 1;
        notifyListeners();
      }
      return existing;
    }
    final tabId =
        'tab_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final kernel = kernelRegistry.createKernel(tabId);
    final tab = TabModel(id: tabId, kernel: kernel, isPrivate: private);
    tab.isPinned.value = pinned;

    final previous = active;
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _normalizeOrder();
    if (!activate && previous != null) {
      final idx = _tabs.indexOf(previous);
      if (idx >= 0) _activeIndex = idx;
    }
    notifyListeners();

    try {
      await _initialize(tab, url ?? config.homePage);
    } catch (e, st) {
      debugPrint('内核初始化失败：$e\n$st');
    }
    _scheduleSessionSave();
    return tab;
  }

  Future<void> _initialize(TabModel tab, String address) async {
    final pluginScripts = pluginManager.collectUserScripts();
    final userScripts = userscriptManager?.collectScripts() ?? const [];
    var scripts = [...pluginScripts, ...userScripts];
    // 广告拦截（内置脚本，最先注入以便 hook 早于页面脚本）
    if (config.adBlockEnabled) {
      scripts = [adBlocker?.buildUserScript(), ...scripts].whereType<UserScript>().toList();
    }
    final granted = pluginManager.grantedBridgeMethods();

    await tab.kernel.initialize(KernelViewConfig(
      tabId: tab.id,
      userScripts: scripts,
      allowedBridgeMethods: granted,
    ));

    tab.kernel.bridge.registerAll(hostApi.handlers());
    // 应用当前 JS 开关
    await tab.kernel.setJavaScriptEnabled(config.jsEnabled);
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
  String homeDataUri() {
    // 与宿主主题保持一致：跟随系统时读取平台亮度
    final mode = appearance?.themeMode ?? ThemeModeOption.system;
    final dark = mode == ThemeModeOption.dark ||
        (mode == ThemeModeOption.system &&
            ui.PlatformDispatcher.instance.platformBrightness ==
                ui.Brightness.dark);

    return HomePage.dataUri(
      config.searchEngine,
      bookmarks: bookmarks.items,
      recent: history.entries,
      shortcutCount: config.homeShortcutCount,
      showRecent: config.homeShowRecent,
      bgColor: appearance?.homeBgColor,
      bgImage: appearance?.homeBgImage,
      accentColor: appearance?.accentColor ?? appearance?.seedColor,
      dark: dark,
    );
  }

  void _wireStreams(TabModel tab) {
    tab.kernel.urlChanges.listen((u) {
      tab.url.value = u;
      _scheduleSessionSave();
    });
    tab.kernel.titleChanges.listen((t) {
      if (t.isNotEmpty) {
        tab.title.value = t;
        _scheduleSessionSave();
      }
    });
    tab.kernel.progress.listen((p) {
      tab.progress.value = p;
      tab.isLoading.value = p > 0 && p < 1;
    });
    tab.kernel.navigationEvents.listen((event) async {
      if (event.stage == NavigationStage.finished) {
        tab.isLoading.value = false;
        // 并行查询前进/后退能力，避免串行平台调用拖慢导航完成
        final results = await Future.wait([
          tab.kernel.canGoBack(),
          tab.kernel.canGoForward(),
        ]);
        tab.canGoBack.value = results[0];
        tab.canGoForward.value = results[1];
        // 隐私标签不写入历史
        if (!tab.isPrivate) {
          history.recordVisit(tab.url.value, tab.title.value);
        }
        // 应用网页增强（阅读/滤镜/无图/字号）与站点缩放，互不依赖并行执行
        await Future.wait([
          webEnhance?.applyTo(tab.kernel) ?? Future.value(),
          applyZoom(tab),
        ]);
        // 自动资源嗅探：稍等资源上报后汇总，发现媒体则提示
        if (config.autoSniff) _scheduleSniffHint(tab);
        _scheduleSessionSave();
        // 通知工具栏刷新前进/后退可用状态
        notifyListeners();
      }
      if (event.stage == NavigationStage.start) {
        tab.isLoading.value = true;
        // 新一次导航：重置嗅探累积与提示标记
        _sniffAcc[tab.id] = {};
        _sniffHinted[tab.id] = false;
        notifyListeners();
      }
    });
    // 资源嗅探：累积当前标签发现的资源（url 去重）
    tab.kernel.sniffedResources.listen((list) {
      final acc = _sniffAcc.putIfAbsent(tab.id, () => {});
      for (final r in list) {
        acc.putIfAbsent(r.url, () => r);
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

  /// 页面加载完成后延迟汇总嗅探结果，发现视频/音频则发出提示横幅
  void _scheduleSniffHint(TabModel tab) {
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!_tabs.contains(tab)) return;
      if (_sniffHinted[tab.id] == true) return;
      final acc = _sniffAcc[tab.id] ?? const <String, SniffedResource>{};
      final videos = acc.values.where((r) => r.type == SniffType.video).length;
      final audios = acc.values.where((r) => r.type == SniffType.audio).length;
      if (videos + audios > 0) {
        _sniffHinted[tab.id] = true;
        _sniffHintCtrl.add(SniffHint(videoCount: videos, audioCount: audios));
      }
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
    _sniffAcc.remove(id);
    _sniffHinted.remove(id);

    // 记录到「最近关闭」，供恢复
    _closedTabs.add(_ClosedTab(
      url: removed.url.value,
      title: removed.title.value,
      groupId: removed.groupId.value,
      pinned: removed.isPinned.value,
    ));
    if (_closedTabs.length > _maxClosedStack) {
      _closedTabs.removeAt(0);
    }

    await removed.close();

    if (_tabs.isEmpty) {
      _activeIndex = -1;
      notifyListeners();
      await createTab();
      _scheduleSessionSave();
      return;
    }

    if (idx <= _activeIndex) {
      _activeIndex = math.max(0, _activeIndex - 1);
    }
    if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    notifyListeners();
    _scheduleSessionSave();
  }

  /// 复制标签页（同地址新标签，紧邻原标签之后）
  Future<TabModel?> duplicateTab(String id) async {
    final src = byTabId(id);
    if (src == null) return null;
    final url = src.url.value;
    final srcIdx = _tabs.indexOf(src);
    final tab = await createTab(
      url: url.startsWith('about:') ? null : url,
      private: src.isPrivate,
    );
    // 放到原标签后面
    final curIdx = _tabs.indexOf(tab);
    if (srcIdx >= 0 && curIdx >= 0 && curIdx != srcIdx + 1) {
      _tabs.removeAt(curIdx);
      _tabs.insert(math.min(srcIdx + 1, _tabs.length), tab);
      _normalizeOrder();
      _activeIndex = _tabs.indexOf(tab);
    }
    notifyListeners();
    return tab;
  }

  /// 关闭除 [id] 外的所有标签
  Future<void> closeOtherTabs(String id) async {
    for (final t in _tabs.where((t) => t.id != id).toList()) {
      await closeTab(t.id);
    }
  }

  /// 关闭 [id] 右侧的所有标签
  Future<void> closeTabsToRight(String id) async {
    final idx = _tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    for (final t in _tabs.skip(idx + 1).toList()) {
      await closeTab(t.id);
    }
  }

  /// 关闭全部标签（随后自动新建一个空白标签）
  Future<void> closeAllTabs() async {
    for (final t in _tabs.toList()) {
      await closeTab(t.id);
    }
  }

  /// 在 [id] 右侧新建标签
  Future<TabModel?> newTabToRight(String id, {String? url}) async {
    final ref = byTabId(id);
    if (ref == null) return createTab(url: url);
    final refIdx = _tabs.indexOf(ref);
    final tab = await createTab(url: url);
    final curIdx = _tabs.indexOf(tab);
    if (refIdx >= 0 && curIdx >= 0 && curIdx != refIdx + 1) {
      _tabs.removeAt(curIdx);
      _tabs.insert(math.min(refIdx + 1, _tabs.length), tab);
      _normalizeOrder();
      _activeIndex = _tabs.indexOf(tab);
    }
    notifyListeners();
    return tab;
  }

  /// 恢复最近关闭的标签页
  Future<TabModel?> reopenClosedTab() async {
    if (_closedTabs.isEmpty) return null;
    final last = _closedTabs.removeLast();
    final url = last.url.startsWith('about:') ? null : last.url;
    final tab = await createTab(url: url, pinned: last.pinned);
    if (last.groupId != null &&
        _groups.any((g) => g.id == last.groupId)) {
      tab.groupId.value = last.groupId;
    }
    notifyListeners();
    return tab;
  }

  /// 切换到下一个 / 上一个标签（Ctrl+Tab 用）
  void activateNext() {
    if (_tabs.length < 2) return;
    _activeIndex = (_activeIndex + 1) % _tabs.length;
    notifyListeners();
  }

  void activatePrevious() {
    if (_tabs.length < 2) return;
    _activeIndex = (_activeIndex - 1 + _tabs.length) % _tabs.length;
    notifyListeners();
  }

  /// 按序号切换标签（1 起）
  void activateAt(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  // —— 会话 ——

  /// 当前会话快照（跳过隐私标签）
  List<SessionTab> sessionSnapshot() {
    return _tabs
        .where((t) => !t.isPrivate)
        .map((t) => SessionTab(
              url: t.url.value,
              title: t.title.value,
              pinned: t.isPinned.value,
              groupId: t.groupId.value,
            ))
        .toList();
  }

  /// 恢复上次会话（清空当前标签后重建）
  Future<void> restoreLastSession() async {
    final service = sessionService;
    if (service == null) return;
    final snapshot = service.readSnapshot();
    if (snapshot.isEmpty) return;

    for (final t in _tabs.toList()) {
      await closeTab(t.id);
    }

    var first = true;
    for (final s in snapshot) {
      final url = s.url.startsWith('about:') ? null : s.url;
      final tab = await createTab(
        url: url,
        pinned: s.pinned,
        activate: first,
      );
      first = false;
      if (!s.pinned && s.groupId != null &&
          _groups.any((g) => g.id == s.groupId)) {
        tab.groupId.value = s.groupId;
      }
    }
    notifyListeners();
  }

  /// 防抖写入会话快照
  void _scheduleSessionSave() {
    final service = sessionService;
    if (service == null) return;
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(milliseconds: 1200), () {
      service.saveSnapshot(sessionSnapshot());
    });
  }

  /// 立即写入会话快照（退出前调用）
  Future<void> flushSession() async {
    _sessionTimer?.cancel();
    await sessionService?.saveSnapshot(sessionSnapshot());
  }

  void activate(String id) {
    final idx = _tabs.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      _activeIndex = idx;
      notifyListeners();
    }
  }

  /// 拖拽排序。
  ///
  /// 与主流浏览器一致：拖入固定区自动固定、拖出固定区自动取消固定。
  void moveTab(int from, int to) {
    if (from < 0 || from >= _tabs.length) return;
    if (to < 0 || to >= _tabs.length) return;
    if (from == to) return;
    final activeTab = active;
    final pinnedCount = _tabs.where((t) => t.isPinned.value).length;
    final tab = _tabs.removeAt(from);
    _tabs.insert(to, tab);
    final shouldPin = to < pinnedCount;
    if (tab.isPinned.value != shouldPin) {
      tab.isPinned.value = shouldPin;
    }
    if (activeTab != null) {
      final newIndex = _tabs.indexOf(activeTab);
      if (newIndex >= 0) _activeIndex = newIndex;
    }
    _scheduleSessionSave();
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
    _sessionTimer?.cancel();
    config.removeListener(_applyConfigToKernels);
    zoomService?.removeListener(_applyZoomToAllTabs);
    _userscriptRequestCtrl.close();
    _notificationCtrl.close();
    _sniffHintCtrl.close();
    super.dispose();
  }
}
