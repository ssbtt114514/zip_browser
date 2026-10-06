import 'package:flutter/widgets.dart';

/// 浏览器根焦点作用域。
///
/// 键盘快捷键依赖"活动焦点位于 [CallbackShortcuts] 子树内"这一前提。
/// 当地址栏失焦、弹层关闭等场景导致焦点落到作用域之外时，需要一个统一的
/// 落点把焦点收回，否则快捷键会整体失效。这里用 [InheritedWidget] 把根
/// [FocusNode] 暴露给地址栏、内容区等任意后代。
class BrowserFocus extends InheritedWidget {
  final FocusNode rootFocus;

  const BrowserFocus({
    super.key,
    required this.rootFocus,
    required super.child,
  });

  static FocusNode? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BrowserFocus>()
        ?.rootFocus;
  }

  /// 把焦点收回根节点（仅当当前没有任何节点持有焦点）
  static void ensureHeld(BuildContext context) {
    final node = maybeOf(context);
    if (node == null) return;
    if (FocusManager.instance.primaryFocus == null) {
      node.requestFocus();
    }
  }

  /// 无条件把焦点交给根节点（用于地址栏主动收起等场景）
  static void take(BuildContext context) {
    maybeOf(context)?.requestFocus();
  }

  @override
  bool updateShouldNotify(BrowserFocus oldWidget) =>
      oldWidget.rootFocus != rootFocus;
}
