import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 历史记录条目
class HistoryEntry {
  String url;
  String title;
  DateTime visited;
  int visits;

  HistoryEntry({
    required this.url,
    required this.title,
    required this.visited,
    this.visits = 1,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'visited': visited.toIso8601String(),
        'visits': visits,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      visited: DateTime.tryParse(json['visited'] as String? ?? '') ?? DateTime.now(),
      visits: json['visits'] as int? ?? 1,
    );
  }
}

/// 一天的分组
class HistoryDayGroup {
  final DateTime day;
  final List<HistoryEntry> entries;
  const HistoryDayGroup(this.day, this.entries);
}

/// 历史服务
class HistoryService extends ChangeNotifier {
  final File file;

  /// 最多保留条目数
  final int maxEntries;
  final List<HistoryEntry> _entries = [];

  HistoryService(this.file, {this.maxEntries = 5000});

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  void load() {
    _entries.clear();
    if (!file.existsSync()) return;
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      for (final e in list) {
        if (e is Map) {
          _entries.add(HistoryEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    } catch (_) {}
    _entries.sort((a, b) => b.visited.compareTo(a.visited));
  }

  /// 记录一次访问（同 URL 合并）
  void recordVisit(String url, String title) {
    if (url.startsWith('data:') || url.startsWith('about:')) return;
    final now = DateTime.now();
    for (final e in _entries) {
      if (e.url == url) {
        e.visits += 1;
        e.visited = now;
        if (title.isNotEmpty) e.title = title;
        _sortAndFlush();
        return;
      }
    }
    _entries.add(HistoryEntry(url: url, title: title.isEmpty ? url : title, visited: now));
    _sortAndFlush();
  }

  void _sortAndFlush() {
    _entries.sort((a, b) => b.visited.compareTo(a.visited));
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    _flush();
    notifyListeners();
  }

  void remove(HistoryEntry entry) {
    _entries.removeWhere((e) => e.url == entry.url);
    _flush();
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _flush();
    notifyListeners();
  }

  List<HistoryEntry> search(String query) {
    final q = query.toLowerCase();
    return _entries
        .where((e) =>
            e.title.toLowerCase().contains(q) || e.url.toLowerCase().contains(q))
        .toList();
  }

  /// 按天分组（最新在前）
  List<HistoryDayGroup> grouped({List<HistoryEntry>? source}) {
    final list = source ?? _entries;
    final map = <String, List<HistoryEntry>>{};
    for (final e in list) {
      final key =
          '${e.visited.year}-${e.visited.month}-${e.visited.day}';
      map.putIfAbsent(key, () => []).add(e);
    }
    final groups = map.entries.map((kv) {
      final first = kv.value.first.visited;
      return HistoryDayGroup(
        DateTime(first.year, first.month, first.day),
        kv.value,
      );
    }).toList();
    groups.sort((a, b) => b.day.compareTo(a.day));
    return groups;
  }

  void _flush() {
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(
        _entries.map((e) => e.toJson()).toList(),
      ),
    );
  }
}
