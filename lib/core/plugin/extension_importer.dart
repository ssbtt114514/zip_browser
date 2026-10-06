import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// 浏览器扩展导入器：将 Chrome(.crx) / Firefox(.xpi) 扩展包
/// 转换为本浏览器可安装的 zip 插件字节流。
///
/// * CRX 为 zip 前置了签名头，需要剥离头部；
/// * XPI 本身就是 zip；
/// * 两者 manifest 均转换为本宿主清单 schema。
class ExtensionImporter {
  const ExtensionImporter._();

  /// 从 .crx 字节导入，返回可安装的 zip 字节
  static List<int> fromCrx(List<int> bytes) {
    final zipBytes = _stripCrxHeader(bytes);
    return _convertExtension(zipBytes, source: 'chromium');
  }

  /// 从 .xpi 字节导入，返回可安装的 zip 字节
  static List<int> fromXpi(List<int> bytes) {
    return _convertExtension(bytes, source: 'gecko');
  }

  /// 智能识别：依据魔数判断 crx / xpi。
  static List<int> autoImport(List<int> bytes) {
    if (bytes.length > 4 &&
        bytes[0] == 0x43 && // 'C'
        bytes[1] == 0x72 && // 'r'
        bytes[2] == 0x32 && // '2'
        bytes[3] == 0x34) {
      return fromCrx(bytes);
    }
    return fromXpi(bytes);
  }

  /// 剥离 CRX2 / CRX3 头部，返回内嵌 zip 字节
  static List<int> _stripCrxHeader(List<int> bytes) {
    if (bytes.length < 12) {
      throw const FormatException('CRX 文件过小');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'Cr24') {
      throw const FormatException('不是合法的 CRX 文件（缺少 Cr24 魔数）');
    }
    final version = data.getUint32(4, Endian.little);
    int zipStart;
    if (version == 2) {
      final pubKeyLen = data.getUint32(8, Endian.little);
      final sigLen = data.getUint32(12, Endian.little);
      zipStart = 16 + pubKeyLen + sigLen;
    } else if (version == 3) {
      final headerSize = data.getUint32(8, Endian.little);
      zipStart = 12 + headerSize;
    } else {
      throw FormatException('不支持的 CRX 版本：$version');
    }
    if (zipStart >= bytes.length) {
      throw const FormatException('CRX 头部损坏');
    }
    return bytes.sublist(zipStart);
  }

  /// 解析扩展 zip，转换 manifest 后重新打包
  static List<int> _convertExtension(List<int> zipBytes, {required String source}) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw FormatException('无法解压扩展包：$e');
    }

    // 定位 manifest.json
    ArchiveFile? manifestEntry;
    String prefix = '';
    for (final f in archive.files) {
      if (f.isFile && _base(f.name) == 'manifest.json') {
        manifestEntry = f;
        prefix = _rootPrefix(f.name);
        break;
      }
    }
    if (manifestEntry == null) {
      throw const FormatException('扩展包内未找到 manifest.json');
    }

    final Map<String, dynamic> src;
    try {
      src = jsonDecode(utf8.decode(manifestEntry.content as List<int>))
          as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('manifest.json 解析失败：$e');
    }

    final normalized = _normalizeManifest(src, source: source);

    // 重建 zip
    final out = Archive();
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name;
      if (_base(name) == 'manifest.json' && _rootPrefix(name) == prefix) {
        continue; // 用规范化后的 manifest 替换
      }
      final rel = _stripPrefix(name, prefix);
      if (rel.isEmpty) continue;
      out.addFile(ArchiveFile(
        rel,
        (f.content as List<int>).length,
        f.content as List<int>,
      ));
    }
    final manifestBytes = utf8.encode(jsonEncode(normalized));
    out.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    final encoded = ZipEncoder().encode(out);
    if (encoded == null) {
      throw const FormatException('重新打包扩展失败');
    }
    return encoded;
  }

  /// 将 Chrome/Firefox manifest 转换为本宿主清单
  static Map<String, dynamic> _normalizeManifest(
    Map<String, dynamic> src, {
    required String source,
  }) {
    final name = (src['name'] as String?) ?? 'extension';
    final version = (src['version'] as String?) ?? '1.0.0';

    // 生成稳定的反向域名 id
    final id = 'ext.${_slug(name)}.${_shortHash(jsonEncode(src))}';

    // background：兼容 MV2 scripts / MV3 service_worker / Firefox scripts / page
    final bgRaw = src['background'];
    Map<String, dynamic>? background;
    if (bgRaw is Map) {
      final scripts = <String>[];
      if (bgRaw['scripts'] is List) {
        scripts.addAll((bgRaw['scripts'] as List).whereType<String>());
      }
      if (bgRaw['service_worker'] is String) {
        scripts.add(bgRaw['service_worker'] as String);
      }
      final page = bgRaw['page'] as String?;
      if (scripts.isNotEmpty || page != null) {
        background = {
          'js': scripts,
          if (page != null) 'page': page,
        };
      }
    }

    // content_scripts 基本兼容，仅将 run_at 透传
    final cs = src['content_scripts'];

    return {
      'manifest_version': 1,
      'id': id,
      'name': name,
      'version': version,
      if (src['description'] != null) 'description': src['description'],
      if (src['author'] != null) 'author': src['author'],
      if (src['homepage_url'] != null) 'homepage': src['homepage_url'],
      'source': source,
      'permissions': _mapPermissions(src['permissions']),
      'host_permissions': _collectHostPermissions(src),
      'web_accessible_resources': src['web_accessible_resources'] ?? const [],
      'content_scripts': cs ?? const [],
      if (background != null) 'background': background,
    };
  }

  /// 将浏览器扩展权限映射到本宿主支持的权限集合
  static List<String> _mapPermissions(dynamic raw) {
    const supported = {
      'tabs',
      'storage',
      'webNavigation',
      'downloads',
      'nativeMessaging',
      'menus',
      'cookies',
      'notifications',
    };
    final out = <String>{};
    if (raw is List) {
      for (final p in raw.whereType<String>()) {
        if (supported.contains(p)) out.add(p);
      }
    }
    return out.toList();
  }

  /// 汇总 host_permissions（MV3）与 content_scripts.matches 中的站点范围
  static List<String> _collectHostPermissions(Map<String, dynamic> src) {
    final out = <String>{};
    final hp = src['host_permissions'];
    if (hp is List) out.addAll(hp.whereType<String>());
    return out.toList();
  }

  static String _base(String name) {
    final n = name.replaceAll('\\', '/');
    return n.endsWith('/') ? '' : n.split('/').last;
  }

  static String _rootPrefix(String manifestName) {
    final n = manifestName.replaceAll('\\', '/');
    final idx = n.indexOf('manifest.json');
    return idx <= 0 ? '' : n.substring(0, idx);
  }

  static String _stripPrefix(String name, String prefix) {
    final n = name.replaceAll('\\', '/');
    if (prefix.isNotEmpty && n.startsWith(prefix)) {
      return n.substring(prefix.length);
    }
    return n;
  }

  static String _slug(String s) {
    final lower = s.toLowerCase();
    final replaced = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final trimmed = replaced.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'unamed' : trimmed;
  }

  static String _shortHash(String s) {
    return sha256.convert(utf8.encode(s)).toString().substring(0, 8);
  }
}
