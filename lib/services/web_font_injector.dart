import 'dart:convert';

/// 生成「网页字体」覆盖脚本。
///
/// 只覆盖正文文本元素，跳过 `pre` / `code` / `kbd` / `samp` 与编辑器类
/// `contenteditable`，避免破坏代码高亮与在线编辑器排版。
/// [family] 为空时返回 null（跟随页面自身字体）。
class WebFontInjector {
  WebFontInjector._();

  static String? buildScript(String family) {
    final trimmed = family.trim();
    if (trimmed.isEmpty) return null;
    final familyJson = jsonEncode(trimmed);
    return _template.replaceFirst('__FAMILY__', familyJson);
  }

  static const String _template = r'''
(function(){
  var family = __FAMILY__;
  if (!family) return;
  var id = 'zb-web-font';
  function css(){
    return 'html,body,body *:not(pre):not(code):not(kbd):not(samp):not([contenteditable="true"])' +
      '{font-family:' + family + ',sans-serif !important;}';
  }
  function apply(){
    if (!document.head) return false;
    var el = document.getElementById(id);
    if (!el) {
      el = document.createElement('style');
      el.id = id;
      document.head.appendChild(el);
    }
    if (el.textContent !== css()) el.textContent = css();
    return true;
  }
  if (!apply()) {
    document.addEventListener('DOMContentLoaded', apply);
  }
})();
''';
}
