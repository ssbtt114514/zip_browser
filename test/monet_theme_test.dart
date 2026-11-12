import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/core/theme/appearance_settings.dart';
import 'package:zip_browser/core/theme/monet_engine.dart';
import 'package:zip_browser/core/theme/theme_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('莫奈配色优先级', () {
    test('wallpaper + 系统种子覆盖时使用覆盖色', () async {
      SharedPreferences.setMockInitialValues({
        'appearance.monet': true,
        'appearance.monet_source': 'wallpaper',
      });
      final s = await AppearanceSettings.create();
      const override = Color(0xFFBB3355);
      s.setSystemSeedOverride(override);

      final scheme = ThemeEngine.light(s).colorScheme;
      final expected =
          ZbMonetEngine.schemeFromSeed(override, Brightness.light);
      expect(scheme.primary, expected.primary);
    });

    test('builtin 源忽略系统种子覆盖，使用手动种子色', () async {
      SharedPreferences.setMockInitialValues({
        'appearance.monet': true,
        'appearance.monet_source': 'builtin',
        'appearance.seed_color': 0xFF0B84A5,
      });
      final s = await AppearanceSettings.create();
      s.setSystemSeedOverride(const Color(0xFFBB3355));

      final scheme = ThemeEngine.light(s).colorScheme;
      final expected =
          ZbMonetEngine.schemeFromSeed(const Color(0xFF0B84A5), Brightness.light);
      expect(scheme.primary, expected.primary);
    });

    test('关闭莫奈时使用标准 Material 3 种子方案', () async {
      SharedPreferences.setMockInitialValues({
        'appearance.monet': false,
        'appearance.seed_color': 0xFF0B84A5,
      });
      final s = await AppearanceSettings.create();
      s.setSystemSeedOverride(const Color(0xFFBB3355));

      final scheme = ThemeEngine.light(s).colorScheme;
      expect(
        scheme.primary,
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B84A5),
          brightness: Brightness.light,
        ).primary,
      );
    });
  });
}
