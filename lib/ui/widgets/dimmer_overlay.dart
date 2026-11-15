import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/config_service.dart';

/// 护眼调光覆盖层：按配置强度在最上层叠加不拦截触摸的黑色遮罩。
///
/// 遮罩位于应用 Navigator 之下，对话框等浮层不受影响，避免弹窗内容被压暗。
class DimmerOverlay extends StatelessWidget {
  const DimmerOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dimmer = context.watch<ConfigService>().dimmer;
    if (dimmer <= 0) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: dimmer),
            ),
          ),
        ),
      ],
    );
  }
}
