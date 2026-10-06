import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 书签条目
class Bookmark {
  final String id;
  String title;
  String url;
  final DateTime added;

  Bookmark({
    required this.id,
    required this.title,
    required this.url,
    required this.added,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'added': added.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'].toString(),
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      added: DateTime.tryParse(json['added'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 书签服务（JSON 持久化）
class BookmarksService extends ChangeNotifier {
  final File file;
  final List<Bookmark> _items = [];
  int _seq = 0;

  BookmarksService(this.file);

  List<Bookmark> get items => List.unmodifiable(_items);

  void load() {
    _items.clear();
    if (!file.existsSync()) return;
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      for (final e in list) {
        if (e is Map) _items.add(Bookmark.fromJson(Map<String, dynamic>.from(e)));
      }
    } catch (_) {}
    if (_items.isNotEmpty) {
      _seq = _items
              .map((e) => int.tryParse(e.id) ?? 0)
              .reduce((a, b) => a > b ? a : b) +
          1;
    }
  }

  bool isBookmarked(String url) => _items.any((e) => e.url == url);

  Bookmark? byUrl(String url) {
    for (final b in _items) {
      if (b.url == url) return b;
    }
    return null;
  }

  Bookmark add({required String title, required String url}) {
    final existing = byUrl(url);
    if (existing != null) return existing;
    final bookmark = Bookmark(
      id: '${_seq++}',
      title: title.isEmpty ? url : title,
      url: url,
      added: DateTime.now(),
    );
    _items.add(bookmark);
    _flush();
    notifyListeners();
    return bookmark;
  }

  void remove(String id) {
    _items.removeWhere((e) => e.id == id);
    _flush();
    notifyListeners();
  }

  void removeByUrl(String url) {
    final b = byUrl(url);
    if (b != null) remove(b.id);
  }

  void _flush() {
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_items.map((e) => e.toJson()).toList()),
    );
  }
}
