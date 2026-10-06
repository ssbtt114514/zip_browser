import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum DownloadStatus { pending, running, completed, failed, canceled }

/// 下载记录
class DownloadRecord {
  final String url;
  String filename;
  String? filePath;
  int totalBytes;
  int receivedBytes;
  DownloadStatus status;
  final DateTime started;
  String? error;

  DownloadRecord({
    required this.url,
    required this.filename,
    this.filePath,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.status = DownloadStatus.pending,
    required this.started,
    this.error,
  });

  double? get progress =>
      totalBytes > 0 ? receivedBytes / totalBytes : null;

  Map<String, dynamic> toJson() => {
        'url': url,
        'filename': filename,
        'file_path': filePath,
        'total': totalBytes,
        'received': receivedBytes,
        'status': status.name,
        'started': started.toIso8601String(),
        'error': error,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) {
    return DownloadRecord(
      url: json['url'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      filePath: json['file_path'] as String?,
      totalBytes: json['total'] as int? ?? 0,
      receivedBytes: json['received'] as int? ?? 0,
      status: DownloadStatus.values.asNameMap()[json['status'] as String?] ??
          DownloadStatus.completed,
      started: DateTime.tryParse(json['started'] as String? ?? '') ?? DateTime.now(),
      error: json['error'] as String?,
    );
  }
}

/// 下载服务
class DownloadsService extends ChangeNotifier {
  final File file;
  final List<DownloadRecord> _items = [];

  DownloadsService(this.file);

  List<DownloadRecord> get items => List.unmodifiable(_items);

  void load() {
    _items.clear();
    if (!file.existsSync()) return;
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      for (final e in list) {
        if (e is Map) {
          _items.add(DownloadRecord.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    } catch (_) {}
    _items.sort((a, b) => b.started.compareTo(a.started));
  }

  DownloadRecord start({required String url, required String filename}) {
    final record = DownloadRecord(
      url: url,
      filename: filename,
      status: DownloadStatus.running,
      started: DateTime.now(),
    );
    _items.insert(0, record);
    _flush();
    notifyListeners();
    return record;
  }

  void updateProgress(DownloadRecord record, {int? received, int? total}) {
    if (received != null) record.receivedBytes = received;
    if (total != null) record.totalBytes = total;
    record.status = DownloadStatus.running;
    _flush();
    notifyListeners();
  }

  void complete(DownloadRecord record, String filePath) {
    record.filePath = filePath;
    record.status = DownloadStatus.completed;
    record.receivedBytes = record.totalBytes > 0
        ? record.totalBytes
        : record.receivedBytes;
    _flush();
    notifyListeners();
  }

  void fail(DownloadRecord record, String error) {
    record.status = DownloadStatus.failed;
    record.error = error;
    _flush();
    notifyListeners();
  }

  void remove(DownloadRecord record) {
    _items.remove(record);
    _flush();
    notifyListeners();
  }

  /// 清除所有已完成的下载记录
  void clearCompleted() {
    _items.removeWhere((r) => r.status == DownloadStatus.completed);
    _flush();
    notifyListeners();
  }

  void _flush() {
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(
        _items.map((e) => e.toJson()).toList(),
      ),
    );
  }
}
