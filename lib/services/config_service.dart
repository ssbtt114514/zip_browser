import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/desktop_mode_config.dart';
import '../core/web/web_enhance_settings.dart';

/// 全局配置（持久化）
class ConfigService {
  static const _kKernelId = 'kernel.selected_id';
  static const _kHomePage = 'browser.home_page';
  static const _kSearchEngine = 'browser.search_engine';
  static const _kJsEnabled = 'browser.js_enabled';
  static const _kEnforceTrusted = 'security.enforce_trusted';
  static const _kDesktopMode = 'browser.desktop_mode';
  static const _kWebEnhance = 'browser.web_enhance';
  static const _kHomeShortcuts = 'home.shortcut_count';
  static const _kHomeRecent = 'home.show_recent';

  final SharedPreferences _prefs;

  /// 暴露 SharedPreferences 供其他服务使用（如搜索引擎自定义项存储）
  SharedPreferences get prefs => _prefs;

  ConfigService._(this._prefs);

  static Future<ConfigService> create() async {
    return ConfigService._(await SharedPreferences.getInstance());
  }

  /// 选中的内核 id；null 表示使用平台默认系统内核
  String? get selectedKernelId => _prefs.getString(_kKernelId);
  Future<void> setSelectedKernelId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kKernelId);
    } else {
      await _prefs.setString(_kKernelId, id);
    }
  }

  String get homePage =>
      _prefs.getString(_kHomePage) ?? 'about:home';
  Future<void> setHomePage(String value) =>
      _prefs.setString(_kHomePage, value);

  String get searchEngine =>
      _prefs.getString(_kSearchEngine) ?? 'https://www.bing.com/search?q={q}';
  Future<void> setSearchEngine(String value) =>
      _prefs.setString(_kSearchEngine, value);

  bool get jsEnabled => _prefs.getBool(_kJsEnabled) ?? true;
  Future<void> setJsEnabled(bool value) => _prefs.setBool(_kJsEnabled, value);

  /// 是否强制只允许白名单插件
  bool get enforceTrustedOnly => _prefs.getBool(_kEnforceTrusted) ?? false;
  Future<void> setEnforceTrustedOnly(bool value) =>
      _prefs.setBool(_kEnforceTrusted, value);

  /// 桌面模式配置
  DesktopModeConfig get desktopMode {
    final raw = _prefs.getString(_kDesktopMode);
    if (raw == null || raw.isEmpty) return const DesktopModeConfig();
    try {
      return DesktopModeConfig.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const DesktopModeConfig();
    }
  }

  Future<void> setDesktopMode(DesktopModeConfig cfg) =>
      _prefs.setString(_kDesktopMode, jsonEncode(cfg.toJson()));

  /// 网页阅读与显示增强设置
  WebEnhanceSettings get webEnhance =>
      WebEnhanceSettings.decode(_prefs.getString(_kWebEnhance));
  Future<void> setWebEnhance(WebEnhanceSettings value) =>
      _prefs.setString(_kWebEnhance, value.encode());

  /// 新标签页快捷方式数量（4 - 16）
  int get homeShortcutCount => _prefs.getInt(_kHomeShortcuts) ?? 8;
  Future<void> setHomeShortcutCount(int value) =>
      _prefs.setInt(_kHomeShortcuts, value.clamp(4, 16));

  /// 新标签页是否展示「最近访问」
  bool get homeShowRecent => _prefs.getBool(_kHomeRecent) ?? true;
  Future<void> setHomeShowRecent(bool value) =>
      _prefs.setBool(_kHomeRecent, value);
}
