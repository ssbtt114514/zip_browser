import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_keys.dart';
import '../../core/theme/appearance_settings.dart';
import '../../core/theme/theme_engine.dart';

/// 监听 [AppearanceSettings] 变化，实时重建 [MaterialApp] 的主题。
/// 用法：将 [MaterialApp] 作为 child 传入，theme/darkTheme/themeMode 由本组件提供。
class ThemeBuilder extends StatelessWidget {
  final Widget child;
  const ThemeBuilder({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppearanceSettings>();
    return _InheritedTheme(
      settings: s,
      child: Builder(
        builder: (ctx) {
          return MaterialApp(
            title: 'Zip Browser',
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: messengerKey,
            debugShowCheckedModeBanner: false,
            theme: ThemeEngine.light(s),
            darkTheme: ThemeEngine.dark(s),
            themeMode: s.flutterThemeMode,
            home: child,
          );
        },
      ),
    );
  }
}

class _InheritedTheme extends InheritedWidget {
  final AppearanceSettings settings;
  const _InheritedTheme({required this.settings, required super.child});

  @override
  bool updateShouldNotify(covariant _InheritedTheme oldWidget) =>
      settings != oldWidget.settings;
}
