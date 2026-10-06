import 'package:flutter/material.dart';

/// 统一风格的工具栏图标按钮。
///
/// 交互/视觉：
/// - 按下时轻微缩小（AnimatedScale）并浮现圆角底色；
/// - 选中态以主题色淡底 + 主题色图标呈现，状态切换带淡入；
/// - 禁用态自动降低透明度。
class ZbToolButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final double size;

  const ZbToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.selected = false,
    this.size = 20,
  });

  @override
  State<ZbToolButton> createState() => _ZbToolButtonState();
}

class _ZbToolButtonState extends State<ZbToolButton> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;

    final Color iconColor = !enabled
        ? scheme.onSurface.withValues(alpha: 0.28)
        : widget.selected
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.78);

    final Color bg = widget.selected
        ? scheme.primary.withValues(alpha: 0.14)
        : _down
            ? scheme.onSurface.withValues(alpha: 0.08)
            : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setDown(true) : null,
        onTapCancel: enabled ? () => _setDown(false) : null,
        onTap: enabled
            ? () {
                widget.onTap?.call();
                // 抬起后短暂保持缩小再回弹，按压动画更清晰
                Future.delayed(const Duration(milliseconds: 95), () {
                  if (mounted) _setDown(false);
                });
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.86 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.size, color: iconColor),
          ),
        ),
      ),
    );
  }
}
