/// 应用视觉风格：Material（Android/通用）或 Cupertino（iOS 风格）。
enum AppStyleMode { material, cupertino }

extension AppStyleModeX on AppStyleMode {
  String get label =>
      this == AppStyleMode.material ? 'Material' : 'Cupertino';
  String get description => this == AppStyleMode.material
      ? 'Material 风格（Android / Material Design）'
      : 'Cupertino 风格（iOS 风格控件）';
}

AppStyleMode parseAppStyleMode(String? raw) =>
    raw == 'cupertino' ? AppStyleMode.cupertino : AppStyleMode.material;
