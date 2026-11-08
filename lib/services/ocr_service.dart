import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ai_service.dart';
import 'config_service.dart';

/// 文字识别（OCR）服务。
///
/// 能力边界（诚实声明）：
/// - Android：内置离线识别，ML Kit Text Recognition v2 中文脚本
///   （原生库由 tool/patch_android_gradle.py 注入 app gradle，首次识别
///   前可能需要联网下载模型）。
/// - Windows / Linux / macOS：走用户在「设置 → AI 解读」配置的
///   OpenAI 兼容多模态接口做视觉取字（要求模型支持图片输入）。
class OcrService {
  OcrService._();

  /// 当前平台是否有内置离线识别（仅 Android）。
  static bool get localOcrAvailable => Platform.isAndroid;

  /// AI 视觉识别是否可用（已配置 AI 接口）。
  static bool aiOcrAvailable(ConfigService config) =>
      AiService.isConfigured(config);

  /// 识别本地图片文件中的文字。
  static Future<String> recognizeImageFile(
    String path,
    ConfigService config,
  ) async {
    if (localOcrAvailable) {
      return _mlKitRecognize(path);
    }
    if (!aiOcrAvailable(config)) {
      throw Exception(
          '当前平台没有内置离线文字识别，请先到「设置 → AI 解读」'
          '配置一个支持图片输入的 AI 接口（如 gpt-4o-mini）');
    }
    final bytes = await File(path).readAsBytes();
    return AiService.ocrImage(config, bytes, mime: _mimeOf(path));
  }

  /// Android 内置识别：ML Kit 中文脚本，失败时回落拉丁脚本
  /// （纯英文图片在中文识别器下偶发漏识别）。
  static Future<String> _mlKitRecognize(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    String text;
    try {
      final recognizer =
          TextRecognizer(script: TextRecognitionScript.chinese);
      try {
        final result = await recognizer.processImage(inputImage);
        text = result.text;
      } finally {
        recognizer.close();
      }
    } catch (_) {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(inputImage);
        text = result.text;
      } finally {
        recognizer.close();
      }
    }
    return text.trim();
  }

  static String _mimeOf(String path) {
    final ext = path.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      _ => 'image/png',
    };
  }
}
