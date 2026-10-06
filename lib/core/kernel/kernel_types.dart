/// 内核来源类型
enum KernelOrigin {
  /// 操作系统自带的 WebView（Android System WebView / Windows WebView2）
  system,

  /// 通过独立安装包安装的内核（本框架主推方式）
  standalone,

  /// 由 zip 插件携带的内核（FFI 原生库 / Fixed Version 运行时）
  plugin,
}

/// 内核能力位
enum KernelCapability {
  /// 加载任意 http(s) 页面
  loadUrl,

  /// 执行 JavaScript
  evaluateJs,

  /// 页面内容脚本注入（content scripts）
  userScripts,

  /// 多标签
  multiTab,

  /// 文件下载
  download,

  /// 开发者工具
  devTools,

  /// 自定义 Scheme 拦截
  schemeIntercept,

  /// 隐私会话（标签关闭即清除 Cookie / 缓存）
  privateSession,
}

/// 内核能力位 <-> 清单字符串的映射
extension KernelCapabilityKey on KernelCapability {
  String get key {
    switch (this) {
      case KernelCapability.loadUrl:
        return 'loadUrl';
      case KernelCapability.evaluateJs:
        return 'evaluateJs';
      case KernelCapability.userScripts:
        return 'userScripts';
      case KernelCapability.multiTab:
        return 'multiTab';
      case KernelCapability.download:
        return 'download';
      case KernelCapability.devTools:
        return 'devTools';
      case KernelCapability.schemeIntercept:
        return 'schemeIntercept';
      case KernelCapability.privateSession:
        return 'privateSession';
    }
  }

  String get label {
    switch (this) {
      case KernelCapability.loadUrl:
        return '网页加载';
      case KernelCapability.evaluateJs:
        return '脚本执行';
      case KernelCapability.userScripts:
        return '内容脚本';
      case KernelCapability.multiTab:
        return '多标签';
      case KernelCapability.download:
        return '下载';
      case KernelCapability.devTools:
        return '开发者工具';
      case KernelCapability.schemeIntercept:
        return '协议拦截';
      case KernelCapability.privateSession:
        return '隐私会话';
    }
  }

  static KernelCapability? fromKey(String key) {
    for (final c in KernelCapability.values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// 渲染引擎谱系
enum KernelEngine {
  /// Chromium / Blink
  chromium,

  /// Gecko
  gecko,

  /// 操作系统自带 WebView（WebView2 / Android WebView / WebKitGTK）
  system,

  /// 自研或第三方内核
  custom;

  String get label {
    switch (this) {
      case KernelEngine.chromium:
        return 'Chromium';
      case KernelEngine.gecko:
        return 'Gecko';
      case KernelEngine.system:
        return '系统 WebView';
      case KernelEngine.custom:
        return '自定义内核';
    }
  }

  static KernelEngine parse(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'chromium':
      case 'blink':
        return KernelEngine.chromium;
      case 'gecko':
      case 'firefox':
        return KernelEngine.gecko;
      case 'system':
      case 'webview':
        return KernelEngine.system;
      default:
        return KernelEngine.custom;
    }
  }
}

/// 内核包加载方式（清单 `type` 字段）的对外文案
///
/// 三种取值分别对应：FFI 原生库、WebView2 固定版本运行时、引擎适配包。
/// 引擎适配包不携带渲染库，仅做引擎探测，文案必须如实说明这一点。
String kernelTypeLabel(String type, {int abiVersion = 1}) {
  switch (type) {
    case 'webview2_fixed':
      return 'WebView2 固定版本';
    case 'engine_adapter':
      return '引擎适配包（不携带渲染库）';
    default:
      return 'FFI 原生库 (ABI v$abiVersion)';
  }
}

/// 导航阶段事件
class NavigationEvent {
  final String url;
  final NavigationStage stage;
  const NavigationEvent(this.url, this.stage);
}

enum NavigationStage {
  start,
  redirect,
  commit,
  finished,
  blocked,
}

/// 内核视图配置：每个标签页持有一份
class KernelViewConfig {
  final String tabId;
  final String? initialUrl;

  /// 需要在页面所有脚本之前/之后注入的 JS
  final List<UserScript> userScripts;

  /// JS Bridge 暴露给页面的全局对象名，默认 `zipBrowser`
  final String bridgeGlobalName;

  /// 插件内核时：原生库绝对路径（FFI）
  final String? nativeLibraryPath;

  /// 插件内核时：内核资源目录（如 WebView2 Fixed Version 目录）
  final String? kernelDataDir;

  /// 允许的 bridge 通道（来自插件权限声明）
  final Set<String> allowedBridgeMethods;

  const KernelViewConfig({
    required this.tabId,
    this.initialUrl,
    this.userScripts = const [],
    this.bridgeGlobalName = 'zipBrowser',
    this.nativeLibraryPath,
    this.kernelDataDir,
    this.allowedBridgeMethods = const {},
  });
}

/// 注入脚本
class UserScript {
  /// 注入时机
  final UserScriptInjectionTiming timing;

  /// URL 匹配规则（glob：* 匹配任意）
  final List<String> matches;
  final String source;

  /// 来源插件 id（系统注入为 null）
  final String? pluginId;

  const UserScript({
    required this.source,
    this.timing = UserScriptInjectionTiming.documentEnd,
    this.matches = const ['*'],
    this.pluginId,
  });

  bool matchesUrl(String url) {
    for (final pattern in matches) {
      if (_globMatch(pattern, url)) return true;
    }
    return false;
  }

  /// 极简 glob：仅支持 * 与前缀，满足 matches 声明需求
  static bool _globMatch(String pattern, String input) {
    if (pattern == '*' || pattern == '<all_urls>') return true;
    final regex = RegExp(
      '^${RegExp.escape(pattern).replaceAll(r'\*', '.*')}\$',
    );
    return regex.hasMatch(input);
  }
}

enum UserScriptInjectionTiming {
  documentStart,
  documentEnd,
}
