import 'package:flutter/foundation.dart';

import '../kernel/browser_kernel.dart';

/// 一个标签页
class TabModel {
  final String id;
  final BrowserKernel kernel;

  /// 隐私标签：不记入历史，关闭时清除 Cookie / 缓存
  final bool isPrivate;

  final ValueNotifier<String> title = ValueNotifier('新标签页');
  final ValueNotifier<String> url = ValueNotifier('about:home');
  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<bool> canGoBack = ValueNotifier(false);
  final ValueNotifier<bool> canGoForward = ValueNotifier(false);
  final ValueNotifier<bool> isLoading = ValueNotifier(false);
  final ValueNotifier<bool> desktopMode = ValueNotifier(false);

  /// 所属标签组 id（null 表示未分组）
  final ValueNotifier<String?> groupId = ValueNotifier(null);

  /// 用户在地址栏输入但尚未提交的内容（由 UI 同步）
  String? pendingAddress;

  TabModel({
    required this.id,
    required this.kernel,
    this.isPrivate = false,
  });

  Future<void> close() async {
    if (isPrivate) {
      // 隐私标签：尽力清理会话数据
      try {
        await kernel.clearCookies();
        await kernel.clearCache();
      } catch (_) {}
    }
    await kernel.dispose();
    title.dispose();
    url.dispose();
    progress.dispose();
    canGoBack.dispose();
    canGoForward.dispose();
    isLoading.dispose();
    desktopMode.dispose();
    groupId.dispose();
  }
}

/// 标签组
class TabGroup {
  final String id;
  String name;

  /// 配色索引（对应 UI 调色板下标）
  int colorIndex;

  bool collapsed;

  TabGroup({
    required this.id,
    required this.name,
    this.colorIndex = 0,
    this.collapsed = false,
  });
}
