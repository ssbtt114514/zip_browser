import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';

/// 检查更新：查询 GitHub Releases 最新版本并与当前版本比较。
class UpdateService {
  UpdateService._();

  static const _api =
      'https://api.github.com/repos/ssbtt114514/zip_browser/releases/latest';

  /// 检查结果；网络失败抛异常，[null] 表示已是最新。
  static Future<UpdateInfo?> check() async {
    final resp = await http.get(
      Uri.parse(_api),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'zip-browser-updater',
      },
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('GitHub API 返回 ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final info = UpdateInfo(
      tagName: (data['tag_name'] as String?) ?? '',
      htmlUrl: (data['html_url'] as String?) ?? '',
      notes: (data['body'] as String?) ?? '',
    );
    if (!info.isNewerThan(BrowserConstants.appVersion)) return null;
    return info;
  }
}

class UpdateInfo {
  final String tagName;
  final String htmlUrl;
  final String notes;

  UpdateInfo({required this.tagName, required this.htmlUrl, required this.notes});

  String get version => tagName.replaceFirst(RegExp(r'^v'), '');
  String get windowsSetupUrl =>
      'https://github.com/ssbtt114514/zip_browser/releases/download/'
      '$tagName/zip-browser-windows-x64-setup.exe';
  String get androidApkUrl =>
      'https://github.com/ssbtt114514/zip_browser/releases/download/'
      '$tagName/zip-browser-android-arm64-v8a.apk';

  /// 语义化版本比较：1.2.10 > 1.2.9 > 1.2.9+1 之类
  bool isNewerThan(String current) {
    List<int> parse(String v) => v
        .split('+')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final a = parse(version);
    final b = parse(current);
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return a.length > b.length;
  }
}
