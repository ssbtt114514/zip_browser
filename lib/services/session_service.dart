import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 启动时行为
enum SessionStartupMode {
  /// 打开主页 / 新标签页
  home,

  /// 恢复上次会话
  restore,
}

/// 会话中一个标签的快照
class SessionTab {
  final String url;
  final String title;
  final bool pinned;
  final String? groupId;

  const SessionTab({
    required this.url,
    this.title = '',
    this.pinned = false,
    this.groupId,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'pinned': pinned,
        if (groupId != null) 'group': groupId,
      };

  static SessionTab? fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    return SessionTab(
      url: url,
      title: json['title']?.toString() ?? '',
      pinned: json['pinned'] == true,
      groupId: json['group']?.toString(),
    );
  }
}

/// 会话（上次打开标签页）持久化服务。
///
/// 与书签/历史一样基于 SharedPreferences，避免额外文件依赖。
/// 隐私标签永不写入快照。
class SessionService {
  static const String _kStartup = 'session.startup_mode';
  static const String _kSnapshot = 'session.snapshot';
  static const String _kClean = 'session.clean_exit';

  /// 快照最多记录的标签数
  static const int maxSnapshotTabs = 60;

  final SharedPreferences _prefs;

  /// 上一次运行是否异常退出（本次启动时读取）
  bool _crashedLastRun = false;

  SessionService._(this._prefs) {
    _crashedLastRun = !(_prefs.getBool(_kClean) ?? true);
    // 本次启动即标记为「非正常退出」，正常退出时由 UI 置回 true
    _prefs.setBool(_kClean, false);
  }

  static Future<SessionService> create() async {
    return SessionService._(await SharedPreferences.getInstance());
  }

  /// 上次运行是否崩溃（用于提示「恢复上次会话」）
  bool get crashedLastRun => _crashedLastRun;

  SessionStartupMode get startupMode {
    final raw = _prefs.getString(_kStartup);
    return raw == 'restore'
        ? SessionStartupMode.restore
        : SessionStartupMode.home;
  }

  Future<void> setStartupMode(SessionStartupMode mode) async {
    await _prefs.setString(_kStartup, mode.name);
  }

  /// 保存当前会话快照（跳过隐私标签）
  Future<void> saveSnapshot(List<SessionTab> tabs) async {
    final list = tabs
        .where((t) => t.url.isNotEmpty && !t.url.startsWith('data:'))
        .take(maxSnapshotTabs)
        .map((t) => t.toJson())
        .toList();
    if (list.isEmpty) {
      await _prefs.remove(_kSnapshot);
      return;
    }
    await _prefs.setString(_kSnapshot, jsonEncode(list));
  }

  /// 读取上次会话快照
  List<SessionTab> readSnapshot() {
    final raw = _prefs.getString(_kSnapshot);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <SessionTab>[];
      for (final e in decoded) {
        if (e is Map) {
          final tab = SessionTab.fromJson(Map<String, dynamic>.from(e));
          if (tab != null) out.add(tab);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  bool get hasSnapshot => readSnapshot().isNotEmpty;

  Future<void> clearSnapshot() => _prefs.remove(_kSnapshot);

  /// 记录一次正常退出
  Future<void> markCleanExit() => _prefs.setBool(_kClean, true);
}
