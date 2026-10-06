import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题亮度模式
enum ThemeModeOption { system, light, dark }

/// 控件密度
enum DensityOption { comfortable, compact }

/// 圆角等级
enum RadiusLevel { none, small, medium, large }

/// 外观设置：可自定义的视觉参数
class AppearanceSettings extends ChangeNotifier {
  static const String _kMode = 'appearance.theme_mode';
  static const String _kSeed = 'appearance.seed_color';
  static const String _kAccent = 'appearance.accent_color';
  static const String _kFontScale = 'appearance.font_scale';
  static const String _kDensity = 'appearance.density';
  static const String _kRadius = 'appearance.radius';
  static const String _kBgColor = 'appearance.home_bg_color';
  static const String _kBgImage = 'appearance.home_bg_image';
  static const String _kTrueBlack = 'appearance.true_black';
  static const String _kMonet = 'appearance.monet';

  final SharedPreferences _prefs;

  AppearanceSettings._(this._prefs);

  static Future<AppearanceSettings> create() async {
    return AppearanceSettings._(await SharedPreferences.getInstance());
  }

  // —— 亮度模式 ——
  ThemeModeOption get themeMode {
    final v = _prefs.getString(_kMode);
    return ThemeModeOption.values.firstWhere(
      (e) => e.name == v,
      orElse: () => ThemeModeOption.system,
    );
  }

  Future<void> setThemeMode(ThemeModeOption mode) async {
    await _prefs.setString(_kMode, mode.name);
    notifyListeners();
  }

  /// 转 Flutter ThemeMode
  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case ThemeModeOption.system:
        return ThemeMode.system;
      case ThemeModeOption.light:
        return ThemeMode.light;
      case ThemeModeOption.dark:
        return ThemeMode.dark;
    }
  }

  // —— 主色调（ColorScheme seed）——
  Color get seedColor {
    final v = _prefs.getInt(_kSeed);
    return v == null ? const Color(0xFF0B84A5) : Color(v);
  }

  Future<void> setSeedColor(Color color) async {
    await _prefs.setInt(_kSeed, color.value);
    notifyListeners();
  }

  // —— 强调色（按钮/链接高亮，null 时跟随 seed）——
  Color? get accentColor {
    final v = _prefs.getInt(_kAccent);
    return v == null ? null : Color(v);
  }

  Future<void> setAccentColor(Color? color) async {
    if (color == null) {
      await _prefs.remove(_kAccent);
    } else {
      await _prefs.setInt(_kAccent, color.value);
    }
    notifyListeners();
  }

  // —— 字体缩放 0.8 ~ 1.4 ——
  double get fontScale {
    return _prefs.getDouble(_kFontScale) ?? 1.0;
  }

  Future<void> setFontScale(double scale) async {
    await _prefs.setDouble(_kFontScale, scale.clamp(0.8, 1.4));
    notifyListeners();
  }

  // —— 控件密度 ——
  DensityOption get density {
    final v = _prefs.getString(_kDensity);
    return DensityOption.values.firstWhere(
      (e) => e.name == v,
      orElse: () => DensityOption.comfortable,
    );
  }

  Future<void> setDensity(DensityOption d) async {
    await _prefs.setString(_kDensity, d.name);
    notifyListeners();
  }

  VisualDensity get visualDensity {
    return density == DensityOption.compact
        ? VisualDensity.compact
        : VisualDensity.comfortable;
  }

  // —— 圆角等级 ——
  RadiusLevel get radiusLevel {
    final v = _prefs.getString(_kRadius);
    return RadiusLevel.values.firstWhere(
      (e) => e.name == v,
      orElse: () => RadiusLevel.medium,
    );
  }

  Future<void> setRadiusLevel(RadiusLevel r) async {
    await _prefs.setString(_kRadius, r.name);
    notifyListeners();
  }

  /// 统一圆角半径（像素）
  double get radiusValue {
    switch (radiusLevel) {
      case RadiusLevel.none:
        return 0;
      case RadiusLevel.small:
        return 6;
      case RadiusLevel.medium:
        return 12;
      case RadiusLevel.large:
        return 20;
    }
  }

  // —— 起始页背景 ——
  Color get homeBgColor {
    final v = _prefs.getInt(_kBgColor);
    return v == null ? const Color(0xFFEEF4FB) : Color(v);
  }

  Future<void> setHomeBgColor(Color color) async {
    await _prefs.setInt(_kBgColor, color.value);
    notifyListeners();
  }

  String? get homeBgImage => _prefs.getString(_kBgImage);

  Future<void> setHomeBgImage(String? path) async {
    if (path == null) {
      await _prefs.remove(_kBgImage);
    } else {
      await _prefs.setString(_kBgImage, path);
    }
    notifyListeners();
  }

  // —— 纯黑模式（OLED 友好）——
  bool get trueBlack => _prefs.getBool(_kTrueBlack) ?? false;

  Future<void> setTrueBlack(bool value) async {
    await _prefs.setBool(_kTrueBlack, value);
    notifyListeners();
  }

  // —— 莫奈动态取色（Android 12+，其他平台自动回退到 seed 色）——
  bool get monetEnabled => _prefs.getBool(_kMonet) ?? true;

  Future<void> setMonetEnabled(bool value) async {
    await _prefs.setBool(_kMonet, value);
    notifyListeners();
  }

  /// 预设主色板
  static const List<Color> palette = [
    Color(0xFF0B84A5),
    Color(0xFF6750A4),
    Color(0xFF006C4A),
    Color(0xFF9C4221),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFDC2626),
    Color(0xFF0F766E),
    Color(0xFF2563EB),
    Color(0xFFCA8A04),
  ];

  /// 预设强调色
  static const List<Color> accentPalette = [
    Color(0xFFFF6B6B),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFFFF6FB5),
    Color(0xFFB983FF),
  ];
}
