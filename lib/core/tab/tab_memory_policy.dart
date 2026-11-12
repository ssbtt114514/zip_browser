import 'dart:convert';

/// 后台标签休眠策略与页面快照脚本。
///
/// 休眠 = 记录 URL / 滚动位置 / 表单值 → 卸载页面（about:blank 释放渲染
/// 进程与 JS 堆）→ 用户切回时重新加载并恢复快照。
/// 固定标签、隐私标签、前台标签不参与休眠。
class TabMemoryPolicy {
  TabMemoryPolicy._();

  /// 是否满足休眠条件
  static bool shouldSleep({
    required bool isActive,
    required bool pinned,
    required bool privateTab,
    required int tabCount,
    required Duration idle,
    required Duration threshold,
    int minTabs = 4,
  }) {
    if (isActive || pinned || privateTab) return false;
    if (tabCount <= minTabs) return false;
    return idle >= threshold;
  }

  /// 解析内核返回的快照（兼容 JSON 字符串被再次编码的情况）
  static Map<String, dynamic>? decodeSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    dynamic value = raw;
    for (var i = 0; i < 3; i++) {
      if (value is Map) return Map<String, dynamic>.from(value);
      if (value is! String) return null;
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  /// 采集页面快照（返回 JSON 字符串表达式）
  static const String snapshotScript = r'''
(function(){
  function values(){
    var out = {};
    try {
      var els = document.querySelectorAll('input[name],textarea[name],select[name]');
      for (var i = 0; i < els.length && i < 40; i++){
        var el = els[i];
        if (!el.name) continue;
        if (el.type === 'password' || el.type === 'file') continue;
        if (el.type === 'checkbox' || el.type === 'radio') {
          out[el.name] = el.checked;
        } else {
          out[el.name] = el.value;
        }
      }
    } catch (e) {}
    return out;
  }
  try {
    return JSON.stringify({
      url: location.href,
      scrollX: Math.round(scrollX || 0),
      scrollY: Math.round(scrollY || 0),
      values: values()
    });
  } catch (e) { return ''; }
})()
''';

  /// 生成恢复快照脚本
  static String restoreScript({
    required double scrollX,
    required double scrollY,
    required Map<String, dynamic> values,
  }) {
    final entries = values.entries
        .map((e) {
          if (e.value is bool) return '${_key(e.key)}:${e.value == true}';
          return '${_key(e.key)}:${_str('${e.value}')}';
        })
        .join(',');
    return '''
(function(){
  var values = {$entries};
  function restore(){
    try {
      var els = document.querySelectorAll('input[name],textarea[name],select[name]');
      for (var i = 0; i < els.length; i++){
        var el = els[i];
        if (!el.name || !(el.name in values)) continue;
        try {
          if (el.type === 'checkbox' || el.type === 'radio') {
            el.checked = !!values[el.name];
          } else {
            el.value = values[el.name];
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
          }
        } catch (e) {}
      }
      window.scrollTo($scrollX, $scrollY);
    } catch (e) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', restore);
  } else {
    restore();
    setTimeout(restore, 300);
  }
})();
''';
  }

  static String _key(String k) => _str(k);

  static String _str(String v) {
    final escaped = v
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '');
    return '"$escaped"';
  }
}
