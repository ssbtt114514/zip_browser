import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zip_browser/core/kernel/kernel_package.dart';
import 'package:zip_browser/core/plugin/ffi_kernel_loader.dart';
import 'package:zip_browser/core/plugin/plugin_package.dart';
import 'package:zip_browser/services/paths.dart';

/// 按 `tool/pack_plugin.py` / `tool/pack_kernel.py` 的规则（以源目录为 zip 根）
/// 在内存中打包，从而在测试里覆盖「打包 → 安装」这条真实链路，
/// 而不依赖仓库里不存在的构建产物。
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

/// ABI 头文件声明的 16 个导出符号
const List<String> kRequiredAbiSymbols = [
  'zb_abi_version',
  'zb_kernel_create',
  'zb_kernel_destroy',
  'zb_kernel_name',
  'zb_kernel_version',
  'zb_kernel_load_url',
  'zb_kernel_go_back',
  'zb_kernel_go_forward',
  'zb_kernel_reload',
  'zb_kernel_eval_js',
  'zb_kernel_current_url',
  'zb_kernel_title',
  'zb_kernel_attach_surface',
  'zb_kernel_tick',
  'zb_kernel_dispatch_from_host',
  'zb_free_ptr',
];

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zb_lite_pkg_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('轻量文本内核 · 插件包（example_plugins/lite_kernel）', () {
    test('可被 PluginPackage 安装，且内核声明完整', () {
      final pluginsDir = Directory(p.join(root.path, 'plugins'))
        ..createSync(recursive: true);

      final record = PluginPackage.install(
        zipBytes: zipDir('example_plugins/lite_kernel'),
        pluginsDir: pluginsDir,
      );

      expect(record.id, 'com.zipbrowser.lite_kernel');
      expect(record.enabled, isTrue);
      expect(record.zipSha256, hasLength(64));

      final spec = record.manifest.kernel;
      expect(spec, isNotNull, reason: 'manifest 必须声明 kernel 字段才能替换内核');
      expect(spec!.type, 'ffi');
      expect(spec.abiVersion, kHostFfiAbiVersion,
          reason: 'ABI 版本必须与宿主的 kHostFfiAbiVersion 一致');
      expect(spec.displayName, isNotNull);
      expect(spec.displayName, isNotEmpty);

      // 三平台产物都要声明（Linux/Android 由构建脚本产出）
      expect(spec.libraryRelativeFor('windows'), isNotNull);
      expect(spec.libraryRelativeFor('linux'), isNotNull);
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
        expect(spec.libraryRelativeFor('android', abi: abi), isNotNull,
            reason: '缺少 Android $abi 产物声明');
      }
    });

    test('随包提交的 Windows DLL 是真实动态库且导出全部 16 个 ABI 符号', () {
      final pluginsDir = Directory(p.join(root.path, 'plugins'))
        ..createSync(recursive: true);
      final record = PluginPackage.install(
        zipBytes: zipDir('example_plugins/lite_kernel'),
        pluginsDir: pluginsDir,
      );

      final rel = record.manifest.kernel!.libraryRelativeFor('windows')!;
      final dll = File(p.join(record.directory.path, rel));
      expect(dll.existsSync(), isTrue, reason: '插件包内应包含 $rel');

      final bytes = dll.readAsBytesSync();
      expect(bytes.length, greaterThan(4096), reason: 'DLL 体积异常，疑似占位文件');
      // PE 文件头
      expect(String.fromCharCodes(bytes.sublist(0, 2)), 'MZ');

      // 导出名表以明文保存在 PE 里，可直接做子串校验（无需解析 PE）
      final text = latin1.decode(bytes);
      final missing =
          kRequiredAbiSymbols.where((s) => !text.contains(s)).toList();
      expect(missing, isEmpty, reason: 'DLL 缺少导出符号：$missing');
    });
  });

  group('轻量文本内核 · 独立内核包（build_kernel_pkg/zb_lite_kernel）', () {
    test('可被 KernelPackage 安装，ABI 与类型正确', () {
      final kernelsDir = Directory(p.join(root.path, 'kernels'))
        ..createSync(recursive: true);

      final record = KernelPackage.install(
        zipBytes: zipDir('build_kernel_pkg/zb_lite_kernel'),
        kernelsDir: kernelsDir,
      );

      expect(record.id, 'com.zipbrowser.kernel.lite');
      expect(record.manifest.type, 'ffi');
      expect(record.manifest.abiVersion, kHostFfiAbiVersion);
      expect(record.manifest.capabilities,
          containsAll(<String>['loadUrl', 'evaluateJs']));
      expect(record.isTampered, isFalse);
      expect(File('${record.directory.path}/kernel.json').existsSync(), isTrue);
    });

    test('当前平台可探测性：Windows 产物随包提供，其它平台按声明判定', () {
      final kernelsDir = Directory(p.join(root.path, 'kernels'))
        ..createSync(recursive: true);
      final record = KernelPackage.install(
        zipBytes: zipDir('build_kernel_pkg/zb_lite_kernel'),
        kernelsDir: kernelsDir,
      );

      // 仓库只随包提交了 windows 产物，linux/android 需先跑构建脚本
      expect(record.availableOn('windows'), isTrue);
      expect(record.availableOn('linux'), isFalse);
      expect(record.availableOn('android', abi: 'arm64-v8a'), isFalse);

      final key = AppPaths.platformKey;
      if (key == 'windows') {
        final lib = record.libraryPathFor('windows');
        expect(lib, isNotNull);
        expect(File(lib!).existsSync(), isTrue);
      }
    });
  });
}
