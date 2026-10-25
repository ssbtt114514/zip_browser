import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/core/kernel/browser_kernel.dart';
import 'package:zip_browser/core/kernel/kernel_registry.dart';
import 'package:zip_browser/core/plugin/plugin_manager.dart';
import 'package:zip_browser/core/tab/tab_manager.dart';
import 'package:zip_browser/platform/stub_kernel.dart';
import 'package:zip_browser/services/bookmarks_service.dart';
import 'package:zip_browser/services/config_service.dart';
import 'package:zip_browser/services/download_runner.dart';
import 'package:zip_browser/services/downloads_service.dart';
import 'package:zip_browser/services/history_service.dart';
import 'package:zip_browser/services/host_bridge_api.dart';
import 'package:zip_browser/services/session_service.dart';

/// 用占位内核构造的注册表，避免测试触碰平台原生内核。
class _StubKernelRegistry extends KernelRegistry {
  _StubKernelRegistry(ConfigService config, PluginManager pluginManager)
      : super(config: config, pluginManager: pluginManager);

  @override
  BrowserKernel createKernel(String tabId) => _RecordingKernel();
}

/// 记录 loadUrl 并广播 URL 变更的占位内核：模拟真实内核的 URL 通知，
/// 使标签的 url 值能随导航更新（StubKernel 本身不产生任何事件）。
class _RecordingKernel extends StubKernel {
  final List<String> loadedUrls = [];
  final _urlCtrl = StreamController<String>.broadcast();

  @override
  Stream<String> get urlChanges => _urlCtrl.stream;

  @override
  Future<void> loadUrl(String url) async {
    loadedUrls.add(url);
    _urlCtrl.add(url);
  }

  @override
  Future<void> dispose() async {
    await _urlCtrl.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late TabManager tm;
  late SessionService session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('zb_session_test_');
    final config = await ConfigService.create();
    final pm = PluginManager(
        pluginsDir: Directory(p.join(dir.path, 'plugins')));
    final registry = _StubKernelRegistry(config, pm);
    final bookmarks =
        BookmarksService(File(p.join(dir.path, 'bookmarks.json')))..load();
    final history =
        HistoryService(File(p.join(dir.path, 'history.json')))..load();
    final downloads =
        DownloadsService(File(p.join(dir.path, 'downloads.json')))..load();
    final runner = DownloadRunner(
      service: downloads,
      downloadDir: Directory(p.join(dir.path, 'downloads')),
    );
    session = await SessionService.create();
    tm = TabManager(
      kernelRegistry: registry,
      pluginManager: pm,
      config: config,
      history: history,
      bookmarks: bookmarks,
      downloadRunner: runner,
      sessionService: session,
    );
    // 与 main.dart 一致：宿主 bridge 由调用方注入，标签初始化时会注册其处理器
    tm.hostApi = HostBridgeApi(
      tabManager: tm,
      config: config,
      kernelRegistry: registry,
    );
  });

  tearDown(() async {
    tm.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('restoreLastSession', () {
    test('恢复后不残留自动补建的主页占位标签', () async {
      // 建两个带地址的标签并写入快照
      final a = await tm.createTab();
      a.url.value = 'https://a.com/';
      final b = await tm.createTab();
      b.url.value = 'https://b.com/';
      await session.saveSnapshot(tm.sessionSnapshot());

      // 用同一快照恢复：先关闭现有标签再重建
      await tm.restoreLastSession();

      expect(tm.tabs.length, 2,
          reason: '恢复后应精确等于快照数量，不能多出 closeTab 自动补建的主页标签');
      final urls = tm.tabs.map((t) => t.url.value).toSet();
      expect(urls, contains('https://a.com/'));
      expect(urls, contains('https://b.com/'));
    });

    test('快照为空时不创建标签', () async {
      await session.clearSnapshot();
      final before = tm.tabs.length;
      await tm.restoreLastSession();
      expect(tm.tabs.length, before);
    });

    test('恢复上限为 16 个标签', () async {
      final many = List.generate(
        20,
        (i) => SessionTab(url: 'https://s$i.com/', title: 'S$i'),
      );
      await session.saveSnapshot(many);
      await tm.restoreLastSession();
      expect(tm.tabs.length, 16, reason: '恢复数量受上限保护约束');
    });
  });
}
