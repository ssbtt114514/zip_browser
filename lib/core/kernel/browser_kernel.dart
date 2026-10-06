import 'package:flutter/widgets.dart';

import '../bridge/js_bridge.dart';
import '../desktop_mode_config.dart';
import '../sniff/sniff_model.dart';
import 'kernel_types.dart';

/// 浏览器内核统一抽象。
///
/// 一个 [BrowserKernel] 实例对应一个标签页中的一个网页渲染实例。
/// 实现方：
///   * [AndroidSystemKernel]  —— Android System WebView（系统）
///   * [WindowsSystemKernel]  —— Windows WebView2 / Edge Chromium（系统）
///   * [FfiBrowserKernel]     —— 独立安装包 / 插件提供的 FFI 原生内核
///   * [LinuxWebKitKernel]    —— Linux WebKitGTK（系统）
///   * [StubKernel]           —— 尚未支持平台的占位
abstract class BrowserKernel {
  /// 内核唯一 id，例如 `system.android_webview`、`plugin.com.xxx.kernel`
  String get id;

  /// 展示名称
  String get displayName;

  /// 内核版本（可获取时）
  Future<String?> get version;

  /// 系统内核 or 插件内核
  KernelOrigin get origin;

  /// 能力集合
  Set<KernelCapability> get capabilities;

  /// 当前实例使用的 JS Bridge（在 [initialize] 后可用）
  JsBridgeHub get bridge;

  /// 初始化内核并应用注入脚本 / bridge 配置
  Future<void> initialize(KernelViewConfig config);

  /// 构建网页渲染视图
  Widget buildView();

  // —— 导航 ——
  Future<void> loadUrl(String url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> stopLoading();
  Future<bool> canGoBack();
  Future<bool> canGoForward();

  /// 执行任意 JS 并取回结果
  Future<String?> evaluateJavascript(String script);

  /// 注册一个 bridge 处理方法
  void registerBridgeHandler(String method, BridgeHandler handler);

  // —— 浏览器增强能力 ——

  /// 启用 / 禁用 JavaScript（实时生效）
  Future<void> setJavaScriptEnabled(bool enabled);

  /// 设置 User-Agent；null 恢复内核默认
  Future<void> setUserAgent(String? userAgent);

  /// 设置桌面模式（UA、视口、DPR）
  Future<void> setDesktopMode(DesktopModeConfig config);

  /// 页面内查找：返回匹配数
  Future<int> findStart(String query);

  /// 跳到下一个（forward=true）/ 上一个匹配
  Future<void> findNext(bool forward);

  /// 清除查找高亮
  Future<void> findClear();

  /// 长按 / 右键菜单请求
  Stream<ContextMenuInfo> get contextMenu;

  /// 请求宿主接管下载的文件 URL
  Stream<String> get downloadRequests;

  /// 检测到可安装的用户脚本链接（点击 .user.js 时触发）
  Stream<String> get userscriptDetected;

  /// 页面扫描到的用户脚本链接列表
  Stream<List<String>> get userscriptList;

  /// 嗅探到的页面资源（媒体/图片/样式/脚本等）
  Stream<List<SniffedResource>> get sniffedResources;

  /// 主动触发一次资源嗅探（重新扫描 DOM）
  Future<void> triggerSniff();

  /// 清除 Cookie
  Future<void> clearCookies();

  /// 清除缓存
  Future<void> clearCache();

  // —— 事件流 ——
  Stream<NavigationEvent> get navigationEvents;
  Stream<double> get progress;
  Stream<String> get urlChanges;
  Stream<String> get titleChanges;
  Stream<WebResourceError> get resourceErrors;

  /// 当前页面标题
  Future<String?> getCurrentTitle();

  /// 当前 URL
  Future<String?> getCurrentUrl();

  Future<void> dispose();
}

/// 长按 / 右键菜单上下文
class ContextMenuInfo {
  final String pageUrl;
  final String? linkUrl;
  final String? imageUrl;
  final String? selectedText;

  const ContextMenuInfo({
    required this.pageUrl,
    this.linkUrl,
    this.imageUrl,
    this.selectedText,
  });

  bool get hasLink => linkUrl != null && linkUrl!.isNotEmpty;
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
}

/// 页面资源加载错误（跨平台统一描述）
class WebResourceError {
  final int? errorCode;
  final String description;
  final bool isForMainFrame;
  final String? url;

  const WebResourceError({
    this.errorCode,
    required this.description,
    this.isForMainFrame = true,
    this.url,
  });

  @override
  String toString() => 'WebResourceError($errorCode, $description, $url)';
}
