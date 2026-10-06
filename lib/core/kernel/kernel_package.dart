import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../plugin/plugin_security.dart';
import 'kernel_manifest.dart';

/// 宿主支持的 FFI 内核 ABI 版本
const int kSupportedKernelAbiVersion = 1;

/// 内核包清单在包内的文件名
const String kKernelManifestEntry = 'kernel.json';

/// 内核包安装异常
class KernelInstallException implements Exception {
  final List<String> reasons;
  KernelInstallException(this.reasons);
  @override
  String toString() => '内核包安装失败：\n  - ${reasons.join('\n  - ')}';
}

/// 一个已安装的独立内核包
class InstalledKernel {
  final KernelManifest manifest;
  final Directory directory;
  final String zipSha256;
  final String fingerprint;
  final DateTime installedAt;

  InstalledKernel({
    required this.manifest,
    required this.directory,
    required this.zipSha256,
    required this.fingerprint,
    required this.installedAt,
  });

  String get id => manifest.id;

  /// 宿主内使用的内核 id
  String get kernelId => 'kernel.${manifest.id}';

  bool _tampered = false;

  /// 目录内容与安装时不一致（可能被篡改）
  bool get isTampered => _tampered;

  File resolveFile(String relative) =>
      File(p.join(directory.path, relative.replaceAll('/', p.separator)));

  /// 当前平台可用的原生库绝对路径
  String? libraryPathFor(String platform, {String? abi}) {
    final rel = manifest.libraryRelativeFor(platform, abi: abi);
    if (rel == null) return null;
    final f = resolveFile(rel);
    return f.existsSync() ? f.path : null;
  }

  /// Fixed Version 运行时目录绝对路径
  String? get runtimeDirPath {
    final rel = manifest.runtimeDir;
    if (rel == null) return null;
    final d = Directory(p.join(directory.path, rel.replaceAll('/', p.separator)));
    return d.existsSync() ? d.path : null;
  }

  /// 在指定平台上是否可用（声明且产物存在）
  ///
  /// `engine_adapter` 不携带平台产物，在所有平台都返回 true：能否真正渲染
  /// 由运行时的引擎探测结果决定，本方法只回答"能不能装/能不能选"。
  bool availableOn(String platform, {String? abi}) {
    if (manifest.type == 'engine_adapter') return true;
    if (manifest.type == 'webview2_fixed') {
      return platform == 'windows' && runtimeDirPath != null;
    }
    return libraryPathFor(platform, abi: abi) != null;
  }

  /// 包占用字节数
  int get sizeBytes {
    var total = 0;
    if (!directory.existsSync()) return 0;
    for (final e in directory.listSync(recursive: true)) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  Map<String, dynamic> installRecordJson() => {
        'id': manifest.id,
        'name': manifest.name,
        'version': manifest.version,
        'engine': manifest.engine.name,
        'type': manifest.type,
        'zip_sha256': zipSha256,
        'fingerprint': fingerprint,
        'installed_at': installedAt.toIso8601String(),
      };

  /// 从已安装目录加载；缺失或损坏时返回 null
  static InstalledKernel? load(Directory dir) {
    final manifestFile = File(p.join(dir.path, kKernelManifestEntry));
    final recordFile = File(p.join(dir.path, 'install.json'));
    if (!manifestFile.existsSync() || !recordFile.existsSync()) return null;

    KernelManifest manifest;
    try {
      manifest = KernelManifest.fromJson(
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
    if (manifest.validationErrors.isNotEmpty) return null;

    Map<String, dynamic> record;
    try {
      record = jsonDecode(recordFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final expectedFingerprint = record['fingerprint'] as String?;
    final actualFingerprint = PluginSecurity.directoryFingerprint(dir);

    return InstalledKernel(
      manifest: manifest,
      directory: dir,
      zipSha256: record['zip_sha256'] as String? ?? '',
      fingerprint: actualFingerprint,
      installedAt: DateTime.tryParse(record['installed_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    ).._tampered = expectedFingerprint != actualFingerprint;
  }
}

/// 独立内核包（.zbk / zip）安装器
class KernelPackage {
  const KernelPackage._();

  /// 从 zip 字节流安装（先全量校验，再原子落盘）
  static InstalledKernel install({
    required List<int> zipBytes,
    required Directory kernelsDir,
    TrustedPlugins? trusted,
  }) {
    final errors = <String>[];

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw KernelInstallException(['不是合法的内核包（zip 解析失败）：$e']);
    }

    // 1. 定位 kernel.json（允许包一层同名目录）
    ArchiveFile? manifestEntry;
    for (final f in archive.files) {
      if (f.isFile && _baseName(f.name) == kKernelManifestEntry) {
        manifestEntry = f;
        break;
      }
    }
    if (manifestEntry == null) {
      throw KernelInstallException(['内核包内未找到 $kKernelManifestEntry']);
    }

    // 2. 解析并校验清单
    KernelManifest manifest;
    try {
      manifest = KernelManifest.fromJson(
        jsonDecode(utf8.decode(manifestEntry.content as List<int>))
            as Map<String, dynamic>,
      );
    } catch (e) {
      throw KernelInstallException(['$kKernelManifestEntry 解析失败：$e']);
    }
    errors.addAll(manifest.validationErrors);
    if (errors.isEmpty) {
      if (manifest.abiVersion != kSupportedKernelAbiVersion) {
        errors.add(
          '内核 ABI 版本 ${manifest.abiVersion} 与宿主支持的 $kSupportedKernelAbiVersion 不匹配',
        );
      }
      // engine_adapter 是适配器：不携带 libraries / runtime_dir 属正常情况，
      // 其余类型仍必须声明至少一项平台产物。
      final adapter = manifest.type == 'engine_adapter';
      if (!adapter &&
          manifest.libraries.isEmpty &&
          !(manifest.type == 'webview2_fixed' &&
              (manifest.runtimeDir?.isNotEmpty ?? false))) {
        errors.add('清单未声明任何平台产物（libraries / runtime_dir 均为空）');
      }
    }
    if (errors.isNotEmpty) throw KernelInstallException(errors);

    // 3. zip 路径安全（防 Zip Slip）
    final prefix = _rootPrefix(manifestEntry.name);
    for (final f in archive.files) {
      final rel = _stripPrefix(f.name, prefix);
      if (rel.isEmpty) continue;
      if (rel.contains('..') ||
          p.isAbsolute(rel) ||
          RegExp(r'^[a-zA-Z]:').hasMatch(rel)) {
        throw KernelInstallException(['内核包含非法路径：${f.name}']);
      }
    }

    // 4. 指纹与白名单
    final zipHash = PluginSecurity.sha256OfBytes(zipBytes);
    if (trusted != null &&
        !trusted.isEmpty &&
        !trusted.isTrusted(manifest.id, zipHash)) {
      throw KernelInstallException([
        '内核 ${manifest.id}（$zipHash）不在受信任白名单中',
      ]);
    }

    // 5. 原子解压到 kernelsDir/<id>
    if (!kernelsDir.existsSync()) kernelsDir.createSync(recursive: true);
    final target = Directory(p.join(kernelsDir.path, manifest.id));
    final staging = Directory(p.join(kernelsDir.path, '.${manifest.id}.tmp'));
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);

    for (final f in archive.files) {
      final rel = _stripPrefix(f.name, prefix);
      if (rel.isEmpty) continue;
      final outFile = File(p.join(staging.path, rel.replaceAll('/', p.separator)));
      if (f.isFile) {
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(f.content as List<int>, flush: true);
      } else {
        outFile.createSync(recursive: true);
      }
    }

    final fingerprint = PluginSecurity.directoryFingerprint(staging);

    if (target.existsSync()) target.deleteSync(recursive: true);
    staging.renameSync(target.path);

    final record = InstalledKernel(
      manifest: manifest,
      directory: target,
      zipSha256: zipHash,
      fingerprint: fingerprint,
      installedAt: DateTime.now(),
    );
    File(p.join(target.path, 'install.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(
      record.installRecordJson(),
    ));

    return record;
  }

  static String _baseName(String name) {
    final normalized = name.replaceAll('\\', '/');
    return normalized.endsWith('/') ? '' : normalized.split('/').last;
  }

  static String _rootPrefix(String manifestName) {
    final normalized = manifestName.replaceAll('\\', '/');
    final idx = normalized.indexOf(kKernelManifestEntry);
    return idx <= 0 ? '' : normalized.substring(0, idx);
  }

  static String _stripPrefix(String name, String prefix) {
    final normalized = name.replaceAll('\\', '/');
    var rel = normalized;
    if (prefix.isNotEmpty && normalized.startsWith(prefix)) {
      rel = normalized.substring(prefix.length);
    }
    return rel;
  }
}
