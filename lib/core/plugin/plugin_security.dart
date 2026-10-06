import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 插件安全校验。
///
/// 当前提供：
///   1. zip 安装包 SHA-256 指纹（安装时记录，展示给用户确认）
///   2. 已安装目录文件清单哈希（启动时重算，发现被篡改则拒绝加载）
///   3. 受信任插件白名单（trusted_plugins.json：插件 id -> 允许的 sha256 列表）
///
/// 升级路径（见 ARCHITECTURE.md）：引入 pointycastle 做
/// RSASSA-PKCS1-v1_5 + SHA-256 签名验证（signature.sig）。
class PluginSecurity {
  const PluginSecurity._();

  static String sha256OfBytes(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  static String sha256OfFile(File file) {
    return sha256.convert(file.readAsBytesSync()).toString();
  }

  /// 计算插件目录的文件清单指纹（相对路径 + 单文件哈希，按路径排序）
  static String directoryFingerprint(Directory dir) {
    final files = <String>[];
    final entities = dir.listSync(recursive: true)..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entities) {
      if (entity is File) {
        final relative = entity.path.substring(dir.path.length + 1).replaceAll(r'\', '/');
        if (relative == 'install.json') continue; // 安装元数据不参与
        final digest = sha256.convert(entity.readAsBytesSync());
        files.add('$relative:$digest');
      }
    }
    return sha256.convert(utf8.encode(files.join('\n'))).toString();
  }
}

/// 受信任插件白名单
class TrustedPlugins {
  /// 插件 id -> 受信任的 zip sha256 集合
  final Map<String, Set<String>> entries;

  const TrustedPlugins(this.entries);

  factory TrustedPlugins.empty() => const TrustedPlugins({});

  /// 白名单为空表示“不强制白名单”（安装时仍展示指纹让用户确认）
  bool get isEmpty => entries.isEmpty;

  bool isTrusted(String pluginId, String zipHash) {
    final allowed = entries[pluginId];
    return allowed != null && allowed.contains(zipHash);
  }

  factory TrustedPlugins.fromJson(Map<String, dynamic> json) {
    final map = <String, Set<String>>{};
    json.forEach((key, value) {
      if (value is List) {
        map[key] = value.map((e) => e.toString()).toSet();
      }
    });
    return TrustedPlugins(map);
  }
}
