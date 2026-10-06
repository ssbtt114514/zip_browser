/// 用宿主自己的安装器校验「打包产物」是否真的能安装并加载。
///
/// 背景：CI 的 package job 会产出 `lite_kernel.zip`、`hello_ffi_kernel.zip`、
/// `zb_lite_kernel.zbk`、`zb_chromium_kernel.zbk`、`zb_gecko_kernel.zbk`。
/// 仅检查 zip 里有哪些文件并不足以说明问题——真正重要的是这些包能被
/// [PluginPackage.install] / [KernelPackage.install] 装出来，且清单声明的
/// 内核库（或固定版本运行时目录）在安装后确实存在于对应路径。
/// 本工具就是跑这条真实链路。
///
/// 三类内核包按 `type` 分别校验，规则与宿主安装器、`tool/pack_common.py`
/// 的"声明必须与实物一致"保持同一套语义：
///   * `ffi`            —— 清单声明的每个平台/ABI 库文件都必须真实存在；
///   * `webview2_fixed` —— 必须有运行时目录，且目录里必须有
///                        `msedgewebview2.exe`（宿主把它交给
///                        `WebviewController.initializeEnvironment`）；
///   * `engine_adapter` —— 不携带平台产物，全部平台都应视为可用。
///
/// 用法：
///   dart run tool/verify_packages.dart lite_kernel.zip hello_ffi_kernel.zip zb_lite_kernel.zbk
///   dart run tool/verify_packages.dart --dir dist/packages
///   dart run tool/verify_packages.dart --strict-runtime zb_chromium_kernel.zbk
///   dart run tool/verify_packages.dart --require-platforms windows,linux,android/arm64-v8a zb_lite_kernel.zbk
///
/// `--dir` 会把目录里所有 .zip/.zbk 都试一遍；其中不含任何清单的（CI 上传的
/// artifact 容器，如 `kernel-windows-dll.zip`）会被跳过并单独列出，
/// 不计入失败 —— 它们本来就不是可安装的包。
///
/// `--strict-runtime` 额外要求 webview2_fixed 的运行时体积不小于
/// [_minRuntimeBytes]，用于在 CI 上挡住"只有一个桩 exe 的假运行时"
/// （本机没有 NuGet 时只能拿桩运行时做链路验证，所以默认不开启）。
///
/// 退出码：0 = 全部通过；1 = 存在校验失败；2 = 参数错误。
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:zip_browser/core/kernel/kernel_package.dart';
import 'package:zip_browser/core/plugin/plugin_package.dart';

int _failures = 0;
int _checks = 0;
final List<String> _skipped = <String>[];

/// webview2_fixed 运行时被视为"真实"的最小体积（严格模式）
const int _minRuntimeBytes = 20 * 1024 * 1024;

/// Fixed Version 运行时里宿主真正依赖的可执行文件名
const String _webview2Exe = 'msedgewebview2.exe';

bool _strictRuntime = false;
List<String> _requiredPlatforms = <String>[];

void _ok(String msg) => stdout.writeln('  [OK]   $msg');

void _info(String msg) => stdout.writeln('  [信息] $msg');

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

List<_DeclaredLib> _declaredFromMap(Map<String, dynamic> libraries) {
  final out = <_DeclaredLib>[];
  libraries.forEach((platform, value) {
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
  // 插件侧的内核描述（PluginKernelSpec）只有 type / libraries / runtimeDir，
  // 没有引擎谱系概念 —— 引擎谱系只在独立内核包（KernelManifest）里存在。
  _info('插件内核类型=${kernel.type}');
  if (kernel.type != 'ffi') {
    _info('该插件声明的内核类型不是 ffi，仅核对已声明的文件路径');
  }

  final declared = _declaredFromMap(kernel.libraries);
  if (kernel.type == 'ffi') {
    _check(declared.isNotEmpty, '清单声明了内核库路径');
  }
  _info('清单声明 ${declared.length} 个平台/ABI 产物');
  for (final lib in declared) {
    final abs = p.join(
        installed.directory.path, lib.relative.replaceAll('/', p.separator));
    final f = File(abs);
    _check(f.existsSync(), '${lib.label} -> ${lib.relative}'
        '${f.existsSync() ? '（${f.lengthSync()} 字节）' : '（缺失！）'}');
  }
}

/// webview2_fixed：运行时目录必须存在，且必须有宿主依赖的 exe
void _verifyWebview2Kernel(InstalledKernel installed) {
  final runtimeDir = installed.runtimeDirPath;
  _check(runtimeDir != null,
      '运行时目录存在：${installed.manifest.runtimeDir ?? '(清单未声明 runtime_dir)'}');

  if (runtimeDir == null) {
    return;
  }

  final dir = Directory(runtimeDir);
  final files = <File>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is File) files.add(e);
  }
  var total = 0;
  for (final f in files) {
    try {
      total += f.lengthSync();
    } catch (_) {}
  }
  _info('运行时目录 ${files.length} 个文件，共 ${(total / 1048576).toStringAsFixed(1)} MB');

  var hasExe = false;
  for (final f in files) {
    if (p.basename(f.path).toLowerCase() == _webview2Exe) {
      hasExe = true;
      _check(f.lengthSync() > 0, '$_webview2Exe 非空（${f.lengthSync()} 字节）');
      break;
    }
  }
  _check(hasExe,
      '运行时目录内含 $_webview2Exe（宿主 WebviewController.initializeEnvironment 依赖）');

  if (_strictRuntime) {
    _check(total >= _minRuntimeBytes,
        '运行时体积 ${(total / 1048576).toStringAsFixed(1)} MB ≥ '
        '${(_minRuntimeBytes / 1048576).toStringAsFixed(0)} MB（严格模式，排除桩运行时）');
  }

  _check(installed.availableOn('windows'), 'windows 可用（type=webview2_fixed）');
  _check(!installed.availableOn('linux'), 'linux 不可用（固定版本运行时的设计如此）');

  if (installed.manifest.libraries.isNotEmpty) {
    _info('清单另外声明了 libraries，但 webview2_fixed 走运行时目录，这些声明会被忽略');
  }
}

/// engine_adapter：不携带平台产物，宿主的可用性判定应当全平台为真
void _verifyEngineAdapterKernel(InstalledKernel installed) {
  _info('engine_adapter 不携带平台产物，仅校验清单语义与全平台可用性');
  for (final platform in const ['windows', 'linux', 'android']) {
    _check(installed.availableOn(platform), '$platform 可用（适配包不分平台）');
  }
  _check(installed.runtimeDirPath == null || installed.manifest.runtimeDir == null,
      '未声明 runtime_dir（适配包不携带运行时）');
  _info('能力声明：${installed.manifest.capabilities.isEmpty ? '（空，如实反映不渲染）' : installed.manifest.capabilities.join(', ')}');
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

  final manifest = installed.manifest;
  _ok('已安装 id=${installed.id} kernelId=${installed.kernelId}');
  _info('类型=${manifest.type} 引擎=${manifest.engine.name} 版本=${manifest.version}'
      '${manifest.engineVersion == null ? '' : ' 引擎版本=${manifest.engineVersion}'}');
  _check(
    File(p.join(installed.directory.path, kKernelManifestEntry)).existsSync(),
    '安装目录根部存在 $kKernelManifestEntry',
  );

  switch (manifest.type) {
    case 'ffi':
      final declared = _declaredFromMap(manifest.libraries);
      _check(declared.isNotEmpty, 'ffi 内核声明了平台产物');
      _info('清单声明 ${declared.length} 个平台/ABI 产物');
      for (final lib in declared) {
        final f = installed.resolveFile(lib.relative);
        _check(f.existsSync(), '${lib.label} -> ${lib.relative}'
            '${f.existsSync() ? '（${f.lengthSync()} 字节）' : '（缺失！）'}');
        _check(installed.availableOn(lib.platform, abi: lib.abi),
            '${lib.label} 经 availableOn 判定为可用');
      }
      break;
    case 'webview2_fixed':
      _verifyWebview2Kernel(installed);
      break;
    case 'engine_adapter':
      _verifyEngineAdapterKernel(installed);
      break;
    default:
      _info('未知内核类型 "${manifest.type}"，只做通用检查');
      for (final lib in _declaredFromMap(manifest.libraries)) {
        _check(installed.resolveFile(lib.relative).existsSync(),
            '${lib.label} -> ${lib.relative}');
      }
  }

  // 显式要求的平台（例如 lite 内核必须同时具备 windows/linux/android×3）
  for (final spec in _requiredPlatforms) {
    final parts = spec.split('/');
    final platform = parts.first;
    final abi = parts.length > 1 ? parts[1] : null;
    _check(installed.availableOn(platform, abi: abi), '要求平台可用：$spec');
  }

  final reloaded = InstalledKernel.load(installed.directory);
  _check(reloaded != null, '安装目录可被 InstalledKernel.load 重新读取');
  if (reloaded != null) {
    _check(!reloaded.isTampered, '重载后指纹一致（未被篡改）');
    _check(reloaded.manifest.type == manifest.type, '重载后类型一致（${reloaded.manifest.type}）');
  }
}

/// 一个 zip 里是否有插件/内核清单，即它是不是一个「可安装的包」。
///
/// CI 上传的 artifact 里混着两类 zip：一类是真正的包（`lite_kernel.zip`），
/// 另一类是 artifact 容器（`kernel-windows-dll.zip` 里只有
/// `lite_kernel/kernels/windows/...`）。后者根本不是包，把它当失败报出来
/// 只会掩盖真正的问题 —— 所以显式跳过它，并说明为什么跳过。
bool _looksInstallable(File f) {
  try {
    final archive = ZipDecoder().decodeBytes(f.readAsBytesSync());
    for (final e in archive.files) {
      if (!e.isFile) continue;
      final name = e.name.replaceAll('\\', '/');
      if (name == 'manifest.json' || name.endsWith('/manifest.json')) {
        return true;
      }
      if (name == kKernelManifestEntry ||
          name.endsWith('/$kKernelManifestEntry')) {
        return true;
      }
    }
    return false;
  } catch (_) {
    // 解不开就交给后面的安装流程去报错，别在这里把真正的坏包吞掉。
    return true;
  }
}

List<File> _collect(List<String> args) {
  final files = <File>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--strict-runtime') {
      _strictRuntime = true;
      continue;
    }
    if (arg == '--require-platforms') {
      if (i + 1 >= args.length) {
        stderr.writeln('--require-platforms 需要一个逗号分隔的平台列表');
        exit(2);
      }
      _requiredPlatforms = args[++i]
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      continue;
    }
    if (arg == '--dir') {
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
    final f = File(arg);
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
        '<包文件...> | --dir <目录> '
        '[--strict-runtime] [--require-platforms p1,p2/abi,...]');
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
      if (!_looksInstallable(f)) {
        _skipped.add(f.path);
        continue;
      }
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

  if (_skipped.isNotEmpty) {
    stdout.writeln('\n跳过 ${_skipped.length} 个不是安装包的文件'
        '（zip 内既无 manifest.json 也无 $kKernelManifestEntry，'
        '多为 CI 的 artifact 容器）：');
    for (final s in _skipped) {
      stdout.writeln('  - $s');
    }
  }

  stdout.writeln('\n共 $_checks 项校验，失败 $_failures 项');
  if (_failures == 0) {
    stdout.writeln('结论：全部打包产物均可被宿主正常安装');
  } else {
    stdout.writeln('结论：存在打包问题，需要修复');
  }
  exit(_failures == 0 ? 0 : 1);
}
