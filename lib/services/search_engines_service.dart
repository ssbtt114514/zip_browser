import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'config_service.dart';

/// 搜索引擎条目
class SearchEngine {
  final String id;
  final String name;
  final String urlTemplate; // 使用 {q} 占位
  final bool builtin;

  const SearchEngine({
    required this.id,
    required this.name,
    required this.urlTemplate,
    this.builtin = false,
  });

  /// 根据关键词生成搜索 URL
  String resolve(String query) {
    final encoded = Uri.encodeQueryComponent(query);
    return urlTemplate.replaceAll('{q}', encoded);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'urlTemplate': urlTemplate,
        'builtin': builtin,
      };

  factory SearchEngine.fromJson(Map<String, dynamic> json) => SearchEngine(
        id: json['id'] as String,
        name: json['name'] as String,
        urlTemplate: json['urlTemplate'] as String,
        builtin: json['builtin'] as bool? ?? false,
      );
}

/// 搜索引擎管理：内置预设 + 自定义，持久化到 ConfigService。
class SearchEnginesService extends ChangeNotifier {
  static const String _kEngines = 'search.engines';
  static const String _kDefault = 'search.default_id';

  static const List<SearchEngine> builtins = [
    SearchEngine(
      id: 'bing',
      name: 'Bing',
      urlTemplate: 'https://www.bing.com/search?q={q}',
      builtin: true,
    ),
    SearchEngine(
      id: 'google',
      name: 'Google',
      urlTemplate: 'https://www.google.com/search?q={q}',
      builtin: true,
    ),
    SearchEngine(
      id: 'duckduckgo',
      name: 'DuckDuckGo',
      urlTemplate: 'https://duckduckgo.com/?q={q}',
      builtin: true,
    ),
    SearchEngine(
      id: 'baidu',
      name: '百度',
      urlTemplate: 'https://www.baidu.com/s?wd={q}',
      builtin: true,
    ),
    SearchEngine(
      id: 'you',
      name: 'You',
      urlTemplate: 'https://you.com/search?q={q}',
      builtin: true,
    ),
  ];

  final ConfigService _config;
  List<SearchEngine> _engines = [];
  String _defaultId = 'bing';

  SearchEnginesService(this._config) {
    _load();
  }

  void _load() {
    _defaultId = _config.prefs.getString(_kDefault) ?? 'bing';

    final raw = _config.prefs.getString(_kEngines);
    List<SearchEngine> customs = [];
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((e) => SearchEngine.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        customs = list;
      } catch (_) {
        customs = [];
      }
    }
    _engines = [...builtins, ...customs];
  }

  List<SearchEngine> get engines => List.unmodifiable(_engines);

  SearchEngine? get defaultEngine {
    for (final e in _engines) {
      if (e.id == _defaultId) return e;
    }
    return _engines.isNotEmpty ? _engines.first : null;
  }

  String get defaultUrlTemplate =>
      defaultEngine?.urlTemplate ?? 'https://www.bing.com/search?q={q}';

  /// 设置默认搜索引擎，同步到 ConfigService.searchEngine
  Future<void> setDefault(String id) async {
    _defaultId = id;
    await _config.prefs.setString(_kDefault, id);
    final eng = engines.firstWhere((e) => e.id == id,
        orElse: () => builtins.first);
    await _config.setSearchEngine(eng.urlTemplate);
    notifyListeners();
  }

  /// 添加自定义搜索引擎
  Future<void> add({
    required String name,
    required String urlTemplate,
  }) async {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final engine = SearchEngine(id: id, name: name, urlTemplate: urlTemplate);
    _engines.add(engine);
    await _persist();
    notifyListeners();
  }

  /// 删除自定义搜索引擎
  Future<void> remove(String id) async {
    final target = _engines.firstWhere(
      (e) => e.id == id,
      orElse: () => const SearchEngine(id: '', name: '', urlTemplate: ''),
    );
    if (target.id.isEmpty || target.builtin) return;
    _engines.removeWhere((e) => e.id == id);
    if (_defaultId == id) {
      _defaultId = 'bing';
      await _config.prefs.setString(_kDefault, 'bing');
      await _config.setSearchEngine(builtins.first.urlTemplate);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final customs =
        _engines.where((e) => !e.builtin).map((e) => e.toJson()).toList();
    await _config.prefs.setString(_kEngines, jsonEncode(customs));
  }
}
