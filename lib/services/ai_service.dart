import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config_service.dart';

/// AI 解读：调用用户自配的 OpenAI 兼容接口（chat/completions）。
///
/// 需要在「设置 → AI 解读」里填好 API 地址 / Key / 模型。
/// 常见配置示例：
///   - OpenAI 官方：https://api.openai.com/v1 + gpt-4o-mini
///   - DeepSeek：  https://api.deepseek.com/v1 + deepseek-chat
///   - 通义/月暗/Kimi 等兼容网关同理
class AiService {
  AiService._();

  static const String kDefaultBaseUrl = 'https://api.openai.com/v1';
  static const String kDefaultModel = 'gpt-4o-mini';

  /// 是否已配置可用（有 Key 即认为可用）
  static bool isConfigured(ConfigService config) =>
      config.aiApiKey.trim().isNotEmpty;

  /// 发送一轮对话。
  static Future<String> chat(
    ConfigService config,
    String userPrompt, {
    String? system,
    int maxTokens = 1024,
  }) async {
    final base = config.aiBaseUrl.trim().isEmpty
        ? kDefaultBaseUrl
        : config.aiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final model =
        config.aiModel.trim().isEmpty ? kDefaultModel : config.aiModel.trim();
    final key = config.aiApiKey.trim();

    final resp = await http.post(
      Uri.parse('$base/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'messages': [
          if (system != null && system.isNotEmpty)
            {'role': 'system', 'content': system},
          {'role': 'user', 'content': userPrompt},
        ],
      }),
    ).timeout(const Duration(seconds: 60));

    if (resp.statusCode != 200) {
      throw Exception('AI 接口返回 ${resp.statusCode}：'
          '${resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes))
        as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('AI 接口未返回内容');
    }
    final msg = choices[0]['message']['content'];
    return (msg is String) ? msg.trim() : jsonEncode(msg);
  }

  /// 提取当前页面正文文本（供 AI 阅读）。
  static Future<String> extractPageText(
      Future<String?> Function(String) evalJs) async {
    const script =
        "(function(){var s=window.getSelection&&String(window.getSelection());"
        "if(s&&s.length>60)return s;"
        "var t=document.body?document.body.innerText:'';"
        "return t.replace(/\\s+\\n/g,'\\n').slice(0,6000);})()";
    final raw = await evalJs(script);
    return (raw ?? '').trim();
  }
}
