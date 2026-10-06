import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用目录约定
class AppPaths {
  static late Directory supportDir;
  static late Directory pluginsDir;

  /// 独立内核包（.zbk）安装目录
  static late Directory kernelsDir;

  static late Directory profilesDir;

  /// 浏览器下载文件目录
  static late Directory downloadsDir;

  /// 插件 zip 下载暂存
  static late Directory downloadCacheDir;

  /// 用户脚本（.user.js）存储目录
  static late Directory userscriptsDir;

  static Future<void> init() async {
    supportDir = await getApplicationSupportDirectory();
    pluginsDir = Directory(p.join(supportDir.path, 'plugins'))
      ..createSync(recursive: true);
    kernelsDir = Directory(p.join(supportDir.path, 'kernels'))
      ..createSync(recursive: true);
    profilesDir = Directory(p.join(supportDir.path, 'profiles', 'default'))
      ..createSync(recursive: true);
    downloadsDir = Directory(p.join(supportDir.path, 'downloads'))
      ..createSync(recursive: true);
    downloadCacheDir = Directory(p.join(supportDir.path, 'cache', 'downloads'))
      ..createSync(recursive: true);
    userscriptsDir = Directory(p.join(supportDir.path, 'userscripts'))
      ..createSync(recursive: true);
  }

  /// 当前平台键名（与 manifest kernel.libraries 的键对齐）
  static String get platformKey {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }
}
