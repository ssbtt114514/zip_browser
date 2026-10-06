import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zip_browser/core/plugin/plugin_manager.dart';
import 'package:zip_browser/core/plugin/plugin_package.dart';

/// 在内存中按 `tool/pack_plugin.py` 的规则（以插件目录为 zip 根）打包示例插件。
///
/// 原先测试直接读取工程根下的 `dark_mode.zip`，而该产物不入库（由打包脚本
/// 生成），导致全新克隆后测试必然失败。这里改为从源码目录即时构建，
/// 让测试变成自包含的。
List<int> buildPluginZip(String pluginDir) {
  final src = Directory(pluginDir);
  if (!src.existsSync()) {
    throw StateError('示例插件目录不存在：$pluginDir');
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
  if (encoded == null) throw StateError('打包失败：$pluginDir');
  return encoded;
}

void main() {
  late Directory tempRoot;
  late Directory pluginsDir;
  late List<int> zipBytes;

  setUpAll(() {
    zipBytes = buildPluginZip('example_plugins/dark_mode');
  });

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('zb_test_');
    pluginsDir = Directory('${tempRoot.path}/plugins')
      ..createSync(recursive: true);
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('示例插件源码目录结构符合预期', () {
    expect(zipBytes, isNotEmpty);
    expect(File('example_plugins/dark_mode/manifest.json').existsSync(), isTrue);
    expect(File('example_plugins/dark_mode/extension.js').existsSync(), isTrue);
  });

  test('zip 插件可安装并记录元数据', () {
    final record = PluginPackage.install(
      zipBytes: zipBytes,
      pluginsDir: pluginsDir,
    );

    expect(record.id, 'com.zipbrowser.darkmode');
    expect(record.manifest.name, '夜间模式');
    expect(record.zipSha256, hasLength(64));
    expect(record.enabled, isTrue);

    // 文件落盘
    expect(File('${record.directory.path}/manifest.json').existsSync(), isTrue);
    expect(File('${record.directory.path}/extension.js').existsSync(), isTrue);
    expect(File('${record.directory.path}/install.json').existsSync(), isTrue);
    expect(File('${record.directory.path}/icons/icon.png').existsSync(), isTrue);
  });

  test('PluginManager 可加载、收集脚本与权限', () {
    PluginPackage.install(
      zipBytes: zipBytes,
      pluginsDir: pluginsDir,
    );

    final pm = PluginManager(pluginsDir: pluginsDir);
    pm.loadAll();

    expect(pm.plugins, hasLength(1));
    expect(pm.enabledPlugins, hasLength(1));

    final scripts = pm.collectUserScripts();
    expect(scripts, hasLength(1));
    expect(scripts.first.source, contains('__zb_dark_mode__'));
    expect(scripts.first.pluginId, 'com.zipbrowser.darkmode');

    final granted = pm.grantedBridgeMethods();
    expect(granted, containsAll(<String>[
      'storage.get', 'storage.set', 'storage.remove', 'storage.keys',
    ]));
  });

  test('停用插件后不再收集脚本', () {
    PluginPackage.install(
      zipBytes: zipBytes,
      pluginsDir: pluginsDir,
    );
    final pm = PluginManager(pluginsDir: pluginsDir);
    pm.loadAll();

    pm.setEnabled('com.zipbrowser.darkmode', false);
    expect(pm.collectUserScripts(), isEmpty);
    expect(pm.grantedBridgeMethods(), isEmpty);

    // 重新加载后状态保持
    final pm2 = PluginManager(pluginsDir: pluginsDir);
    pm2.loadAll();
    expect(pm2.enabledPlugins, isEmpty);
  });

  test('篡改插件目录会被检测并强制停用', () {
    final record = PluginPackage.install(
      zipBytes: zipBytes,
      pluginsDir: pluginsDir,
    );
    // 追加恶意内容
    File('${record.directory.path}/extension.js')
        .writeAsStringSync('\n// tampered\n');

    final pm = PluginManager(pluginsDir: pluginsDir);
    pm.loadAll();

    expect(pm.tamperedPluginIds, contains('com.zipbrowser.darkmode'));
    final plugin = pm.byId('com.zipbrowser.darkmode')!;
    expect(plugin.isTampered, isTrue);
    expect(plugin.enabled, isFalse);
    expect(pm.enabledPlugins, isEmpty);
  });

  test('非法/损坏 zip 被拒绝', () {
    expect(
      () => PluginPackage.install(
        zipBytes: [1, 2, 3, 4],
        pluginsDir: pluginsDir,
      ),
      throwsA(isA<PluginInstallException>()),
    );

    expect(
      () => PluginPackage.install(
        zipBytes: File('README.md').readAsBytesSync(),
        pluginsDir: pluginsDir,
      ),
      throwsA(isA<PluginInstallException>()),
    );
  });

  test('缺少 manifest 的 zip 被拒绝', () {
    final archive = Archive();
    final bytes = File('README.md').readAsBytesSync();
    archive.addFile(ArchiveFile('docs/README.md', bytes.length, bytes));
    final encoded = ZipEncoder().encode(archive)!;

    expect(
      () => PluginPackage.install(
        zipBytes: encoded,
        pluginsDir: pluginsDir,
      ),
      throwsA(isA<PluginInstallException>()),
    );
  });
}
