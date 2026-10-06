import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网页缩放服务。
///
/// 浏览器该有的能力之一：按站点记住缩放倍率，并提供全局默认倍率。
/// 由于各系统内核（Android System WebView / Windows WebView2）在 Dart 侧
/// 没有统一的 zoom API，这里通过向页面注入 CSS `zoom` 实现，Chromium
/// 系（Blink）原生支持该属性。
class ZoomService extends ChangeNotifier {
  static const String _kDefault = 'zoom.default';
  static const String _kPerSite = 'zoom.per_site';
  static const String _kPerSiteEnabled = 'zoom.per_site_enabled';

  /// 可选倍率档位（100% 位于中段，便于上下调节）
  static const List<double> presets = [
    0.25, 0.33, 0.50, 0.67, 0.75, 0.80, 0.90,
    1.00, 1.10, 1.25, 1.50, 1.75, 2.00, 2.50, 3.00, 4.00, 5.00,
  ];

  static const double minZoom = 0.25;
  static const double maxZoom = 5.0;

  final SharedPreferences _prefs;

  /// origin -> 倍率
  final Map<String, double> _sites = {};

  ZoomService._(this._prefs) {
    _load();
  }

  static Future<ZoomService> create() async {
    return ZoomService._(await SharedPreferences.getInstance());
  }

  void _load() {
    final raw = _prefs.getString(_kPerSite);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final z = value is num ? value.toDouble() : double.tryParse('$value');
          if (z != null && z >= minZoom && z <= maxZoom) {
            _sites['$key'] = z;
          }
        });
      }
    } catch (_) {
      // 存储损坏时忽略，退回默认倍率
    }
  }

  Future<void> _flush() async {
    await _prefs.setString(_kPerSite, jsonEncode(_sites));
    notifyListeners();
  }

  /// 全局默认倍率
  double get defaultZoom {
    final v = _prefs.getDouble(_kDefault) ?? 1.0;
    return v.clamp(minZoom, maxZoom).toDouble();
  }

  Future<void> setDefaultZoom(double value) async {
    await _prefs.setDouble(_kDefault, value.clamp(minZoom, maxZoom).toDouble());
    notifyListeners();
  }

  /// 是否启用「按站点记忆缩放」
  bool get perSiteEnabled => _prefs.getBool(_kPerSiteEnabled) ?? true;

  Future<void> setPerSiteEnabled(bool value) async {
    await _prefs.setBool(_kPerSiteEnabled, value);
    notifyListeners();
  }

  /// 已记录缩放的站点（origin -> 倍率），供设置页展示
  Map<String, double> get siteZooms => Map.unmodifiable(_sites);

  /// 站点标识；无法解析（data: / about:）时返回 null
  static String? originOf(String url) {
    if (url.isEmpty) return null;
    if (url.startsWith('data:') || url.startsWith('about:') ||
        url.startsWith('blob:')) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.hasPort ? '${uri.scheme}://${uri.host}:${uri.port}' : '${uri.scheme}://${uri.host}';
  }

  /// 某 URL 当前生效的倍率
  double forUrl(String url) {
    if (!perSiteEnabled) return defaultZoom;
    final origin = originOf(url);
    if (origin == null) return defaultZoom;
    return _sites[origin] ?? defaultZoom;
  }

  /// 设置某 URL 的倍率（按 origin 记录）
  Future<void> setForUrl(String url, double value) async {
    final origin = originOf(url);
    final clamped = value.clamp(minZoom, maxZoom).toDouble();
    if (origin == null) {
      await setDefaultZoom(clamped);
      return;
    }
    if ((clamped - defaultZoom).abs() < 0.001) {
      _sites.remove(origin);
    } else {
      _sites[origin] = clamped;
    }
    await _flush();
  }

  /// 清除某站点的缩放记录
  Future<void> clearSite(String url) async {
    final origin = originOf(url);
    if (origin == null) return;
    if (_sites.remove(origin) != null) await _flush();
  }

  Future<void> clearAll() async {
    if (_sites.isEmpty) return;
    _sites.clear();
    await _flush();
  }

  /// 下一档 / 上一档
  double stepUp(double current) {
    for (final p in presets) {
      if (p > current + 0.001) return p;
    }
    return maxZoom;
  }

  double stepDown(double current) {
    for (final p in presets.reversed) {
      if (p < current - 0.001) return p;
    }
    return minZoom;
  }

  /// 倍率显示文本，例如 110%
  static String label(double zoom) => '${(zoom * 100).round()}%';

  /// 注入页面的缩放脚本。倍率 1.0 时清除内联样式，避免残留。
  static String scriptFor(double zoom) {
    final value = zoom.clamp(minZoom, maxZoom).toDouble();
    return '''
(function () {
  try {
    var el = document.documentElement || document.body;
    if (!el) return;
    if (Math.abs($value - 1) < 0.001) {
      el.style.removeProperty('zoom');
    } else {
      el.style.zoom = '$value';
    }
  } catch (e) {}
})();''';
  }
}
