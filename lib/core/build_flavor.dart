/// 构建风味：由 `--dart-define=ZIP_FLAVOR=full|single|none` 决定。
///
/// - full   完整版：系统内核 + 独立内核包 + 用户脚本（默认）
/// - single 单内核版：仅系统 WebView 内核，隐藏内核管理 / 用户脚本
/// - none   无内核版：完全不加载网页，仅保留界面 / 数据 / 工具能力
///
/// 三种风味满足「无浏览器内核」「单内核」分发需求。
/// zip 功能插件接口已于 v0.12.0 移除（原 full 风味专属），
/// 独立内核改由 .zbk 内核包机制承载（内核管理页安装）。
enum BuildFlavor { full, single, none }

class BuildFlavorInfo {
  static const String _raw = String.fromEnvironment(
    'ZIP_FLAVOR',
    defaultValue: 'full',
  );

  static BuildFlavor get current => switch (_raw) {
        'single' => BuildFlavor.single,
        'none' => BuildFlavor.none,
        _ => BuildFlavor.full,
      };

  /// 是否启用内核管理（独立 .zbk 内核包 / 内核切换）
  static bool get kernelManagementEnabled => current == BuildFlavor.full;

  /// 是否加载网页（none 风味使用占位内核）
  static bool get webEnabled => current != BuildFlavor.none;

  /// 中文标签（关于页 / 安装包命名用）
  static String get label => switch (current) {
        BuildFlavor.full => '完整版',
        BuildFlavor.single => '单内核版',
        BuildFlavor.none => '无内核版',
      };

  /// 文件名后缀
  static String get fileSuffix => switch (current) {
        BuildFlavor.full => '',
        BuildFlavor.single => '-single',
        BuildFlavor.none => '-no-kernel',
      };
}
