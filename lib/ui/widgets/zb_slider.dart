import 'package:flutter/material.dart';

/// 统一风格的滑块：圆润粗轨道、圆形拖柄、按压放大、平滑的主题色高亮。
class ZbSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const ZbSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 5,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.14),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.16),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        thumbShape: const _PulseThumbShape(radius: 8),
        // 默认 RoundedRectSliderTrackShape 已提供圆角轨道
        trackShape: const RoundedRectSliderTrackShape(),
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: TextStyle(
          color: scheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// 圆形拖柄，按压时放大并带光晕。
class _PulseThumbShape extends SliderComponentShape {
  final double radius;
  const _PulseThumbShape({this.radius = 8});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius * 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final t = activationAnimation.value; // 0 未按压 → 1 按压
    final r = radius + t * 2.2;

    // 外圈光晕
    final halo = Paint()
      ..color = sliderTheme.overlayColor ?? Colors.transparent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r + 6 * (0.4 + t * 0.6), halo);

    // 主体
    final body = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r, body);

    // 白色高光点
    final hi = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center.translate(-r * 0.28, -r * 0.28), r * 0.32, hi);
  }
}
