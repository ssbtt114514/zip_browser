import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'plugin_manifest.dart';
import 'plugin_security.dart';

/// 安装异常
class PluginInstallException implements Exception {
  final List<String> reasons;
  PluginInstallException(this.reasons);
  @override
  String toString() => '插件安装失败：\n  - ${reasons.join('\n  - ')}';
}

/// 一条已安装插件记录
class InstalledPlugin {
  final PluginManifest manifest;
  final Directory directory;
  final String zipSha256;
  final String fingerprint;
  final DateTime installedAt;
  bool enabled;

  InstalledPlugin({
    required this.manifest,
    required this.directory,
    required this.zipSha256,
    required this.fingerprint,
    required this.installedAt,
    required this.enabled,
  });

  String get id => manifest.id;

  File resolveFile(String relative) =>
      File(p.join(directory.path, relative.replaceAll('/', p.separator)));

  Map<String, dynamic> installRecordJson() => {
        'id': manifest.id,
        'name': manifest.name,
        'version': manifest.version,
        'zip_sha256': zipSha256,
        'fingerprint': fingerprint,
        'installed_at': installedAt.toIso8601String(),
        'enabled': enabled,
      };

  /// 从已安装目录加载；损坏 / 被篡改时返回 null（[tampered] 置 true）
  static InstalledPlugin? load(Directory dir, {bool tampered = false}) {
    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    final recordFile = File(p.join(dir.path, 'install.json'));
    if (!manifestFile.existsSync() || !recordFile.existsSync()) return null;

    final manifest = PluginManifest.fromJson(
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>,
    );
    if (manifest.validationErrors.isNotEmpty) return null;

    final record = jsonDecode(recordFile.readAsStringSync()) as Map<String, dynamic>;

    final expectedFingerprint = record['fingerprint'] as String?;
    final actualFingerprint = PluginSecurity.directoryFingerprint(dir);
    final isTampered = expectedFingerprint != actualFingerprint;

    return InstalledPlugin(
      manifest: manifest,
      directory: dir,
      zipSha256: record['zip_sha256'] as String? ?? '',
      fingerprint: actualFingerprint,
      installedAt: DateTime.tryParse(record['installed_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      enabled: record['enabled'] as bool? ?? true,
    ).._tampered = isTampered;
  }

  bool _tampered = false;

  /// 目录内容与安装时不一致（可能被篡改）
  bool get isTampered => _tampered;
}

/// zip 插件包安装器
class PluginPackage {
  const PluginPackage._();

  /// 从 zip 字节流安装（会先做全部校验，再原子落盘）
  static InstalledPlugin install({
    required List<int> zipBytes,
    required Directory pluginsDir,
    TrustedPlugins? trusted,
  }) {
    final errors = <String>[];

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw PluginInstallException(['不是合法的 zip 文件：$e']);
    }

    // 1. 定位 manifest.json（允许压缩时多包一层同名目录）
    ArchiveFile? manifestEntry;
    for (final f in archive.files) {
      if (f.isFile && _baseNormalized(f.name) == 'manifest.json') {
        manifestEntry = f;
        break;
      }
    }
    if (manifestEntry == null) {
      throw PluginInstallException(['压缩包内未找到 manifest.json']);
    }

    // 2. 解析并校验清单
    final manifest = PluginManifest.fromJson(
      jsonDecode(utf8.decode(manifestEntry.content as List<int>))
          as Map<String, dynamic>,
    );
    errors.addAll(manifest.validationErrors);
    if (errors.isNotEmpty) throw PluginInstallException(errors);

    // 3. zip 路径安全检查（防 Zip Slip：../、绝对路径、盘符）
    final prefix = _rootPrefix(manifestEntry.name);
    for (final f in archive.files) {
      final rel = _stripPrefix(f.name, prefix);
      if (rel.isEmpty) continue;
      if (rel.contains('..') ||
          p.isAbsolute(rel) ||
          RegExp(r'^[a-zA-Z]:').hasMatch(rel)) {
        throw PluginInstallException(['压缩包含非法路径：${f.name}']);
      }
    }

    // 4. 指纹与白名单
    final zipHash = PluginSecurity.sha256OfBytes(zipBytes);
    if (trusted != null &&
        !trusted.isEmpty &&
        !trusted.isTrusted(manifest.id, zipHash)) {
      throw PluginInstallException([
        '插件 ${manifest.id}（$zipHash）不在受信任白名单中',
      ]);
    }

    // 5. 原子解压到 pluginsDir/<id>
    if (!pluginsDir.existsSync()) pluginsDir.createSync(recursive: true);
    final target = Directory(p.join(pluginsDir.path, manifest.id));
    final staging = Directory(p.join(pluginsDir.path, '.${manifest.id}.tmp'));
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

    final record = InstalledPlugin(
      manifest: manifest,
      directory: target,
      zipSha256: zipHash,
      fingerprint: fingerprint,
      installedAt: DateTime.now(),
      enabled: true,
    );
    File(p.join(target.path, 'install.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(
      record.installRecordJson(),
    ));

    return record;
  }

  static String _baseNormalized(String name) {
    final normalized = name.replaceAll('\\', '/');
    return normalized.endsWith('/') ? '' : normalized.split('/').last;
  }

  static String _rootPrefix(String manifestName) {
    final normalized = manifestName.replaceAll('\\', '/');
    final idx = normalized.indexOf('manifest.json');
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
