import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/build_flavor.dart';
import 'config_service.dart';
import 'downloads_service.dart';
import 'history_service.dart';
import 'bookmarks_service.dart';

/// 用户数据导出 / 导入（JSON 快照）。
///
/// 包含：全部设置项（SharedPreferences）+ 书签 / 历史 / 下载记录的原始 JSON。
/// 导出文件名：zip-browser-backup-YYYYMMDD-HHMMSS.json
class DataExportService {
  DataExportService._();

  static const _services = {
    'bookmarks': 'bookmarks.json',
    'history': 'history.json',
    'downloads': 'downloads.json',
  };

  /// 组装快照
  static Map<String, dynamic> buildSnapshot(
    ConfigService config, {
    BookmarksService? bookmarks,
    HistoryService? history,
    DownloadsService? downloads,
  }) {
    String? readService(File? f) {
      try {
        return f?.existsSync() == true ? f!.readAsStringSync() : null;
      } catch (_) {
        return null;
      }
    }

    return {
      'meta': {
        'app': 'zip_browser',
        'version': '1',
        'flavor': BuildFlavorInfo.current.name,
        'exportedAt': DateTime.now().toIso8601String(),
      },
      'prefs': config.prefs.getKeys(),
      if (bookmarks != null)
        'files.bookmarks':
            readService(bookmarks.file),
      if (history != null)
        'files.history': readService(history.file),
      if (downloads != null)
        'files.downloads': readService(downloads.file),
    };
  }

  static String _fileName() {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'zip-browser-backup-'
        '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}'
        '.json';
  }

  /// 导出：桌面端弹保存对话框；移动端走系统分享。
  /// 返回提示文案。
  static Future<String> export(
    ConfigService config, {
    BookmarksService? bookmarks,
    HistoryService? history,
    DownloadsService? downloads,
    Directory? tempDir,
  }) async {
    final jsonText =
        const JsonEncoder.withIndent('  ').convert(buildSnapshot(config,
            bookmarks: bookmarks, history: history, downloads: downloads));
    final bytes = utf8.encode(jsonText);
    final name = _fileName();

    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      final dir = tempDir ??
          Directory.systemTemp;
      final f = File(p.join(dir.path, name));
      await f.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path)],
        text: 'Zip Browser 数据备份',
      ));
      return '已通过系统分享导出：$name';
    }

    final save = await FilePicker.platform.saveFile(
      fileName: name,
      bytes: bytes,
    );
    if (save == null) return '已取消导出';
    return '已导出到：$save';
  }

  /// 导入：选择备份文件并恢复（重启后全部生效）。
  static Future<String> import(
    ConfigService config, {
    required Directory profilesDir,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final pickedFile = picked?.files.single;
    if (pickedFile == null) return '已取消导入';
    final data = pickedFile.bytes;
    Map<String, dynamic> snapshot;
    if (data != null && data.isNotEmpty) {
      snapshot = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } else {
      final path = pickedFile.path;
      if (path == null) return '导入失败：无法读取文件';
      snapshot =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    }
    if (snapshot['meta']?['app'] != 'zip_browser') {
      return '导入失败：不是 Zip Browser 的备份文件';
    }

    var restored = 0;
    // 1) 文件类数据（书签 / 历史 / 下载）
    for (final entry in _services.entries) {
      final content = snapshot['files.${entry.key}'];
      if (content is! String || content.isEmpty) continue;
      File(p.join(profilesDir.path, entry.value)).writeAsStringSync(content);
      restored++;
    }
    // 2) 设置项（按 key 类型写回）
    final prefsData = snapshot['prefs'];
    if (prefsData is Map) {
      for (final e in prefsData.entries) {
        final v = e.value;
        try {
          if (v is bool) {
            await config.prefs.setBool(e.key, v);
          } else if (v is int) {
            await config.prefs.setInt(e.key, v);
          } else if (v is double) {
            await config.prefs.setDouble(e.key, v);
          } else if (v is String) {
            await config.prefs.setString(e.key, v);
          } else if (v is List) {
            await config.prefs
                .setStringList(e.key, v.map((x) => x.toString()).toList());
          }
        } catch (_) {}
      }
      restored++;
    }
    return restored == 0 ? '备份中没有可恢复的数据' : '已恢复 $restored 类数据，重启应用后生效';
  }
}
