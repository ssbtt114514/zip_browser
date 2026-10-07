import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/style_mode.dart';
import '../../services/config_service.dart';

/// 根据 ConfigService.styleMode 在 Material 与 Cupertino 控件间切换。
bool _isCupertino(BuildContext context) =>
    context.select<ConfigService, bool>(
        (c) => c.styleMode == AppStyleMode.cupertino);

class AdaptiveSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AdaptiveSwitch(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 打开时滑块用「背景色」：Material 由 switchTheme 统一处理；
    // Cupertino 原生开启滑块即白色（背景色），轨道保持主题色，无需覆写。
    if (_isCupertino(context)) {
      return CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: theme.colorScheme.primary,
      );
    }
    return Switch(value: value, onChanged: onChanged);
  }
}

class AdaptiveSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const AdaptiveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (_isCupertino(context)) {
      return CupertinoSlider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        activeColor: primary,
      );
    }
    return Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
    );
  }
}

class AdaptiveButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool filled;
  final EdgeInsets? padding;

  const AdaptiveButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.filled = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (_isCupertino(context)) {
      return CupertinoButton(
        onPressed: onPressed,
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        borderRadius: BorderRadius.circular(10),
        color: filled ? primary : null,
        child: child,
      );
    }
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        child: child,
      );
    }
    return TextButton(onPressed: onPressed, child: child);
  }
}

/// 圆形进度指示器（Material ↔ Cupertino）
class AdaptiveProgressIndicator extends StatelessWidget {
  final double? size;
  const AdaptiveProgressIndicator({super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (_isCupertino(context)) {
      return CupertinoActivityIndicator(radius: (size ?? 20) / 2);
    }
    return SizedBox(
      width: size ?? 20,
      height: size ?? 20,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: primary),
    );
  }
}
