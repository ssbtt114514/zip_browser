import 'package:flutter/material.dart';

/// 设计令牌：尺寸、间距、动效时长。
///
/// 全站 UI 只引用这里的常量，避免各处硬编码魔法数字。
class ZbTokens {
  const ZbTokens._();

  // —— 尺寸 ——
  /// 桌面 / 宽屏：标签栏高度
  static const double tabStripHeight = 40;

  /// 窄屏：标签栏高度（略高，便于触摸）
  static const double compactTabStripHeight = 44;

  /// 主工具栏高度（含地址栏）
  static const double toolbarHeight = 54;

  /// 二级工具栏高度
  static const double secondaryBarHeight = 48;

  /// 书签栏高度
  static const double bookmarksBarHeight = 34;

  /// 地址栏（Pill）高度
  static const double omniboxHeight = 38;

  /// 标签页宽度
  static const double tabWidth = 208;
  static const double tabWidthCompact = 148;
  static const double pinnedTabWidth = 44;

  /// 工具按钮触区
  static const double toolButtonSize = 36;

  // —— 间距 ——
  static const double s1 = 2;
  static const double s2 = 4;
  static const double s3 = 6;
  static const double s4 = 8;
  static const double s5 = 12;
  static const double s6 = 16;
  static const double s7 = 24;

  // —— 动效 ——
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
}

/// 语义色板：把 [ColorScheme] 映射为浏览器外壳专用的颜色。
///
/// 原实现直接在组件里写死 `Color(0xFFE7EDF2)` / `Colors.white` 之类的
/// 值，导致暗色主题下标签栏、地址栏发白、文字看不清。改为统一从这里取值，
/// 颜色全部随主题与莫奈取色联动。
@immutable
class ZbColors {
  final ColorScheme scheme;
  final bool isDark;

  const ZbColors(this.scheme, this.isDark);

  factory ZbColors.of(BuildContext context) {
    final theme = Theme.of(context);
    return ZbColors(theme.colorScheme, theme.brightness == Brightness.dark);
  }

  // —— 外壳层次 ——

  /// 标签栏底色（比工具栏略"深"一档，形成层次）
  Color get chrome =>
      isDark ? scheme.surfaceContainerLowest : scheme.surfaceContainerHigh;

  /// 工具栏底色
  Color get chromeElevated =>
      isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLow;

  /// 内容区上下文色（页面失效时的兜底背景）
  Color get contentBackground => scheme.surface;

  /// 活动标签底色：与工具栏/内容形成对比
  Color get tabActive =>
      isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest;

  /// 非活动标签底色
  Color get tabInactive => Colors.transparent;

  // —— 交互态 ——
  Color get hover =>
      scheme.onSurface.withValues(alpha: isDark ? 0.10 : 0.06);
  Color get pressed =>
      scheme.onSurface.withValues(alpha: isDark ? 0.16 : 0.11);

  // —— 分隔与描边 ——
  Color get hairline => scheme.outlineVariant.withValues(alpha: isDark ? 0.6 : 0.9);
  Color get strongBorder => scheme.outline.withValues(alpha: 0.55);

  // —— 地址栏 ——
  Color get omniboxFill =>
      isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest;
  Color get omniboxFillFocused =>
      isDark ? scheme.surfaceContainerHighest : scheme.surfaceContainerLowest;

  // —— 文字 ——
  Color get textPrimary => scheme.onSurface;
  Color get textMuted => scheme.onSurfaceVariant;
  Color get textFaint => scheme.onSurfaceVariant.withValues(alpha: 0.7);

  // —— 语义色 ——
  /// 安全连接（https）指示色，明暗两种主题下都保持足够对比
  Color get secure => isDark ? const Color(0xFF6FD48A) : const Color(0xFF1E8E3E);

  /// 不安全 / 错误
  Color get insecure => scheme.error;

  /// 隐私标签标识色
  Color get privateAccent =>
      isDark ? const Color(0xFFC6B4E8) : const Color(0xFF5E4A8A);

  /// 隐私标签底色
  Color get privateSurface =>
      isDark ? const Color(0xFF33294A) : const Color(0xFFEDE7F6);

  /// 建议列表选中项底色
  Color get suggestionHighlight =>
      scheme.primary.withValues(alpha: isDark ? 0.20 : 0.10);

  /// 低强度阴影（浮层/omnibox）
  List<BoxShadow> softShadow() => isDark
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ];

  /// 浮层阴影（下拉建议 / 面板）
  List<BoxShadow> panelShadow() => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.14),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}

/// 便捷访问：`context.zb.chrome`
extension ZbColorsX on BuildContext {
  ZbColors get zb => ZbColors.of(this);
}

/// 浏览器外壳的一条横向"栏"（标签栏 / 工具栏 / 书签栏通用底）。
class ZbChromeBar extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double? height;
  final EdgeInsetsGeometry padding;
  final bool bottomBorder;
  final bool topBorder;

  const ZbChromeBar({
    super.key,
    required this.child,
    this.color,
    this.height,
    this.padding = EdgeInsets.zero,
    this.bottomBorder = false,
    this.topBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? zb.chromeElevated,
        border: Border(
          bottom: bottomBorder
              ? BorderSide(color: zb.hairline, width: 1)
              : BorderSide.none,
          top: topBorder
              ? BorderSide(color: zb.hairline, width: 1)
              : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

/// 统一风格的图标按钮（外壳专用，尺寸与主题联动）。
class ZbIconAction extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final double size;
  final double extent;
  final Color? color;
  final Color? selectedColor;

  const ZbIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.selected = false,
    this.size = 19,
    this.extent = ZbTokens.toolButtonSize,
    this.color,
    this.selectedColor,
  });

  @override
  State<ZbIconAction> createState() => _ZbIconActionState();
}

class _ZbIconActionState extends State<ZbIconAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final enabled = widget.onTap != null;

    final Color fg;
    if (!enabled) {
      fg = zb.textPrimary.withValues(alpha: 0.30);
    } else if (widget.selected) {
      fg = widget.selectedColor ?? Theme.of(context).colorScheme.primary;
    } else {
      fg = widget.color ?? zb.textPrimary.withValues(alpha: 0.82);
    }

    final Color bg;
    if (widget.selected) {
      bg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.14);
    } else if (_pressed) {
      bg = zb.pressed;
    } else if (_hovered && enabled) {
      bg = zb.hover;
    } else {
      bg = Colors.transparent;
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 420),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: enabled
              ? () {
                  widget.onTap!.call();
                  Future.delayed(const Duration(milliseconds: 90), () {
                    if (mounted) setState(() => _pressed = false);
                  });
                }
              : null,
          child: AnimatedContainer(
            duration: ZbTokens.fast,
            curve: ZbTokens.easeOut,
            width: widget.extent,
            height: widget.extent,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.extent * 0.30),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.size, color: fg),
          ),
        ),
      ),
    );
  }
}

/// 空状态占位（书签/历史/下载为空时统一样式）
class ZbEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const ZbEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZbTokens.s7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 34,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.75)),
            ),
            const SizedBox(height: ZbTokens.s6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: zb.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: ZbTokens.s3),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: zb.textMuted, height: 1.5),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: ZbTokens.s6),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 页面级标题（各设置页/列表页统一使用）
class ZbSectionTitle extends StatelessWidget {
  final String text;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const ZbSectionTitle({
    super.key,
    required this.text,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
        ZbTokens.s6, ZbTokens.s5, ZbTokens.s6, ZbTokens.s2),
  });

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(fontSize: 11.5, color: zb.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 状态标识（地址栏左侧的安全图标等）
class ZbStatusDot extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String tooltip;

  const ZbStatusDot({
    super.key,
    required this.color,
    required this.icon,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 15, color: color),
    );
  }
}
