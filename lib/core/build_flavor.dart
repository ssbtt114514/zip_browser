/// 构建风味：由 `--dart-define=ZIP_FLAVOR=none|chromium|gecko` 决定。
///
/// - none     无内核版：不加载网页，仅保留界面 / 数据 / 工具能力
/// - chromium Chromium 内核版：使用系统 WebView（Android WebView /
///   Windows WebView2，Linux 回落 WebKitGTK）
/// - gecko    Gecko 内核版：随包内置 Gecko 内核包，首次启动自动安装并选中
///
/// 三种风味满足「无内核 / Chromium / Gecko」分发需求。
/// 内核不再支持运行时安装：内置内核包随安装介质交付，
/// 用户无需也不能手动安装 .zbk。
enum BuildFlavor { none, chromium, gecko }

class BuildFlavorInfo {
  static const String _raw = String.fromEnvironment(
    'ZIP_FLAVOR',
    defaultValue: 'chromium',
  );

  static BuildFlavor get current => switch (_raw) {
        'none' => BuildFlavor.none,
        'gecko' => BuildFlavor.gecko,
        _ => BuildFlavor.chromium,
      };

  /// 是否加载网页（none 风味使用占位内核）
  static bool get webEnabled => current != BuildFlavor.none;

  /// 随包内置的内核包资产路径；null 表示不内置（使用系统内核）
  static String? get bundledKernelAsset =>
      current == BuildFlavor.gecko ? 'assets/bundled/kernel.zbk' : null;

  /// 中文标签（关于页 / 安装包命名用）
  static String get label => switch (current) {
        BuildFlavor.none => '无内核版',
        BuildFlavor.chromium => 'Chromium 内核版',
        BuildFlavor.gecko => 'Gecko 内核版',
      };

  /// 文件名后缀
  static String get fileSuffix => switch (current) {
        BuildFlavor.none => '-no-kernel',
        BuildFlavor.chromium => '-chromium',
        BuildFlavor.gecko => '-gecko',
      };
}
