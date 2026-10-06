import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/palettes/core_palette.dart';
import 'package:provider/provider.dart';

import '../../core/app_keys.dart';
import '../../core/theme/appearance_settings.dart';
import '../../core/theme/style_mode.dart';
import '../../core/theme/theme_engine.dart';
import '../../services/config_service.dart';

/// 监听 [AppearanceSettings] 与 ConfigService.styleMode，实时重建主题。
class ThemeBuilder extends StatelessWidget {
  final Widget child;
  const ThemeBuilder({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppearanceSettings>();
    final monet = context.watch<CorePalette?>();
    final styleMode =
        context.select<ConfigService, AppStyleMode>((c) => c.styleMode);

    return _InheritedTheme(
      settings: s,
      child: Builder(
        builder: (ctx) {
          return MaterialApp(
            title: 'Zip Browser',
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: messengerKey,
            debugShowCheckedModeBanner: false,
            theme: ThemeEngine.light(s, monet: monet, styleMode: styleMode),
            darkTheme: ThemeEngine.dark(s, monet: monet, styleMode: styleMode),
            themeMode: s.flutterThemeMode,
            builder: (mctx, navChild) {
              final theme = Theme.of(mctx);
              return CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: theme.brightness,
                  primaryColor: theme.colorScheme.primary,
                  scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
                  barBackgroundColor: theme.colorScheme.surface,
                  textTheme: CupertinoTextThemeData(
                    primaryColor: theme.colorScheme.primary,
                  ),
                ),
                child: navChild!,
              );
            },
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
