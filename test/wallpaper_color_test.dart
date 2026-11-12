import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/core/theme/appearance_settings.dart';
import 'package:zip_browser/services/wallpaper_color.dart';

Uint8List solidRgba(int width, int height, int r, int g, int b, [int a = 255]) {
  final data = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    data[i * 4] = r;
    data[i * 4 + 1] = g;
    data[i * 4 + 2] = b;
    data[i * 4 + 3] = a;
  }
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('壁纸主色提取', () {
    test('纯色图返回该颜色', () {
      final color = WallpaperColor.dominantColorFromRgba(
        solidRgba(8, 8, 30, 90, 200),
        width: 8,
        height: 8,
      );
      expect(color, const Color.fromARGB(255, 30, 90, 200));
    });

    test('一半红一半蓝时优先低色相桶', () {
      final data = Uint8List(16 * 4);
      for (var i = 0; i < 16; i++) {
        final red = i < 8;
        data[i * 4] = red ? 255 : 0;
        data[i * 4 + 1] = 0;
        data[i * 4 + 2] = red ? 0 : 255;
        data[i * 4 + 3] = 255;
      }
      final color = WallpaperColor.dominantColorFromRgba(
        data,
        width: 16,
        height: 1,
      );
      expect(color, const Color.fromARGB(255, 255, 0, 0));
    });

    test('全灰图退化为平均色（不会返回 null）', () {
      final color = WallpaperColor.dominantColorFromRgba(
        solidRgba(4, 4, 128, 128, 128),
        width: 4,
        height: 4,
      );
      expect(color, const Color.fromARGB(255, 128, 128, 128));
    });

    test('全透明像素返回 null', () {
      final color = WallpaperColor.dominantColorFromRgba(
        solidRgba(4, 4, 200, 20, 20, 0),
        width: 4,
        height: 4,
      );
      expect(color, isNull);
    });

    test('尺寸或缓冲非法返回 null', () {
      expect(
        WallpaperColor.dominantColorFromRgba(Uint8List(0),
            width: 0, height: 0),
        isNull,
      );
      expect(
        WallpaperColor.dominantColorFromRgba(Uint8List(4),
            width: 4, height: 4),
        isNull,
      );
    });
  });

  group('莫奈取色源设置', () {
    test('默认取色源为 system，可切换到 wallpaper 并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await AppearanceSettings.create();
      expect(s.monetSource, MonetSource.system);

      await s.setMonetSource(MonetSource.wallpaper);
      expect(s.monetSource, MonetSource.wallpaper);

      final again = await AppearanceSettings.create();
      expect(again.monetSource, MonetSource.wallpaper);
    });

    test('systemSeedOverride 变化会通知监听者', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await AppearanceSettings.create();
      var notified = 0;
      s.addListener(() => notified++);

      s.setSystemSeedOverride(const Color(0xFF3366CC));
      expect(s.systemSeedOverride, const Color(0xFF3366CC));
      expect(notified, 1);

      s.setSystemSeedOverride(const Color(0xFF3366CC));
      expect(notified, 1);

      s.setSystemSeedOverride(null);
      expect(s.systemSeedOverride, isNull);
      expect(notified, 2);
    });
  });
}
