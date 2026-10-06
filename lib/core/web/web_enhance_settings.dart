import 'dart:convert';

/// 网页滤镜模式
enum WebFilterMode {
  /// 不启用
  none,

  /// 夜间：整体反色 + 降低对比
  night,

  /// 护眼：棕褐色调
  sepia,

  /// 灰度
  gray;

  String get label {
    switch (this) {
      case WebFilterMode.none:
        return '关闭';
      case WebFilterMode.night:
        return '夜间';
      case WebFilterMode.sepia:
        return '护眼';
      case WebFilterMode.gray:
        return '灰度';
    }
  }

  /// 注入页面的 CSS filter 值（null 表示不注入）
  String? get cssFilter {
    switch (this) {
      case WebFilterMode.none:
        return null;
      case WebFilterMode.night:
        return 'invert(1) hue-rotate(180deg) brightness(.92) contrast(.92)';
      case WebFilterMode.sepia:
        return 'sepia(.55) saturate(1.1) brightness(1.02)';
      case WebFilterMode.gray:
        return 'grayscale(1)';
    }
  }

  static WebFilterMode parse(String? raw) {
    for (final m in WebFilterMode.values) {
      if (m.name == raw) return m;
    }
    return WebFilterMode.none;
  }
}

/// 网页阅读与显示增强设置
class WebEnhanceSettings {
  /// 隐藏图片（省流 / 无图模式）
  final bool noImage;

  /// 网页滤镜
  final WebFilterMode filter;

  /// 正文字号倍率（0.8 - 2.0）
  final double fontScale;

  /// 正文行高（1.2 - 2.4）
  final double lineHeight;

  /// 打开页面后自动进入阅读模式
  final bool autoReader;

  const WebEnhanceSettings({
    this.noImage = false,
    this.filter = WebFilterMode.none,
    this.fontScale = 1.0,
    this.lineHeight = 1.6,
    this.autoReader = false,
  });

  bool get anyActive =>
      noImage ||
      filter != WebFilterMode.none ||
      (fontScale - 1.0).abs() > 0.001 ||
      (lineHeight - 1.6).abs() > 0.001;

  WebEnhanceSettings copyWith({
    bool? noImage,
    WebFilterMode? filter,
    double? fontScale,
    double? lineHeight,
    bool? autoReader,
  }) {
    return WebEnhanceSettings(
      noImage: noImage ?? this.noImage,
      filter: filter ?? this.filter,
      fontScale: fontScale ?? this.fontScale,
      lineHeight: lineHeight ?? this.lineHeight,
      autoReader: autoReader ?? this.autoReader,
    );
  }

  Map<String, dynamic> toJson() => {
        'no_image': noImage,
        'filter': filter.name,
        'font_scale': fontScale,
        'line_height': lineHeight,
        'auto_reader': autoReader,
      };

  factory WebEnhanceSettings.fromJson(Map<String, dynamic> json) {
    return WebEnhanceSettings(
      noImage: json['no_image'] as bool? ?? false,
      filter: WebFilterMode.parse(json['filter'] as String?),
      fontScale: (json['font_scale'] as num?)?.toDouble() ?? 1.0,
      lineHeight: (json['line_height'] as num?)?.toDouble() ?? 1.6,
      autoReader: json['auto_reader'] as bool? ?? false,
    );
  }

  static WebEnhanceSettings decode(String? raw) {
    if (raw == null || raw.isEmpty) return const WebEnhanceSettings();
    try {
      return WebEnhanceSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const WebEnhanceSettings();
    }
  }

  String encode() => jsonEncode(toJson());
}
