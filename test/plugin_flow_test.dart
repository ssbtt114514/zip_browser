import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zip_browser/core/plugin/plugin_manager.dart';
import 'package:zip_browser/core/plugin/plugin_package.dart';

void main() {
  late Directory tempRoot;
  late Directory pluginsDir;
  late File zipFile;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('zb_test_');
    pluginsDir = Directory('${tempRoot.path}/plugins')
      ..createSync(recursive: true);
    zipFile = File('dark_mode.zip');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('zip 插件可安装并记录元数据', () {
    expect(zipFile.existsSync(), isTrue, reason: 'dark_mode.zip 应存在于工程根');

    final record = PluginPackage.install(
      zipBytes: zipFile.readAsBytesSync(),
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
      zipBytes: zipFile.readAsBytesSync(),
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
      zipBytes: zipFile.readAsBytesSync(),
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
      zipBytes: zipFile.readAsBytesSync(),
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
}
