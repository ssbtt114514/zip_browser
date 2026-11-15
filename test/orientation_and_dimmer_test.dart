import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/core/orientation_mode.dart';
import 'package:zip_browser/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppOrientationMode', () {
    test('解析未知值回落到跟随系统', () {
      expect(parseAppOrientationMode(null), AppOrientationMode.system);
      expect(parseAppOrientationMode('foo'), AppOrientationMode.system);
    });

    test('解析已知值并给出方向列表', () {
      expect(parseAppOrientationMode('portrait'), AppOrientationMode.portrait);
      expect(parseAppOrientationMode('landscape'), AppOrientationMode.landscape);
      expect(AppOrientationMode.system.preferredOrientations, isEmpty);
      expect(AppOrientationMode.portrait.preferredOrientations.length, 2);
      expect(AppOrientationMode.landscape.preferredOrientations.length, 2);
    });
  });

  group('ConfigService 方向与调光', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('默认值：跟随系统且无调光', () async {
      final config = await ConfigService.create();
      expect(config.orientation, AppOrientationMode.system);
      expect(config.dimmer, 0);
    });

    test('方向选择可持久化', () async {
      final config = await ConfigService.create();
      await config.setOrientation(AppOrientationMode.landscape);
      expect(config.orientation, AppOrientationMode.landscape);

      final reloaded = await ConfigService.create();
      expect(reloaded.orientation, AppOrientationMode.landscape);
    });

    test('调光强度被限制在 0.0-0.6', () async {
      final config = await ConfigService.create();
      await config.setDimmer(0.9);
      expect(config.dimmer, 0.6);
      await config.setDimmer(-1);
      expect(config.dimmer, 0);
      await config.setDimmer(0.35);
      expect(config.dimmer, closeTo(0.35, 1e-9));
    });
  });
}
