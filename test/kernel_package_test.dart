import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zip_browser/core/kernel/kernel_manager.dart';
import 'package:zip_browser/core/kernel/kernel_package.dart';
import 'package:zip_browser/services/paths.dart';

/// 构造一个内存中的 .zbk 内核包
List<int> buildKernelZip({
  String id = 'com.example.kernel.demo',
  int abiVersion = 1,
  String type = 'ffi',
  Map<String, dynamic>? libraries,
  List<MapEntry<String, String>> extraFiles = const [],
}) {
  final manifest = <String, dynamic>{
    'manifest_version': 1,
    'id': id,
    'name': 'Demo Kernel',
    'version': '1.0.0',
    'engine': 'chromium',
    'type': type,
    'abi_version': abiVersion,
    'capabilities': ['loadUrl', 'evaluateJs'],
    'libraries': libraries ??
        {
          'windows': 'bin/windows/kernel.dll',
          'linux': 'bin/linux/libkernel.so',
          'android': {'arm64-v8a': 'bin/android/arm64-v8a/libkernel.so'},
        },
  };

  final archive = Archive();
  void add(String name, String data) {
    final bytes = utf8.encode(data);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('kernel.json', jsonEncode(manifest));
  add('bin/windows/kernel.dll', 'placeholder');
  add('bin/linux/libkernel.so', 'placeholder');
  add('bin/android/arm64-v8a/libkernel.so', 'placeholder');
  for (final e in extraFiles) {
    add(e.key, e.value);
  }
  return ZipEncoder().encode(archive)!;
}

void main() {
  late Directory tempRoot;
  late Directory kernelsDir;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('zb_kernel_test_');
    kernelsDir = Directory('${tempRoot.path}/kernels')..createSync(recursive: true);
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('独立内核包可安装、落盘并被管理器探测', () {
    final record = KernelPackage.install(
      zipBytes: buildKernelZip(),
      kernelsDir: kernelsDir,
    );

    expect(record.id, 'com.example.kernel.demo');
    expect(record.kernelId, 'kernel.com.example.kernel.demo');
    expect(record.zipSha256, hasLength(64));
    expect(record.fingerprint, hasLength(64));
    expect(record.isTampered, isFalse);
    expect(record.availableOn('linux'), isTrue);
    expect(record.availableOn('windows'), isTrue);
    expect(record.runtimeDirPath, isNull);

    final dir = record.directory;
    expect(File('${dir.path}/kernel.json').existsSync(), isTrue);
    expect(File('${dir.path}/install.json').existsSync(), isTrue);
    expect(File('${dir.path}/bin/linux/libkernel.so').existsSync(), isTrue);

    // 管理器扫描
    final manager = KernelManager(kernelsDir: kernelsDir)..loadAll();
    expect(manager.kernels, hasLength(1));
    expect(manager.trustedKernels, hasLength(1));
    expect(manager.tamperedKernelIds, isEmpty);
    expect(manager.byKernelId('kernel.com.example.kernel.demo'), isNotNull);
    expect(manager.availableHere().map((k) => k.id), contains('com.example.kernel.demo'));
  });

  test('平台产物缺失时仍可安装，但当前平台不可用', () {
    // 只声明一个与**当前宿主平台不同**的产物，这样断言与运行平台无关
    // （原先固定声明 windows，导致在 Windows 主机上跑必失败）。
    // 路径必须指向 buildKernelZip 真正写入包内的占位文件，否则
    // availableOn 会因为"文件不存在"而返回 false。
    const placeholder = {
      'windows': 'bin/windows/kernel.dll',
      'linux': 'bin/linux/libkernel.so',
    };
    final host = AppPaths.platformKey;
    final other = host == 'windows' ? 'linux' : 'windows';

    final record = KernelPackage.install(
      zipBytes: buildKernelZip(libraries: {other: placeholder[other]!}),
      kernelsDir: kernelsDir,
    );

    expect(record.availableOn(other), isTrue);
    expect(record.availableOn(host), isFalse);

    final manager = KernelManager(kernelsDir: kernelsDir)..loadAll();
    expect(manager.availableHere(), isEmpty);
    expect(manager.unavailableHere(), hasLength(1));
  });

  test('FFI ABI 版本不匹配被拒绝', () {
    expect(
      () => KernelPackage.install(
        zipBytes: buildKernelZip(abiVersion: 2),
        kernelsDir: kernelsDir,
      ),
      throwsA(isA<KernelInstallException>()),
    );
  });

  test('非法 id 与非法路径被拒绝', () {
    expect(
      () => KernelPackage.install(
        zipBytes: buildKernelZip(id: 'Not Valid Id'),
        kernelsDir: kernelsDir,
      ),
      throwsA(isA<KernelInstallException>()),
    );

    expect(
      () => KernelPackage.install(
        zipBytes: buildKernelZip(
          extraFiles: [const MapEntry('../evil.txt', 'pwned')],
        ),
        kernelsDir: kernelsDir,
      ),
      throwsA(isA<KernelInstallException>()),
    );
  });

  test('目录被篡改后被标记并阻止加载', () {
    final record = KernelPackage.install(
      zipBytes: buildKernelZip(),
      kernelsDir: kernelsDir,
    );
    File('${record.directory.path}/bin/linux/libkernel.so')
        .writeAsStringSync('tampered');

    final manager = KernelManager(kernelsDir: kernelsDir)..loadAll();
    expect(manager.tamperedKernelIds, contains('com.example.kernel.demo'));
    expect(manager.trustedKernels, isEmpty);
    expect(manager.byId('com.example.kernel.demo')!.isTampered, isTrue);
  });

  test('卸载会删除内核包目录', () async {
    final record = KernelPackage.install(
      zipBytes: buildKernelZip(),
      kernelsDir: kernelsDir,
    );
    final manager = KernelManager(kernelsDir: kernelsDir)..loadAll();
    expect(manager.kernels, hasLength(1));

    await manager.uninstall(record.id);
    expect(manager.kernels, isEmpty);
    expect(record.directory.existsSync(), isFalse);
  });
}
