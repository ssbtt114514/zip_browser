import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'downloads_service.dart';

/// 实际执行 HTTP 下载并同步 [DownloadsService]
class DownloadRunner {
  final DownloadsService service;
  final Directory downloadDir;

  DownloadRunner({required this.service, required this.downloadDir});

  Future<void> start(String url, {Map<String, String>? headers}) async {
    final initialName = _nameFromUrl(url);
    final record = service.start(url: url, filename: initialName);

    http.Client? client;
    try {
      if (!downloadDir.existsSync()) {
        downloadDir.createSync(recursive: true);
      }
      client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      // 附带请求头（Referer、Cookie 等）
      if (headers != null) {
        headers.forEach((k, v) => request.headers[k] = v);
      }
      final response = await client.send(request);

      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      // 优先使用 Content-Disposition 中的文件名
      final cdName = _nameFromContentDisposition(
        response.headers['content-disposition'],
      );
      if (cdName != null) record.filename = cdName;

      final total = response.contentLength ?? 0;
      service.updateProgress(record, received: 0, total: total);

      final file = File(p.join(downloadDir.path, _unique(record.filename)));
      final sink = file.openWrite();
      int received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        service.updateProgress(record, received: received, total: total);
      }
      await sink.flush();
      await sink.close();
      service.complete(record, file.path);
    } catch (e) {
      service.fail(record, e.toString());
    } finally {
      client?.close();
    }
  }

  static String _nameFromUrl(String url) {
    var path = Uri.tryParse(url)?.path ?? '';
    path = path.split('?').first;
    final seg = path.split('/').where((s) => s.isNotEmpty);
    if (seg.isEmpty) return 'download';
    try {
      return Uri.decodeComponent(seg.last);
    } catch (_) {
      return seg.last;
    }
  }

  static String? _nameFromContentDisposition(String? header) {
    if (header == null || header.isEmpty) return null;
    // filename*=UTF-8''xxx
    final star = RegExp(r"filename\*\s*=\s*([^']+)'([^']*)'(.+?)(?:;|$)",
        caseSensitive: false);
    final m = star.firstMatch(header);
    if (m != null) {
      try {
        return Uri.decodeComponent(m.group(3)!.trim().replaceAll('"', ''));
      } catch (_) {}
    }
    final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false);
    final m2 = plain.firstMatch(header);
    if (m2 != null) {
      final name = m2.group(1)!.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  String _unique(String name) {
    final candidate = p.join(downloadDir.path, name);
    if (!File(candidate).existsSync()) return name;
    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var i = 1;
    while (File(p.join(downloadDir.path, '$base($i)$ext')).existsSync()) {
      i++;
    }
    return '$base($i)$ext';
  }
}
