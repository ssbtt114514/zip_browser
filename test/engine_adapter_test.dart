import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/core/kernel/kernel_manager.dart';
import 'package:zip_browser/core/kernel/kernel_manifest.dart';
import 'package:zip_browser/core/kernel/kernel_package.dart';
import 'package:zip_browser/core/kernel/kernel_registry.dart';
import 'package:zip_browser/core/kernel/kernel_types.dart';
import 'package:zip_browser/core/plugin/plugin_manager.dart';
import 'package:zip_browser/platform/engine_adapter_kernel.dart';
import 'package:zip_browser/platform/plugin_ffi_kernel.dart';
import 'package:zip_browser/services/config_service.dart';

/// 按 `tool/pack_kernel.py` 的规则（以源目录为 zip 根）在内存中打包，
/// 用于覆盖「真实内核包目录 → 安装」这条链路。
List<int> zipDir(String dir) {
  final src = Directory(dir);
  if (!src.existsSync()) {
    throw StateError('目录不存在：$dir');
  }
  final archive = Archive();
  final files = src
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .toList()
    ..sort();
  for (final path in files) {
    final name = p.relative(path, from: src.path).replaceAll(r'\', '/');
    final bytes = File(path).readAsBytesSync();
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) throw StateError('打包失败：$dir');
  return encoded;
}

/// 用内存里的 kernel.json 造一个内核包（用于校验规则测试）
List<int> zipManifest(Map<String, dynamic> manifest) {
  final archive = Archive();
  final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
  archive.addFile(ArchiveFile('kernel.json', bytes.length, bytes));
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) throw StateError('打包失败');
  return encoded;
}

/// 合法的 engine_adapter 清单（字段与 build_kernel_pkg/zb_gecko_kernel 一致）
Map<String, dynamic> adapterManifest({
  String type = 'engine_adapter',
  Map<String, dynamic>? libraries,
  String? runtimeDir,
}) {
  return <String, dynamic>{
    'manifest_version': 1,
    'id': 'com.zipbrowser.kernel.gecko',
    'name': 'Gecko 内核适配包',
    'display_name': 'Gecko 内核适配包（不提供网页渲染）',
    'version': '1.0.0',
    'engine': 'gecko',
    'type': type,
    'abi_version': 1,
    'description': '只探测本机 Gecko 运行时，不提供离屏渲染。',
    'capabilities': <String>[],
    if (libraries != null) 'libraries': libraries,
    if (runtimeDir != null) 'runtime_dir': runtimeDir,
  };
}

/// 只命中给定路径的注入式探测器（绝不读真实磁盘）
EngineRuntimeLocator locatorFor(
  String platform,
  Set<String> existing, {
  Map<String, String> environment = const {},
  String? Function(String path)? readText,
}) {
  return EngineRuntimeLocator(
    platform: platform,
    exists: existing.contains,
    readText: readText,
    environment: environment,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EngineRuntimeLocator · Windows', () {
    test('命中 %ProgramFiles%\\Mozilla Firefox\\xul.dll', () {
      const hit = r'C:\Program Files\Mozilla Firefox\xul.dll';
      final locator = locatorFor(
        'windows',
        {hit},
        environment: const {
          'ProgramFiles': r'C:\Program Files',
          'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
        },
      );

      final probe = locator.detect();
      expect(probe.found, isTrue);
      expect(probe.path, hit);
      expect(probe.source, EngineRuntimeSource.knownPath);
      expect(probe.hits.single.isLibrary, isTrue);
      expect(probe.summary, contains('发现 Gecko 运行时文件'));
      // 候选清单里必须包含 x86 与 LOCALAPPDATA 两条常见位置
      final paths = locator.candidates().map((c) => c.path).toList();
      expect(paths, contains(r'C:\Program Files (x86)\Mozilla Firefox\xul.dll'));
      expect(
        paths,
        contains(r'C:\Users\me\AppData\Local\Mozilla Firefox\xul.dll'),
      );
    });

    test('多候选命中时取优先级最高的一条', () {
      final locator = locatorFor(
        'windows',
        {r'C:\Program Files (x86)\Mozilla Firefox\xul.dll'},
        environment: const {
          'ProgramFiles': r'C:\Program Files',
          'ProgramFiles(x86)': r'C:\Program Files (x86)',
        },
      );
      expect(
        locator.detect().path,
        r'C:\Program Files (x86)\Mozilla Firefox\xul.dll',
      );
    });

    test('完全未命中时如实报告，不编造路径与版本', () {
      final locator = locatorFor('windows', const {});
      final probe = locator.detect();

      expect(probe.found, isFalse);
      expect(probe.path, isNull);
      expect(probe.version, isNull);
      expect(probe.buildId, isNull);
      expect(probe.source, EngineRuntimeSource.none);
      expect(probe.candidates, isNotEmpty);
      expect(probe.hits, isEmpty);
      expect(probe.summary, contains('未检测到 Gecko 运行时'));
    });

    test('只有安装痕迹（firefox.exe）时给出"线索"而非"已就绪"', () {
      final locator = locatorFor(
        'windows',
        {r'C:\Program Files\Mozilla Firefox\firefox.exe'},
        environment: const {'ProgramFiles': r'C:\Program Files'},
      );
      final probe = locator.detect();

      expect(probe.found, isFalse);
      expect(probe.hasClueOnly, isTrue);
      expect(probe.clues.single.kind, EngineRuntimeCandidateKind.clue);
      expect(probe.summary, contains('安装痕迹'));
    });

    test('PATH 上的 firefox.exe 只作为线索候选', () {
      final locator = locatorFor(
        'windows',
        const {},
        environment: const {'Path': r'C:\Tools;D:\bin'},
      );
      final pathCandidates = locator
          .candidates()
          .where((c) => c.source == EngineRuntimeSource.pathExecutable)
          .toList();

      expect(
        pathCandidates.map((c) => c.path),
        containsAll(<String>[r'C:\Tools\firefox.exe', r'D:\bin\firefox.exe']),
      );
      expect(pathCandidates.every((c) => !c.isLibrary), isTrue);
    });

    test('MOZ* 环境变量：目录线索会被展开，非路径值被跳过', () {
      final locator = locatorFor(
        'windows',
        {r'D:\gecko\xul.dll'},
        environment: const {
          'MOZ_GECKO_DIR': r'D:\gecko',
          'MOZ_ENABLE_WAYLAND': '1',
        },
      );
      final envCandidates = locator
          .candidates()
          .where((c) => c.source == EngineRuntimeSource.environment)
          .toList();

      expect(
        envCandidates.map((c) => c.path),
        contains(r'D:\gecko\xul.dll'),
      );
      expect(
        locator.candidates().any((c) => c.note.contains('MOZ_ENABLE_WAYLAND')),
        isFalse,
        reason: '值为 1 的环境变量不是路径，不应产生候选',
      );

      final probe = locator.detect();
      expect(probe.found, isTrue);
      expect(probe.source, EngineRuntimeSource.environment);
      expect(probe.path, r'D:\gecko\xul.dll');
    });

    test('MOZ* 环境变量直接指向库文件时按运行时库处理', () {
      final locator = locatorFor(
        'windows',
        {r'E:\custom\xul.dll'},
        environment: const {'MOZ_GECKO_LIB': r'E:\custom\xul.dll'},
      );
      final c = locator
          .candidates()
          .firstWhere((c) => c.source == EngineRuntimeSource.environment);
      expect(c.isLibrary, isTrue);
      expect(locator.detect().found, isTrue);
    });
  });

  group('EngineRuntimeLocator · Linux / Android / macOS', () {
    test('Linux 命中发行版路径与 snap 路径候选', () {
      final paths = locatorFor('linux', const {})
          .candidates()
          .map((c) => c.path)
          .toList();
      expect(
        paths,
        containsAll(<String>[
          '/usr/lib/firefox/libxul.so',
          '/usr/lib/firefox-esr/libxul.so',
          '/usr/lib64/firefox/libxul.so',
          '/opt/firefox/libxul.so',
          '/snap/firefox/current/usr/lib/firefox/libxul.so',
        ]),
      );

      final probe =
          locatorFor('linux', const {'/usr/lib/firefox/libxul.so'}).detect();
      expect(probe.found, isTrue);
      expect(probe.path, '/usr/lib/firefox/libxul.so');
      expect(probe.summary, contains('本适配包不会加载它'));
    });

    test('Android：GeckoView 固定路径可探测，提示指向宿主集成', () {
      final probe = locatorFor(
        'android',
        const {'/system/lib64/libgeckoview.so'},
      ).detect();
      expect(probe.found, isTrue);
      expect(probe.path, '/system/lib64/libgeckoview.so');

      final hint = locatorFor('android', const {}).installHint;
      expect(hint, contains('GeckoView'));
      expect(hint, contains('宿主 APK'));
    });

    test('macOS：Firefox.app 内的 libxul.dylib', () {
      final probe = locatorFor(
        'macos',
        const {'/Applications/Firefox.app/Contents/MacOS/libxul.dylib'},
      ).detect();
      expect(probe.found, isTrue);
      expect(probe.candidates.any((c) => c.path == '/Applications/Firefox.app'),
          isTrue);
    });

    test('未提供候选清单的平台如实返回空清单（macOS 之外仍不报错）', () {
      final locator = locatorFor('unknown', const {});
      expect(locator.candidates(), isEmpty);
      expect(locator.detect().found, isFalse);
      expect(locator.installHint, contains('没有内置的 Gecko 候选路径'));
    });
  });

  group('EngineRuntimeLocator · 版本读取', () {
    test('从 platform.ini 读 Milestone / BuildID', () {
      final locator = EngineRuntimeLocator(
        platform: 'linux',
        exists: (path) => path == '/usr/lib/firefox/libxul.so',
        readText: (path) => path == '/usr/lib/firefox/platform.ini'
            ? '[BuildID]\nBuildID=20250101120000\n[Milestone]\nMilestone=134.0\n'
            : null,
        environment: const {},
      );
      final probe = locator.detect();

      expect(probe.version, '134.0');
      expect(probe.buildId, '20250101120000');
      expect(probe.summary, contains('发现 Gecko 运行时文件'));
    });

    test('platform.ini 缺失时退回 application.ini 的 Version', () {
      final locator = EngineRuntimeLocator(
        platform: 'linux',
        exists: (path) => path == '/usr/lib/firefox/libxul.so',
        readText: (path) => path == '/usr/lib/firefox/application.ini'
            ? 'Version=128.0\nBuildID=abc\n'
            : null,
        environment: const {},
      );
      expect(locator.detect().version, '128.0');
    });

    test('读不到 ini 时版本为 null，绝不编造', () {
      final locator = locatorFor('linux', const {'/usr/lib/firefox/libxul.so'});
      final probe = locator.detect();

      expect(locator.isHermetic, isTrue);
      expect(probe.found, isTrue);
      expect(probe.version, isNull);
      expect(probe.buildId, isNull);
    });
  });

  group('清单解析与校验', () {
    test('engine_adapter 是合法类型，且在所有平台视为可用', () {
      final m = KernelManifest.fromJson(adapterManifest());

      expect(KernelManifest.supportedTypes, contains('engine_adapter'));
      expect(m.validationErrors, isEmpty);
      expect(m.type, 'engine_adapter');
      expect(m.engine, KernelEngine.gecko);
      expect(m.title, 'Gecko 内核适配包（不提供网页渲染）');
      expect(m.capabilities, isEmpty);
      for (final platform in ['windows', 'linux', 'android', 'macos']) {
        expect(m.supportsPlatform(platform), isTrue,
            reason: '适配器不携带平台产物，$platform 也应视为可用');
      }
    });

    test('非法 type 仍然被拒绝', () {
      final m = KernelManifest.fromJson(adapterManifest(type: 'native_plugin'));
      expect(m.validationErrors, isNotEmpty);
      expect(m.validationErrors.join('|'), contains('"type"'));
    });
  });

  group('内核包安装（真实目录 build_kernel_pkg/zb_gecko_kernel）', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('zb_gecko_pkg_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Directory kernelsDir() =>
        Directory(p.join(root.path, 'kernels'))..createSync(recursive: true);

    test('可安装，且声明了三平台 FFI 产物（gecko 已是真渲染内核）', () {
      final record = KernelPackage.install(
        zipBytes: zipDir('build_kernel_pkg/zb_gecko_kernel'),
        kernelsDir: kernelsDir(),
      );

      expect(record.id, 'com.zipbrowser.kernel.gecko');
      expect(record.kernelId, 'kernel.com.zipbrowser.kernel.gecko');
      expect(record.manifest.type, 'ffi');
      expect(record.manifest.engine, KernelEngine.gecko);
      expect(record.manifest.version, '1.0.0');
      expect(record.manifest.libraries.keys,
          containsAll(['windows', 'linux', 'android']));
      expect(record.manifest.runtimeDir, isNull);
      expect(record.manifest.capabilities, isNotEmpty);
      expect(record.isTampered, isFalse);
      expect(
        File(p.join(record.directory.path, 'kernel.json')).existsSync(),
        isTrue,
      );
      expect(File(p.join(record.directory.path, 'README.md')).existsSync(),
          isTrue);
    });

    test('availableOn() 三平台为 true，且各平台都解析出真实库文件', () {
      final record = KernelPackage.install(
        zipBytes: zipDir('build_kernel_pkg/zb_gecko_kernel'),
        kernelsDir: kernelsDir(),
      );

      expect(record.availableOn('windows'), isTrue);
      expect(record.availableOn('linux'), isTrue);
      expect(record.availableOn('android', abi: 'arm64-v8a'), isTrue);
      expect(record.availableOn('android', abi: 'armeabi-v7a'), isTrue);
      expect(record.availableOn('android', abi: 'x86_64'), isTrue);
      expect(record.libraryPathFor('windows'), isNotNull);
      expect(record.libraryPathFor('linux'), isNotNull);
      expect(record.libraryPathFor('android', abi: 'arm64-v8a'), isNotNull);
      expect(record.runtimeDirPath, isNull);
    });

    test('ffi 包缺少 libraries 时仍被拒绝（原规则不变）', () {
      final dir = kernelsDir();
      expect(
        () => KernelPackage.install(
          zipBytes: zipManifest(adapterManifest(type: 'ffi')),
          kernelsDir: dir,
        ),
        throwsA(
          isA<KernelInstallException>().having(
            (e) => e.reasons.join('|'),
            'errors',
            contains('清单未声明任何平台产物'),
          ),
        ),
      );
    });

    test('webview2_fixed 包缺少 runtime_dir 时仍被拒绝', () {
      expect(
        () => KernelPackage.install(
          zipBytes: zipManifest(adapterManifest(type: 'webview2_fixed')),
          kernelsDir: kernelsDir(),
        ),
        throwsA(isA<KernelInstallException>()),
      );
    });

    test('type 非法的包无法安装', () {
      expect(
        () => KernelPackage.install(
          zipBytes: zipManifest(adapterManifest(type: 'native_plugin')),
          kernelsDir: kernelsDir(),
        ),
        throwsA(isA<KernelInstallException>()),
      );
    });
  });

  group('内核接入（KernelManager / KernelRegistry）', () {
    late Directory root;
    late ConfigService config;
    late PluginManager pluginManager;
    late KernelManager kernelManager;
    late KernelRegistry registry;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zb_gecko_registry_');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      config = await ConfigService.create();

      final pluginsDir = Directory(p.join(root.path, 'plugins'))
        ..createSync(recursive: true);
      pluginManager = PluginManager(pluginsDir: pluginsDir)..loadAll();

      kernelManager = KernelManager(
        kernelsDir: Directory(p.join(root.path, 'kernels')),
      )..loadAll();
      kernelManager.installFromBytes(zipDir('build_kernel_pkg/zb_gecko_kernel'));

      registry = KernelRegistry(
        config: config,
        pluginManager: pluginManager,
        kernelManager: kernelManager,
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('在「内核管理」可见：描述项可用且标注为 FFI 渲染内核', () {
      final described = registry
          .describe()
          .where((d) => d.id == 'kernel.com.zipbrowser.kernel.gecko')
          .toList();

      expect(described, hasLength(1));
      final d = described.single;
      expect(d.packageType, 'ffi');
      expect(d.engine, KernelEngine.gecko);
      expect(d.origin, KernelOrigin.standalone);
      expect(d.available, isTrue);
      expect(d.capabilities, contains(KernelCapability.loadUrl));
      expect(d.unavailableReason, isNull);

      expect(
        kernelManager.availableHere().map((k) => k.id),
        contains('com.zipbrowser.kernel.gecko'),
      );
    });

    test('选中后能构造出 FfiBrowserKernel（引擎为 gecko）', () async {
      await config.setSelectedKernelId('kernel.com.zipbrowser.kernel.gecko');
      final kernel = registry.createKernel('tab-1');

      expect(kernel, isA<FfiBrowserKernel>());
      final ffi = kernel as FfiBrowserKernel;
      expect(ffi.source, isA<StandaloneKernelOffer>());
      expect(
        (ffi.source as StandaloneKernelOffer).package.manifest.engine,
        KernelEngine.gecko,
      );
      expect(ffi.origin, KernelOrigin.standalone);
      expect(ffi.capabilities, contains(KernelCapability.loadUrl));
      expect(ffi.displayName, isNot(contains('适配包')));
      await ffi.dispose();
    });
  });

  group('内核 API 的诚实行为', () {
    late Directory root;
    late StandaloneKernelOffer offer;

    setUp(() {
      root = Directory.systemTemp.createTempSync('zb_gecko_api_');
      final kernelsDir = Directory(p.join(root.path, 'kernels'))
        ..createSync(recursive: true);
      final record = KernelPackage.install(
        zipBytes: zipDir('build_kernel_pkg/zb_gecko_kernel'),
        kernelsDir: kernelsDir,
      );
      offer = StandaloneKernelOffer(record);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    EngineAdapterKernel build({String? version}) {
      return EngineAdapterKernel(
        source: offer,
        locator: EngineRuntimeLocator(
          platform: 'linux',
          exists: (path) => path == '/usr/lib/firefox/libxul.so',
          readText: version == null
              ? null
              : (path) => path == '/usr/lib/firefox/platform.ini'
                  ? 'Milestone=$version\nBuildID=20250101120000\n'
                  : null,
          environment: const {},
        ),
      );
    }

    test('loadUrl 不谎报成功：只记录请求并发 blocked，不进历史、不报进度', () async {
      final kernel = build();
      await kernel.initialize(const KernelViewConfig(tabId: 'tab-1'));

      final events = <NavigationEvent>[];
      final sub = kernel.navigationEvents.listen(events.add);

      expect(kernel.hasBlockedNavigation, isFalse);
      await kernel.loadUrl('https://example.com/a');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.map((e) => e.stage).toList(), <NavigationStage>[
        NavigationStage.blocked,
      ]);
      expect(kernel.hasBlockedNavigation, isTrue);
      expect(kernel.lastRequestedUrl, 'https://example.com/a');
      expect(await kernel.getCurrentUrl(), 'https://example.com/a');
      expect(await kernel.getCurrentTitle(), isNull);
      expect(await kernel.canGoBack(), isFalse);
      expect(await kernel.canGoForward(), isFalse);
      expect(await kernel.progress.isEmpty, isTrue);
      expect(await kernel.sniffedResources.isEmpty, isTrue);
      expect(await kernel.downloadRequests.isEmpty, isTrue);
      expect(await kernel.userscriptDetected.isEmpty, isTrue);
      expect(await kernel.resourceErrors.isEmpty, isTrue);
      expect(await kernel.titleChanges.isEmpty, isTrue);

      await sub.cancel();
      await kernel.dispose();
    });

    test('evaluateJavascript 返回空串，页面内查找返回 0', () async {
      final kernel = build();
      await kernel.initialize(const KernelViewConfig(tabId: 'tab-1'));

      expect(await kernel.evaluateJavascript('document.title'), '');
      expect(await kernel.findStart('zip'), 0);
      // 无会话、无页面：这些都是无害 no-op
      await kernel.findNext(true);
      await kernel.findClear();
      await kernel.clearCookies();
      await kernel.clearCache();
      await kernel.goBack();
      await kernel.reload();
      await kernel.stopLoading();

      await kernel.dispose();
    });

    test('内置 data: 首页不进地址栏（它不是用户导航）', () async {
      final kernel = build();
      await kernel.initialize(const KernelViewConfig(tabId: 'tab-1'));
      await kernel.loadUrl('data:text/html,<h1>home</h1>');

      expect(kernel.hasBlockedNavigation, isTrue);
      expect(await kernel.getCurrentUrl(), isNull);
      await kernel.dispose();
    });

    test('能力声明为空，版本如实透传或为 null', () async {
      final withVersion = build(version: '134.0');
      expect(withVersion.capabilities, isEmpty);
      expect(await withVersion.version, '134.0');
      await withVersion.dispose();

      final without = build();
      expect(await without.version, isNull);
      await without.dispose();
    });

    test('重新检测会刷新探测结果与视图版本号', () async {
      final kernel = build(version: '134.0');
      final before = kernel.probeRevision.value;

      expect(kernel.probe.found, isTrue);
      kernel.redetect();
      expect(kernel.probeRevision.value, greaterThan(before));
      expect(kernel.probe.found, isTrue);
      await kernel.dispose();
    });

    testWidgets('诊断视图如实显示"不提供网页渲染"与候选路径', (tester) async {
      final kernel = build(version: '134.0');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: kernel.buildView()),
      ));

      expect(find.text('不提供网页渲染'), findsOneWidget);
      expect(find.text(EngineAdapterKernel.cannotRenderNotice), findsOneWidget);
      expect(find.text('${KernelEngine.gecko.label} 引擎适配包'), findsOneWidget);
      expect(find.textContaining('版本 134.0'), findsOneWidget);

      await tester.scrollUntilVisible(find.textContaining('候选路径（共'), 300);
      expect(find.textContaining('候选路径（共'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('重新检测'), 300);
      final before = kernel.probeRevision.value;
      await tester.tap(find.text('重新检测'));
      await tester.pump();
      expect(kernel.probeRevision.value, greaterThan(before),
          reason: '"重新检测"按钮必须真的重新探测');

      await kernel.dispose();
    });
  });
}
