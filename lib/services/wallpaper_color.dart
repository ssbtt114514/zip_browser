import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 桌面壁纸主色提取。
///
/// 用于「壁纸取色」莫奈源：把壁纸缩略解码后做色相直方图投票，取主色作为
/// 莫奈种子。全部逻辑在 Dart 侧完成，不依赖平台插件。
class WallpaperColor {
  WallpaperColor._();

  /// 解码 [path] 指向的壁纸并提取主色；失败返回 null（调用方降级）。
  static Future<Color?> extractFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        return dominantColorFromRgba(
          data.buffer.asUint8List(),
          width: image.width,
          height: image.height,
        );
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (e) {
      debugPrint('壁纸取色失败：$e');
      return null;
    }
  }

  /// 从 RGBA 像素缓冲提取主色（纯函数，便于单测）。
  ///
  /// 策略：
  /// 1. 跳过透明、过暗、接近灰的像素（这类颜色做种子会得到灰蒙蒙的配色）；
  /// 2. 按色相分 24 个桶，权重为饱和度 × 明度，票数最高的桶胜出；
  /// 3. 返回该桶内像素的 RGB 均值；
  /// 4. 若没有满足条件的像素（如黑白壁纸），退化为全图平均色。
  static Color? dominantColorFromRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) return null;
    final pixelCount = width * height;
    if (rgba.length < pixelCount * 4) return null;

    const int buckets = 24;
    final weights = List<double>.filled(buckets, 0);
    final sums = List<List<int>>.generate(buckets, (_) => [0, 0, 0, 0]);

    var totalR = 0, totalG = 0, totalB = 0, totalN = 0;

    for (var i = 0; i < pixelCount; i++) {
      final o = i * 4;
      final r = rgba[o];
      final g = rgba[o + 1];
      final b = rgba[o + 2];
      final a = rgba[o + 3];
      if (a < 128) continue;

      totalR += r;
      totalG += g;
      totalB += b;
      totalN++;

      final hsv = _rgbToHsv(r, g, b);
      if (hsv.$2 < 0.12 || hsv.$3 < 0.10) continue;

      final bucket =
          ((hsv.$1 / 360.0 * buckets).floor()).clamp(0, buckets - 1).toInt();
      final weight = hsv.$2 * hsv.$3;
      weights[bucket] += weight;
      final sum = sums[bucket];
      sum[0] += r;
      sum[1] += g;
      sum[2] += b;
      sum[3] += 1;
    }

    var best = -1;
    var bestWeight = 0.0;
    for (var i = 0; i < buckets; i++) {
      if (weights[i] > bestWeight) {
        bestWeight = weights[i];
        best = i;
      }
    }

    if (best >= 0 && sums[best][3] > 0) {
      final sum = sums[best];
      final n = sum[3];
      return Color.fromARGB(255, sum[0] ~/ n, sum[1] ~/ n, sum[2] ~/ n);
    }
    if (totalN > 0) {
      return Color.fromARGB(
        255,
        totalR ~/ totalN,
        totalG ~/ totalN,
        totalB ~/ totalN,
      );
    }
    return null;
  }

  /// RGB → (色相 0-360, 饱和度 0-1, 明度 0-1)。
  static (double, double, double) _rgbToHsv(int r, int g, int b) {
    final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    final maxV = [rf, gf, bf].reduce((x, y) => x > y ? x : y);
    final minV = [rf, gf, bf].reduce((x, y) => x < y ? x : y);
    final delta = maxV - minV;

    double hue;
    if (delta == 0) {
      hue = 0;
    } else if (maxV == rf) {
      hue = 60 * (((gf - bf) / delta) % 6);
    } else if (maxV == gf) {
      hue = 60 * (((bf - rf) / delta) + 2);
    } else {
      hue = 60 * (((rf - gf) / delta) + 4);
    }
    if (hue < 0) hue += 360;

    final saturation = maxV == 0 ? 0.0 : delta / maxV;
    return (hue, saturation, maxV);
  }
}
