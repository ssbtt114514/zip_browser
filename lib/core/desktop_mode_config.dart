/// 桌面模式配置模型：User-Agent、视口、DPR 等自定义参数。
class DesktopModeConfig {
  /// 是否启用桌面模式
  final bool enabled;

  /// 自定义 User-Agent（为空则使用默认桌面 UA）
  final String userAgent;

  /// 视口宽度（CSS 像素），0 表示使用内核默认
  final int viewportWidth;

  /// 视口高度（CSS 像素），0 表示使用内核默认
  final int viewportHeight;

  /// 设备像素比，0 表示使用内核默认
  final double devicePixelRatio;

  const DesktopModeConfig({
    this.enabled = false,
    this.userAgent = '',
    this.viewportWidth = 0,
    this.viewportHeight = 0,
    this.devicePixelRatio = 0,
  });

  /// 默认桌面 UA（Edge on Windows 11）
  static const String defaultDesktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0';

  /// 默认移动 UA（Android Chrome）
  static const String defaultMobileUA =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// 解析后的生效 UA
  String get effectiveUA {
    if (!enabled) return defaultMobileUA;
    return userAgent.trim().isEmpty ? defaultDesktopUA : userAgent.trim();
  }

  DesktopModeConfig copyWith({
    bool? enabled,
    String? userAgent,
    int? viewportWidth,
    int? viewportHeight,
    double? devicePixelRatio,
  }) {
    return DesktopModeConfig(
      enabled: enabled ?? this.enabled,
      userAgent: userAgent ?? this.userAgent,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      viewportHeight: viewportHeight ?? this.viewportHeight,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'userAgent': userAgent,
        'viewportWidth': viewportWidth,
        'viewportHeight': viewportHeight,
        'devicePixelRatio': devicePixelRatio,
      };

  factory DesktopModeConfig.fromJson(Map<String, dynamic> json) {
    return DesktopModeConfig(
      enabled: json['enabled'] as bool? ?? false,
      userAgent: json['userAgent'] as String? ?? '',
      viewportWidth: json['viewportWidth'] as int? ?? 0,
      viewportHeight: json['viewportHeight'] as int? ?? 0,
      devicePixelRatio: (json['devicePixelRatio'] as num?)?.toDouble() ?? 0,
    );
  }
}
