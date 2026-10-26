import 'dart:convert';

import 'package:http/http.dart' as http;

/// 翻译服务：Google gtx 免费接口，失败时回落 MyMemory。
class TranslateService {
  TranslateService._();

  /// 目标语言（可按需扩展设置项）
  static const String defaultTarget = 'zh-CN';

  static Future<String> translate(String text, {String? target}) async {
    final t = target ?? defaultTarget;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    try {
      return await _google(trimmed, t);
    } catch (_) {
      return await _mymemory(trimmed, t);
    }
  }

  static Future<String> _google(String text, String target) async {
    final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx'
        '&sl=auto&tl=$target&dt=t&q=${Uri.encodeComponent(text)}');
    final resp = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    }).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('Google 翻译返回 ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final segs = data[0] as List?;
    if (segs == null) throw Exception('Google 翻译解析失败');
    final sb = StringBuffer();
    for (final seg in segs) {
      if (seg is List && seg.isNotEmpty) sb.write(seg[0]);
    }
    final out = sb.toString().trim();
    if (out.isEmpty) throw Exception('Google 翻译结果为空');
    return out;
  }

  static Future<String> _mymemory(String text, String target) async {
    final src = target.startsWith('zh') ? 'en' : 'zh-CN';
    final uri = Uri.parse(
        'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}'
        '&langpair=$src|$target');
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('MyMemory 返回 ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final out = data['responseData']?['translatedText'];
    if (out is! String || out.isEmpty) throw Exception('翻译失败');
    return out;
  }

  /// 提取选中文本（没有则取正文前 3000 字）。
  static Future<String> extractText(
      Future<String?> Function(String) evalJs) async {
    const script =
        "(function(){var s=window.getSelection&&String(window.getSelection());"
        "if(s&&s.trim())return s;"
        "return document.body?document.body.innerText.slice(0,3000):'';})()";
    return (await evalJs(script) ?? '').trim();
  }
}
