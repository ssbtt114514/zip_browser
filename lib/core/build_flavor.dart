/// 构建风味：由 `--dart-define=ZIP_FLAVOR=full|single|none` 决定。
///
/// - full   完整版：系统内核 + 独立内核包 + zip 插件 + 用户脚本（默认）
/// - single 单内核版：仅系统 WebView 内核，隐藏内核管理 / 插件 / 用户脚本
/// - none   无内核版：完全不加载网页，仅保留界面 / 数据 / 工具能力
///
/// 两种精简构建满足「无浏览器内核」「单内核」分发需求，也在构建层面
/// 移除了插件接口的入口（代码保留，便于随时恢复完整版）。
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

  /// 是否启用 zip 插件系统（工具栏扩展按钮 / 插件管理 / 插件内核）
  static bool get pluginSystemEnabled => current == BuildFlavor.full;

  /// 是否启用内核管理（独立 .zbk 内核包 / 插件携带内核）
  static bool get kernelManagementEnabled => current == BuildFlavor.full;

  /// 是否启用用户脚本
  static bool get userscriptsEnabled => current == BuildFlavor.full;

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
