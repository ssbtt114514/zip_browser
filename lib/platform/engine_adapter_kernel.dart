import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/bridge/js_bridge.dart';
import '../core/desktop_mode_config.dart';
import '../core/kernel/browser_kernel.dart';
import '../core/kernel/kernel_source.dart';
import '../core/kernel/kernel_types.dart';
import '../core/sniff/sniff_model.dart';

/// 候选路径的命中方式
enum EngineRuntimeSource {
  /// 已知安装路径（内置候选清单）
  knownPath,

  /// MOZ* / MOZILLA* 环境变量指向的路径
  environment,

  /// PATH 上的浏览器可执行文件
  pathExecutable,

  /// 未命中
  none;

  String get label {
    switch (this) {
      case EngineRuntimeSource.knownPath:
        return '已知安装路径';
      case EngineRuntimeSource.environment:
        return '环境变量';
      case EngineRuntimeSource.pathExecutable:
        return 'PATH 可执行文件';
      case EngineRuntimeSource.none:
        return '未命中';
    }
  }
}

/// 候选路径的性质
enum EngineRuntimeCandidateKind {
  /// 引擎运行时库：命中即"发现运行时"
  library,

  /// 安装痕迹（浏览器可执行文件 / 安装目录）：只是线索，不能证明可加载
  clue;

  String get label {
    switch (this) {
      case EngineRuntimeCandidateKind.library:
        return '运行时库';
      case EngineRuntimeCandidateKind.clue:
        return '安装痕迹';
    }
  }
}

/// 一条被探测的候选路径
class EngineRuntimeCandidate {
  final String path;
  final EngineRuntimeSource source;
  final EngineRuntimeCandidateKind kind;

  /// 中文备注（为什么会有这条候选）
  final String note;

  /// 本次探测是否命中
  final bool hit;

  const EngineRuntimeCandidate({
    required this.path,
    required this.source,
    required this.kind,
    required this.note,
    this.hit = false,
  });

  bool get isLibrary => kind == EngineRuntimeCandidateKind.library;

  EngineRuntimeCandidate withHit(bool value) => EngineRuntimeCandidate(
        path: path,
        source: source,
        kind: kind,
        note: note,
        hit: value,
      );
}

/// 从 Gecko 运行时同目录的 platform.ini / application.ini 读到的版本信息
///
/// 读不到时整体为 null；**绝不编造版本号**。
class EngineRuntimeVersion {
  /// Milestone（platform.ini）或 Version（application.ini）
  final String? milestone;

  /// BuildID
  final String? buildId;

  const EngineRuntimeVersion({this.milestone, this.buildId});

  String get label {
    final parts = <String>[];
    if (milestone != null) parts.add('版本 $milestone');
    if (buildId != null) parts.add('BuildID $buildId');
    return parts.join(' · ');
  }

  bool get isEmpty => milestone == null && buildId == null;
}

/// 一次探测的完整结果（供 UI 与测试使用）
class EngineRuntimeProbe {
  final String engineId;
  final String platform;

  /// 是否发现运行时库（`xul.dll` / `libxul.so` 等）
  final bool found;

  /// 命中的运行时库路径
  final String? path;

  /// 命中方式
  final EngineRuntimeSource source;

  /// 运行时版本（读不到为 null）
  final String? version;
  final String? buildId;

  /// 全部候选路径（含未命中项，UI 如实展示）
  final List<EngineRuntimeCandidate> candidates;

  /// 探测时间
  final DateTime checkedAt;

  const EngineRuntimeProbe({
    required this.engineId,
    required this.platform,
    required this.found,
    required this.candidates,
    required this.checkedAt,
    this.path,
    this.source = EngineRuntimeSource.none,
    this.version,
    this.buildId,
  });

  /// 命中的候选（库与线索）
  List<EngineRuntimeCandidate> get hits =>
      candidates.where((c) => c.hit).toList();

  /// 命中的安装痕迹（不能证明可加载）
  List<EngineRuntimeCandidate> get clues =>
      candidates.where((c) => c.hit && !c.isLibrary).toList();

  /// 有安装痕迹但没有确认运行时
  bool get hasClueOnly => !found && clues.isNotEmpty;

  /// 一句话结论（UI 与测试共用，措辞即对外承诺）
  String get summary {
    if (found) {
      return '发现 Gecko 运行时文件：$path（仅探测报告，本适配包不会加载它）';
    }
    if (hasClueOnly) {
      return '发现 Gecko 安装痕迹（${clues.length} 条），但未确认可加载的运行时库';
    }
    return '未检测到 Gecko 运行时（已检查 ${candidates.length} 条候选路径）';
  }
}

/// Gecko（及同类浏览器引擎）运行时探测器
///
/// 纯 Dart 实现，**所有探测动作都可注入**（文件存在探测、文本读取、环境变量、
/// 平台字符串），因此单元测试完全不依赖本机真实环境：
///
/// ```dart
/// final locator = EngineRuntimeLocator(
///   platform: 'linux',
///   exists: (p) => p == '/usr/lib/firefox/libxul.so',
///   environment: const {},
/// );
/// ```
///
/// 只注入 [exists] 而不注入 [readText] 时，版本解析会被自动关闭（返回 null），
/// 避免测试意外去读真实磁盘。
class EngineRuntimeLocator {
  /// 引擎标识（当前只有 gecko 有候选清单）
  final String engineId;

  /// 平台字符串：windows / linux / android / macos
  final String platform;

  final bool Function(String path) _exists;
  final String? Function(String path) _readText;
  final Map<String, String> _env;
  final bool _hermetic;

  EngineRuntimeLocator({
    String? engineId,
    String? platform,
    bool Function(String path)? exists,
    String? Function(String path)? readText,
    Map<String, String>? environment,
  })  : engineId = engineId ?? 'gecko',
        platform = platform ?? _currentPlatform(),
        _exists = exists ?? _defaultExists,
        _readText = readText ?? (exists != null ? _denyRead : _defaultReadText),
        _env = environment ?? Platform.environment,
        _hermetic = exists != null && readText == null;

  static bool _defaultExists(String path) {
    try {
      return File(path).existsSync() || Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String? _defaultReadText(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  static String? _denyRead(String path) => null;

  /// 是否处于"注入探测、不读真实磁盘"的模式（测试用）
  bool get isHermetic => _hermetic;

  static String _currentPlatform() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  /// 执行一次探测
  EngineRuntimeProbe detect() {
    final resolved = <EngineRuntimeCandidate>[];
    String? foundPath;
    var foundSource = EngineRuntimeSource.none;

    for (final c in candidates()) {
      final hit = _exists(c.path);
      resolved.add(c.withHit(hit));
      if (hit && foundPath == null && c.isLibrary) {
        foundPath = c.path;
        foundSource = c.source;
      }
    }

    final version = foundPath == null ? null : _readVersion(foundPath);

    return EngineRuntimeProbe(
      engineId: engineId,
      platform: platform,
      found: foundPath != null,
      path: foundPath,
      source: foundSource,
      version: version?.milestone,
      buildId: version?.buildId,
      candidates: resolved,
      checkedAt: DateTime.now(),
    );
  }

  /// 全部候选路径（按优先级排序，未探测命中情况）
  List<EngineRuntimeCandidate> candidates() {
    final out = <EngineRuntimeCandidate>[];

    for (final p in _knownLibraryPaths()) {
      out.add(EngineRuntimeCandidate(
        path: p,
        source: EngineRuntimeSource.knownPath,
        kind: EngineRuntimeCandidateKind.library,
        note: '内置候选：$_platformName 常见安装位置',
      ));
    }

    for (final p in _knownCluePaths()) {
      out.add(EngineRuntimeCandidate(
        path: p,
        source: EngineRuntimeSource.knownPath,
        kind: EngineRuntimeCandidateKind.clue,
        note: '内置候选：浏览器可执行文件 / 安装目录（仅线索）',
      ));
    }

    for (final e in _environmentCandidates()) {
      out.add(e);
    }

    for (final p in _pathExecutables()) {
      out.add(EngineRuntimeCandidate(
        path: p,
        source: EngineRuntimeSource.pathExecutable,
        kind: EngineRuntimeCandidateKind.clue,
        note: 'PATH 中的浏览器可执行文件（仅线索）',
      ));
    }

    return out;
  }

  String get _platformName {
    switch (platform) {
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      case 'android':
        return 'Android';
      case 'macos':
        return 'macOS';
      default:
        return platform;
    }
  }

  /// 本平台的运行时库文件名
  List<String> get _libraryFileNames {
    switch (platform) {
      case 'windows':
        return const ['xul.dll'];
      case 'linux':
        return const ['libxul.so'];
      case 'android':
        return const ['libxul.so', 'libgeckoview.so'];
      case 'macos':
        return const ['libxul.dylib'];
      default:
        return const [];
    }
  }

  /// 内置运行时库候选路径
  List<String> _knownLibraryPaths() {
    switch (platform) {
      case 'windows':
        final pf = _envLookup('ProgramFiles') ?? r'C:\Program Files';
        final pf86 = _envLookup('ProgramFiles(x86)') ?? r'C:\Program Files (x86)';
        final local = _envLookup('LOCALAPPDATA');
        return [
          _join(pf, r'Mozilla Firefox\xul.dll'),
          _join(pf86, r'Mozilla Firefox\xul.dll'),
          if (local != null) _join(local, r'Mozilla Firefox\xul.dll'),
          _join(pf, r'Mozilla Firefox ESR\xul.dll'),
        ];
      case 'linux':
        return const [
          '/usr/lib/firefox/libxul.so',
          '/usr/lib/firefox-esr/libxul.so',
          '/usr/lib64/firefox/libxul.so',
          '/opt/firefox/libxul.so',
          '/snap/firefox/current/usr/lib/firefox/libxul.so',
        ];
      case 'android':
        // GeckoView 通常位于应用私有目录（/data/app/<pkg>/lib/<abi>/），
        // 没有固定路径可枚举，这里只探测系统镜像里的已知位置。
        return const [
          '/system/lib64/libxul.so',
          '/system/lib/libxul.so',
          '/system/lib64/libgeckoview.so',
          '/system/lib/libgeckoview.so',
          '/product/lib64/libgeckoview.so',
          '/vendor/lib64/libgeckoview.so',
        ];
      case 'macos':
        return const [
          '/Applications/Firefox.app/Contents/MacOS/libxul.dylib',
        ];
      default:
        return const [];
    }
  }

  /// 内置安装痕迹候选（可执行文件 / 安装目录）
  List<String> _knownCluePaths() {
    switch (platform) {
      case 'windows':
        final pf = _envLookup('ProgramFiles') ?? r'C:\Program Files';
        final local = _envLookup('LOCALAPPDATA');
        return [
          _join(pf, r'Mozilla Firefox\firefox.exe'),
          if (local != null) _join(local, r'Mozilla Firefox\firefox.exe'),
        ];
      case 'linux':
        return const ['/usr/bin/firefox', '/usr/bin/firefox-esr'];
      case 'android':
        return const ['/system/bin/firefox'];
      case 'macos':
        return const ['/Applications/Firefox.app'];
      default:
        return const [];
    }
  }

  /// MOZ* / MOZILLA* 环境变量指向的候选
  List<EngineRuntimeCandidate> _environmentCandidates() {
    final out = <EngineRuntimeCandidate>[];
    final libNames = _libraryFileNames;
    for (final entry in _env.entries) {
      final key = entry.key.toUpperCase();
      if (!key.startsWith('MOZ')) continue;
      final value = entry.value.trim();
      if (value.isEmpty) continue;
      // 只认像路径的值（MOZ_ENABLE_WAYLAND=1 之类直接跳过）
      if (!value.contains('/') && !value.contains(r'\')) continue;

      final looksLikeLibrary =
          libNames.any((n) => value.toLowerCase().endsWith(n.toLowerCase()));
      if (looksLikeLibrary) {
        out.add(EngineRuntimeCandidate(
          path: value,
          source: EngineRuntimeSource.environment,
          kind: EngineRuntimeCandidateKind.library,
          note: '环境变量 $key（指向运行时库）',
        ));
        continue;
      }
      // 目录线索：在目录下找本平台的运行时库
      for (final n in libNames) {
        out.add(EngineRuntimeCandidate(
          path: _join(value, n),
          source: EngineRuntimeSource.environment,
          kind: EngineRuntimeCandidateKind.library,
          note: '环境变量 $key 指向的目录',
        ));
      }
    }
    return out;
  }

  /// PATH 上的浏览器可执行文件
  List<String> _pathExecutables() {
    final raw = _envLookup('PATH') ?? _envLookup('Path');
    if (raw == null || raw.isEmpty) return const [];
    final sep = platform == 'windows' ? ';' : ':';
    final names = platform == 'windows'
        ? const ['firefox.exe']
        : const ['firefox', 'firefox-esr'];
    final out = <String>[];
    for (final dir in raw.split(sep)) {
      final d = dir.trim();
      if (d.isEmpty) continue;
      for (final n in names) {
        out.add(_join(d, n));
      }
    }
    return out;
  }

  /// 读取运行时同目录的 platform.ini / application.ini，解析版本
  EngineRuntimeVersion? _readVersion(String libraryPath) {
    final dir = _dirName(libraryPath);
    if (dir.isEmpty) return null;
    for (final name in const ['platform.ini', 'application.ini']) {
      final text = _readText(_join(dir, name));
      if (text == null || text.trim().isEmpty) continue;
      final milestone =
          _iniValue(text, 'Milestone') ?? _iniValue(text, 'Version');
      final buildId = _iniValue(text, 'BuildID');
      if (milestone != null || buildId != null) {
        return EngineRuntimeVersion(milestone: milestone, buildId: buildId);
      }
    }
    return null;
  }

  static String? _iniValue(String text, String key) {
    for (var line in text.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      if (line.substring(0, eq).trim() != key) continue;
      final v = line.substring(eq + 1).trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// 本平台"怎样才能被检测到"的可照做提示
  String get installHint {
    switch (platform) {
      case 'windows':
        return '安装 Mozilla 官方 Firefox（或 Firefox ESR）后，检测器会在 '
            r'%ProgramFiles%\Mozilla Firefox\xul.dll'
            ' 等位置找到 Gecko 运行时；即使找到，本适配包也不会加载它。';
      case 'linux':
        return '安装发行版提供的 firefox / firefox-esr 后，检测器会检查 '
            '/usr/lib/firefox/libxul.so、/opt/firefox/libxul.so 等路径；'
            '即使找到，本适配包也不会加载它。';
      case 'android':
        return 'Android 上的 GeckoView 位于应用私有目录'
            '（/data/app/<包名>/lib/<abi>/libgeckoview.so），无法用固定路径探测；'
            '要真正使用 Gecko，需要宿主 APK 自行集成 GeckoView（AAR）。';
      case 'macos':
        return '安装 Firefox 后，检测器会检查 '
            '/Applications/Firefox.app/Contents/MacOS/libxul.dylib；'
            '即使找到，本适配包也不会加载它。';
      default:
        return '当前平台没有内置的 Gecko 候选路径。';
    }
  }

  String? _envLookup(String name) {
    for (final e in _env.entries) {
      if (e.key.toUpperCase() == name.toUpperCase()) return e.value;
    }
    return null;
  }

  static String _join(String dir, String name) {
    if (dir.isEmpty) return name;
    final last = dir[dir.length - 1];
    if (last == '/' || last == r'\') return '$dir$name';
    final sep = dir.contains(r'\') && !dir.contains('/') ? r'\' : '/';
    return '$dir$sep$name';
  }

  static String _dirName(String path) {
    final i = path.lastIndexOf('/');
    final j = path.lastIndexOf(r'\');
    final cut = i > j ? i : j;
    if (cut <= 0) return '';
    return path.substring(0, cut);
  }
}

/// 引擎适配包内核：**如实报告"不能渲染"**，不做任何假装。
///
/// 它做三件事：
/// 1. 探测本机是否存在目标引擎（Gecko）的运行时文件，并把候选路径与命中情况
///    全部展示出来；
/// 2. 提供与其它内核一致的 [BrowserKernel] 接口，使「内核管理」可以选中它、
///    标签页可以正常创建；
/// 3. 在视图里明确说明为什么不渲染、以及要真正渲染需要什么。
///
/// 它**不做**的事：不加载 libxul / xul.dll，不渲染任何网页，不伪造加载成功。
/// [loadUrl] 只记录目标地址并发出 [NavigationStage.blocked]，
/// 因此标签页不会出现假的加载动画，也不会把没加载的地址写进历史。
class EngineAdapterKernel implements BrowserKernel {
  /// 对外承诺的统一文案（UI、文档、测试共用）
  static const String cannotRenderNotice =
      '本适配包只做引擎探测，不提供网页渲染：它不会加载 Gecko 运行时，也不会显示任何网页内容。';

  final KernelSource source;

  /// 引擎谱系（本适配包当前用于 gecko）
  final KernelEngine engine;

  /// 运行时探测器（可注入，便于测试）
  final EngineRuntimeLocator locator;

  late JsBridgeHub _bridge;

  late EngineRuntimeProbe _probe;
  String? _lastRequestedUrl;
  String? _lastDisplayedUrl;

  /// 是否有过一次"无法完成"的导航请求
  bool _blockedNavigation = false;

  /// 探测结果版本号：重新检测后自增，供 UI 刷新
  final ValueNotifier<int> probeRevision = ValueNotifier<int>(0);

  final _nav = StreamController<NavigationEvent>.broadcast();
  final _urlC = StreamController<String>.broadcast();

  EngineAdapterKernel({
    required this.source,
    EngineRuntimeLocator? locator,
    KernelEngine? engine,
  })  : engine = engine ?? KernelEngine.gecko,
        locator = locator ?? EngineRuntimeLocator() {
    _probe = this.locator.detect();
  }

  @override
  String get id => source.kernelId;

  @override
  String get displayName => source.displayName;

  @override
  KernelOrigin get origin => source.origin;

  /// 如实声明能力：适配包不提供网页加载、脚本执行等任何渲染能力
  @override
  Set<KernelCapability> get capabilities => const <KernelCapability>{};

  @override
  JsBridgeHub get bridge => _bridge;

  /// 最近一次探测结果
  EngineRuntimeProbe get probe => _probe;

  /// 最近一次 [loadUrl] 请求的地址（**不代表已加载**）
  String? get lastRequestedUrl => _lastRequestedUrl;

  /// 是否发生过被拒绝的导航（视图据此显示"未加载"提示）
  bool get hasBlockedNavigation => _blockedNavigation;

  /// 引擎运行时版本（读不到为 null，不编造）
  @override
  Future<String?> get version async => _probe.version;

  @override
  Future<void> initialize(KernelViewConfig config) async {
    _bridge = JsBridgeHub(
      globalName: config.bridgeGlobalName,
      allowedMethods: config.allowedBridgeMethods,
    );
    _probe = locator.detect();
    probeRevision.value = probeRevision.value + 1;
  }

  @override
  Widget buildView() => _EngineAdapterView(kernel: this);

  /// 重新探测本机引擎运行时
  void redetect() {
    _probe = locator.detect();
    probeRevision.value = probeRevision.value + 1;
  }

  @override
  Future<void> loadUrl(String url) async {
    _lastRequestedUrl = url;
    _blockedNavigation = true;
    // 只有 data: 首页等内置地址不进地址栏（它不是用户导航，且内容极长）；
    // 其余请求如实写入地址栏，但绝不发 start / finished —— 没有加载就是没有加载。
    if (!url.startsWith('data:')) {
      _lastDisplayedUrl = url;
      _urlC.add(url);
    }
    _nav.add(NavigationEvent(url, NavigationStage.blocked));
    probeRevision.value = probeRevision.value + 1;
  }

  @override
  Future<void> goBack() async {}
  @override
  Future<void> goForward() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> stopLoading() async {}

  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<bool> canGoForward() async => false;

  /// 没有页面上下文，任何脚本都不会被执行
  @override
  Future<String?> evaluateJavascript(String script) async => '';

  @override
  void registerBridgeHandler(String method, BridgeHandler handler) =>
      _bridge.register(method, handler);

  @override
  Future<void> setJavaScriptEnabled(bool enabled) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> setDesktopMode(DesktopModeConfig config) async {}

  /// 页面内查找：没有页面，如实返回 0
  @override
  Future<int> findStart(String query) async => 0;
  @override
  Future<void> findNext(bool forward) async {}
  @override
  Future<void> findClear() async {}

  @override
  Stream<ContextMenuInfo> get contextMenu => const Stream.empty();
  @override
  Stream<String> get downloadRequests => const Stream.empty();
  @override
  Stream<String> get userscriptDetected => const Stream.empty();
  @override
  Stream<List<String>> get userscriptList => const Stream.empty();
  @override
  Stream<List<SniffedResource>> get sniffedResources => const Stream.empty();
  @override
  Future<void> triggerSniff() async {}

  /// 没有会话，清理是无害 no-op
  @override
  Future<void> clearCookies() async {}
  @override
  Future<void> clearCache() async {}

  @override
  Stream<NavigationEvent> get navigationEvents => _nav.stream;
  @override
  Stream<double> get progress => const Stream.empty();
  @override
  Stream<String> get urlChanges => _urlC.stream;
  @override
  Stream<String> get titleChanges => const Stream.empty();
  @override
  Stream<WebResourceError> get resourceErrors => const Stream.empty();

  @override
  Future<String?> getCurrentTitle() async => null;

  /// 最近一次写入地址栏的地址；null 表示从未请求过可显示的地址
  @override
  Future<String?> getCurrentUrl() async => _lastDisplayedUrl;

  @override
  Future<void> dispose() async {
    await _nav.close();
    await _urlC.close();
    probeRevision.dispose();
  }
}

/// 引擎适配包视图：探测报告 + "不渲染"说明
class _EngineAdapterView extends StatelessWidget {
  final EngineAdapterKernel kernel;

  const _EngineAdapterView({required this.kernel});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: kernel.probeRevision,
      builder: (context, _, __) {
        final probe = kernel.probe;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            _header(probe),
            const SizedBox(height: 16),
            _noticeCard(context),
            const SizedBox(height: 16),
            _probeCard(context, probe),
            if (kernel.hasBlockedNavigation) ...[
              const SizedBox(height: 12),
              _requestCard(),
            ],
            const SizedBox(height: 20),
            _sectionTitle('为什么不渲染'),
            const SizedBox(height: 6),
            const Text(
              'Gecko 目前没有任何可供第三方"离屏嵌入渲染"的发行版：'
              'Mozilla 只发行 Firefox 应用与 GeckoView（Android 端编译进宿主 APK 的组件），'
              '它们都不提供"把渲染结果交给宿主 Flutter 视图"的接口。'
              '因此本适配包不会加载 xul.dll / libxul.so，也不会显示网页内容。',
              style: TextStyle(color: Colors.black54, height: 1.6),
            ),
            const SizedBox(height: 10),
            const Text(
              '如果检测结果显示"发现 Gecko 运行时文件"，那只能证明这台机器上存在 Gecko 文件，'
              '并不代表本应用可以调用它。',
              style: TextStyle(color: Colors.black54, height: 1.6),
            ),
            const SizedBox(height: 20),
            _sectionTitle('要真正渲染网页，需要什么'),
            const SizedBox(height: 6),
            const Text(
              '· 想现在就上网：在「内核管理」里切回系统内核（Windows WebView2 / '
              'Linux WebKitGTK / Android System WebView），或安装携带 FFI 原生库、'
              'WebView2 固定版本运行时的内核包。',
              style: TextStyle(color: Colors.black54, height: 1.6),
            ),
            const SizedBox(height: 6),
            const Text(
              '· 想在 Android 上真正用 Gecko：需要宿主 APK 集成 GeckoView（AAR），'
              '由宿主内核实现渲染；本适配包不包含 GeckoView。',
              style: TextStyle(color: Colors.black54, height: 1.6),
            ),
            const SizedBox(height: 6),
            const Text(
              '· 桌面端要出现"可嵌入的 Gecko"，需要 Mozilla 提供可离屏渲染的发行版；'
              '目前不存在这样的发行版。',
              style: TextStyle(color: Colors.black54, height: 1.6),
            ),
            const SizedBox(height: 20),
            _sectionTitle('本机检测提示'),
            const SizedBox(height: 6),
            Text(
              kernel.locator.installHint,
              style: const TextStyle(color: Colors.black54, height: 1.6),
            ),
            const SizedBox(height: 20),
            _sectionTitle(
              '候选路径（共 ${probe.candidates.length} 条，命中 ${probe.hits.length} 条）',
            ),
            const SizedBox(height: 8),
            for (final c in probe.candidates) _candidateRow(c),
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                onPressed: kernel.redetect,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新检测'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(EngineRuntimeProbe probe) {
    return Row(
      children: [
        Icon(
          kernel.engine == KernelEngine.gecko
              ? Icons.local_fire_department_outlined
              : Icons.extension_outlined,
          size: 40,
          color: Colors.blueGrey,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${kernel.engine.label} 引擎适配包',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${kernel.displayName} · ${probe.platform}',
                style: const TextStyle(color: Colors.black54, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _noticeCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '不提供网页渲染',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  EngineAdapterKernel.cannotRenderNotice,
                  style: TextStyle(
                    color: Colors.brown.shade700,
                    height: 1.5,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _probeCard(BuildContext context, EngineRuntimeProbe probe) {
    final found = probe.found;
    final color = found
        ? Colors.teal.shade700
        : (probe.hasClueOnly ? Colors.orange.shade800 : Colors.blueGrey);
    final icon = found
        ? Icons.check_circle_outline
        : (probe.hasClueOnly ? Icons.info_outline : Icons.search_off);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  probe.summary,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '探测内容：本机是否存在 Gecko 运行时文件（xul.dll / libxul.so 等）',
            style: TextStyle(color: Colors.black54, fontSize: 12.5),
          ),
          Text(
            '命中方式：${probe.source.label}',
            style: const TextStyle(color: Colors.black54, fontSize: 12.5),
          ),
          Text(
            '版本：${_versionLabel(probe)}',
            style: const TextStyle(color: Colors.black54, fontSize: 12.5),
          ),
          Text(
            '探测时间：${_formatTime(probe.checkedAt)} · 仅探测，不会加载',
            style: const TextStyle(color: Colors.black54, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _requestCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block, size: 18, color: Colors.red.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '最近一次请求地址（未加载）：${_shortUrl(kernel.lastRequestedUrl)}',
              style: TextStyle(
                color: Colors.red.shade900,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  Widget _candidateRow(EngineRuntimeCandidate c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            c.hit ? Icons.check_circle : Icons.remove_circle_outline,
            size: 14,
            color: c.hit
                ? (c.isLibrary ? Colors.teal : Colors.orange)
                : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.path,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.hit ? Colors.black87 : Colors.black45,
                  ),
                ),
                Text(
                  '${c.kind.label} · ${c.source.label}${c.hit ? ' · 命中' : ''} · ${c.note}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _versionLabel(EngineRuntimeProbe probe) {
    if (probe.version == null && probe.buildId == null) {
      return '未读取到（不编造版本号）';
    }
    final parts = <String>[];
    if (probe.version != null) parts.add('版本 ${probe.version}');
    if (probe.buildId != null) parts.add('BuildID ${probe.buildId}');
    return parts.join(' · ');
  }

  static String _shortUrl(String? url) {
    if (url == null || url.isEmpty) return '(未知)';
    if (url.startsWith('data:')) return '内置新标签页（data: 页面，未加载）';
    if (url.length <= 96) return url;
    return '${url.substring(0, 96)}…';
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
