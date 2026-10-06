/// 用宿主自己的安装器校验「打包产物」是否真的能安装并加载。
///
/// 背景：CI 的 package job 会产出 `lite_kernel.zip`、`hello_ffi_kernel.zip`
/// 与 `zb_lite_kernel.zbk`。仅检查 zip 里有哪些文件并不足以说明问题——
/// 真正重要的是这些包能被 [PluginPackage.install] / [KernelPackage.install]
/// 装出来，且清单声明的内核库在安装后确实存在于对应路径。
/// 本工具就是跑这条真实链路。
///
/// 用法：
///   dart run tool/verify_packages.dart lite_kernel.zip hello_ffi_kernel.zip zb_lite_kernel.zbk
///   dart run tool/verify_packages.dart --dir dist/packages
///
/// 退出码：0 = 全部通过；1 = 存在校验失败。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zip_browser/core/kernel/kernel_package.dart';
import 'package:zip_browser/core/plugin/plugin_manifest.dart';
import 'package:zip_browser/core/plugin/plugin_package.dart';

int _failures = 0;
int _checks = 0;

void _ok(String msg) => stdout.writeln('  [OK]   $msg');

void _bad(String msg) {
  _failures++;
  stdout.writeln('  [FAIL] $msg');
}

void _check(bool condition, String what) {
  _checks++;
  if (condition) {
    _ok(what);
  } else {
    _bad(what);
  }
}

/// 清单里声明的全部内核库：(平台, abi, 相对路径)
class _DeclaredLib {
  _DeclaredLib(this.platform, this.abi, this.relative);
  final String platform;
  final String? abi;
  final String relative;

  String get label => abi == null ? platform : '$platform/$abi';
}

List<_DeclaredLib> _declaredLibraries(PluginKernelSpec spec) {
  final out = <_DeclaredLib>[];
  spec.libraries.forEach((platform, value) {
    if (value is String) {
      out.add(_DeclaredLib(platform, null, value));
    } else if (value is Map) {
      value.forEach((abi, rel) {
        out.add(_DeclaredLib(platform, abi.toString(), rel.toString()));
      });
    }
  });
  return out;
}

void _verifyPluginZip(File zip, Directory tempRoot) {
  stdout.writeln('\n== 插件包 ${p.basename(zip.path)}（${zip.lengthSync()} 字节）');
  final pluginsDir = Directory(p.join(tempRoot.path, 'plugins'));
  pluginsDir.createSync(recursive: true);

  InstalledPlugin installed;
  try {
    installed = PluginPackage.install(
      zipBytes: zip.readAsBytesSync(),
      pluginsDir: pluginsDir,
    );
  } catch (e) {
    _bad('安装失败：$e');
    return;
  }

  _ok('已安装 id=${installed.manifest.id} 版本=${installed.manifest.version}');
  _check(
    File(p.join(installed.directory.path, 'manifest.json')).existsSync(),
    '安装目录根部存在 manifest.json',
  );

  final kernel = installed.manifest.kernel;
  if (kernel == null) {
    _ok('该插件未声明内核，跳过内核库校验');
    return;
  }
  _check(kernel.type == 'ffi', '内核类型为 ffi（实际 ${kernel.type}）');

  final declared = _declaredLibraries(kernel);
  _check(declared.isNotEmpty, '清单声明了内核库路径');

  for (final lib in declared) {
    final abs = p.join(installed.directory.path,
        lib.relative.replaceAll('/', p.separator));
    final f = File(abs);
    _check(f.existsSync(), '${lib.label} -> ${lib.relative}'
        '${f.existsSync() ? '（${f.lengthSync()} 字节）' : '（缺失！）'}');
  }
}

void _verifyKernelPackage(File zbk, Directory tempRoot) {
  stdout.writeln('\n== 独立内核包 ${p.basename(zbk.path)}（${zbk.lengthSync()} 字节）');
  final kernelsDir = Directory(p.join(tempRoot.path, 'kernels'));
  kernelsDir.createSync(recursive: true);

  InstalledKernel installed;
  try {
    installed = KernelPackage.install(
      zipBytes: zbk.readAsBytesSync(),
      kernelsDir: kernelsDir,
    );
  } catch (e) {
    _bad('安装失败：$e');
    return;
  }

  _ok('已安装 id=${installed.id} kernelId=${installed.kernelId}');
  _check(
    File(p.join(installed.directory.path, kKernelManifestEntry)).existsSync(),
    '安装目录根部存在 $kKernelManifestEntry',
  );

  for (final platform in const ['windows', 'linux']) {
    final path = installed.libraryPathFor(platform);
    _check(installed.availableOn(platform),
        '$platform 可用${path == null ? '（未声明）' : '：$path'}');
  }
  for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
    final path = installed.libraryPathFor('android', abi: abi);
    _check(installed.availableOn('android', abi: abi),
        'android/$abi 可用${path == null ? '（未声明）' : '：$path'}');
  }

  final reloaded = InstalledKernel.load(installed.directory);
  _check(reloaded != null, '安装目录可被 InstalledKernel.load 重新读取');
  if (reloaded != null) {
    _check(!reloaded.isTampered, '重载后指纹一致（未被篡改）');
  }
}

List<File> _collect(List<String> args) {
  final files = <File>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dir') {
      if (i + 1 >= args.length) {
        stderr.writeln('--dir 需要一个目录参数');
        exit(2);
      }
      final dir = Directory(args[++i]);
      if (!dir.existsSync()) {
        stderr.writeln('目录不存在：${dir.path}');
        exit(2);
      }
      for (final e in dir.listSync()) {
        if (e is File &&
            (e.path.endsWith('.zip') || e.path.endsWith('.zbk'))) {
          files.add(e);
        }
      }
      continue;
    }
    final f = File(args[i]);
    if (!f.existsSync()) {
      stderr.writeln('文件不存在：${f.path}');
      exit(2);
    }
    files.add(f);
  }
  return files;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法：dart run tool/verify_packages.dart '
        '<包文件...> | --dir <目录>');
    exit(2);
  }

  final files = _collect(args);
  if (files.isEmpty) {
    stderr.writeln('没有找到任何 .zip / .zbk 包');
    exit(2);
  }

  final tempRoot = Directory.systemTemp.createTempSync('zb_pkg_verify_');
  try {
    for (final f in files) {
      if (f.path.endsWith('.zbk')) {
        _verifyKernelPackage(f, tempRoot);
      } else {
        _verifyPluginZip(f, tempRoot);
      }
    }
  } finally {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  }

  stdout.writeln('\n共 $_checks 项校验，失败 $_failures 项');
  if (_failures == 0) {
    stdout.writeln('结论：全部打包产物均可被宿主正常安装');
  } else {
    stdout.writeln('结论：存在打包问题，需要修复');
  }
  exit(_failures == 0 ? 0 : 1);
}
