import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全局字体管理。
///
/// * 内置字体：OPPO Sans（assets 打包，pubspec 声明后随主题直接可用）；
/// * 自定义字体：用户从本地导入 .ttf/.otf → 复制到应用支持目录 →
///   运行时用 [FontLoader] 注册固定族名 [kCustomFamily] → 主题引用该族名。
///
/// 由于 [FontLoader] 注册的是全局字体表，注册后只要主题重建
/// （AppearanceSettings 通知）即可全 App 生效，无需重启。
class FontService {
  /// 内置 OPPO Sans 族名（pubspec fonts 声明的 family）
  static const String kBuiltInFamily = 'OPPO Sans';

  /// 系统默认字体（不指定族名）
  static const String kSystemFamily = '';

  /// 导入的自定义字体固定注册族名
  static const String kCustomFamily = 'ZipCustomFont';

  /// 是否已注册过自定义字体（防止重复注册）
  static bool _customRegistered = false;

  /// 应用支持目录下保存自定义字体的子目录
  static String get _fontsDirName => 'fonts';

  /// 启动时加载已导入的自定义字体（幂等）。
  ///
  /// 复制文件时不保留源文件名：统一命名为 custom.ttf / custom.otf，
  /// 保证每次导入只有一份生效、配置里的族名恒定。
  static Future<void> loadInstalledCustomFont() async {
    if (_customRegistered) return;
    final dir = await getApplicationSupportDirectory();
    final fontsDir = p.join(dir.path, _fontsDirName);
    final file = Directory(fontsDir).existsSync()
        ? (File(p.join(fontsDir, 'custom.ttf')).existsSync()
            ? File(p.join(fontsDir, 'custom.ttf'))
            : File(p.join(fontsDir, 'custom.otf')))
        : null;
    if (file == null || !file.existsSync()) return;

    final bytes = await file.readAsBytes();
    await _register(bytes);
  }

  /// 导入自定义字体：把 [srcPath] 复制进应用目录并注册。
  ///
  /// 返回注册后的族名 [kCustomFamily]；失败抛异常（调用方提示用户）。
  static Future<String> importFont(String srcPath) async {
    final src = File(srcPath);
    if (!src.existsSync()) {
      throw Exception('字体文件不存在：$srcPath');
    }
    final ext = p.extension(srcPath).toLowerCase();
    if (ext != '.ttf' && ext != '.otf') {
      throw Exception('仅支持 .ttf / .otf 字体文件');
    }

    final dir = await getApplicationSupportDirectory();
    final fontsDir = Directory(p.join(dir.path, _fontsDirName));
    if (!fontsDir.existsSync()) fontsDir.createSync(recursive: true);

    // 统一命名，旧的导入直接覆盖
    final target = File(p.join(fontsDir.path, 'custom$ext'));
    await src.copy(target.path);

    final bytes = await target.readAsBytes();
    await _register(bytes);
    return kCustomFamily;
  }

  /// 移除自定义字体（恢复内置/系统字体时调用，可选）
  static Future<void> removeCustomFont() async {
    final dir = await getApplicationSupportDirectory();
    final fontsDir = Directory(p.join(dir.path, _fontsDirName));
    if (fontsDir.existsSync()) {
      await fontsDir.delete(recursive: true);
    }
  }

  static Future<void> _register(Uint8List bytes) async {
    final loader = FontLoader(kCustomFamily)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _customRegistered = true;
  }
}
