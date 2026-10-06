import 'web_enhance_settings.dart';

/// 生成注入页面的「网页增强」脚本（滤镜 / 无图 / 字号 / 行距 / 阅读模式）。
///
/// 所有脚本均为幂等：重复注入只更新既有 <style> 或切换阅读层，
/// 不会叠加多层效果。
class WebEnhanceScript {
  const WebEnhanceScript._();

  static const styleId = '__zb_enhance__';
  static const readerId = '__zb_reader__';

  /// 把 [settings] 应用到当前页面
  static String apply(WebEnhanceSettings s) {
    final filter = s.filter.cssFilter;
    final rules = <String>[];

    if (filter != null) {
      rules.add('html{filter:$filter !important;}');
    }
    if (s.noImage) {
      rules.add('img,picture,source,video[poster]{display:none !important;}');
      rules.add('*{background-image:none !important;}');
    }
    if ((s.fontScale - 1.0).abs() > 0.001) {
      final pct = (s.fontScale * 100).round();
      rules.add('body{font-size:$pct% !important;}');
    }
    if ((s.lineHeight - 1.6).abs() > 0.001) {
      rules.add(
          'body{line-height:${s.lineHeight.toStringAsFixed(2)} !important;}');
    }

    if (rules.isEmpty) return clearApply();

    final css = _jsString(rules.join(''));

    return '''
(function(){
  var el=document.getElementById('$styleId');
  if(!el){
    el=document.createElement('style');
    el.id='$styleId';
    (document.head||document.documentElement).appendChild(el);
  }
  el.textContent=$css;
  return 'applied';
})();
''';
  }

  /// 移除网页增强样式（恢复页面原样）
  static String clearApply() => '''
(function(){
  var el=document.getElementById('$styleId');
  if(el&&el.parentNode)el.parentNode.removeChild(el);
  return 'cleared';
})();
''';

  /// 切换阅读模式（无阅读层则创建，已存在则关闭）
  static String toggleReader(WebEnhanceSettings s) {
    return '''
(function(){
  var RID='$readerId';
  var old=document.getElementById(RID);
  if(old){
    if(old.parentNode)old.parentNode.removeChild(old);
    document.documentElement.style.overflow='';
    return 'closed';
  }
  var nodes=document.querySelectorAll('article,main,[role="main"],.article,.post,.content,.entry,section,div');
  var best=null,bestScore=0;
  for(var i=0;i<nodes.length;i++){
    var n=nodes[i];
    var txt=(n.innerText||'').trim();
    if(txt.length<400)continue;
    var links=n.getElementsByTagName('a').length;
    var score=txt.length-links*80;
    if(score>bestScore){bestScore=score;best=n;}
  }
  if(!best)best=document.body;
  if(!best)return 'none';

  var overlay=document.createElement('div');
  overlay.id=RID;
  overlay.setAttribute('style','position:fixed;inset:0;z-index:2147483646;'
    +'background:${_jsString(_readerBg(s))};color:${_jsString(_readerFg(s))};'
    +'overflow:auto;padding:32px 18px 64px;');

  var box=document.createElement('div');
  box.setAttribute('style','max-width:760px;margin:0 auto;'
    +'font-size:${(s.fontScale * 19).round()}px;line-height:${s.lineHeight.toStringAsFixed(2)};');

  var bar=document.createElement('div');
  bar.setAttribute('style','display:flex;align-items:center;gap:10px;margin-bottom:18px;');
  var close=document.createElement('button');
  close.textContent='关闭阅读模式';
  close.setAttribute('style','border:1px solid rgba(128,128,128,.5);background:transparent;'
    +'color:inherit;border-radius:999px;padding:6px 14px;font-size:13px;cursor:pointer;');
  close.onclick=function(){overlay.parentNode.removeChild(overlay);document.documentElement.style.overflow='';};
  var tag=document.createElement('span');
  tag.textContent='ZipBrowser 阅读模式';
  tag.setAttribute('style','font-size:12px;opacity:.6;');
  bar.appendChild(close);bar.appendChild(tag);
  box.appendChild(bar);

  var h=document.createElement('h1');
  h.textContent=document.title||'';
  h.setAttribute('style','font-size:1.6em;line-height:1.3;margin:0 0 20px;');
  box.appendChild(h);

  var text=(best.innerText||'').replace(/\\r/g,'');
  var parts=text.split(/\\n\\s*\\n/);
  for(var j=0;j<parts.length;j++){
    var p=(parts[j]||'').replace(/\\n/g,' ').trim();
    if(!p)continue;
    var pe=document.createElement('p');
    pe.textContent=p;
    pe.setAttribute('style','margin:0 0 1em;');
    box.appendChild(pe);
  }

  overlay.appendChild(box);
  document.documentElement.style.overflow='hidden';
  document.body.appendChild(overlay);
  return 'opened';
})();
''';
  }

  /// 关闭阅读模式（若有）
  static String closeReader() => '''
(function(){
  var el=document.getElementById('$readerId');
  if(el&&el.parentNode)el.parentNode.removeChild(el);
  document.documentElement.style.overflow='';
  return 'ok';
})();
''';

  /// 取回阅读模式是否开启
  static String readerState() =>
      "!!document.getElementById('$readerId')";

  static String _readerBg(WebEnhanceSettings s) {
    switch (s.filter) {
      case WebFilterMode.night:
        return '#ffffff'; // html 滤镜会反色，这里给白即得黑
      case WebFilterMode.sepia:
        return '#f6efe3';
      default:
        return '#ffffff';
    }
  }

  static String _readerFg(WebEnhanceSettings s) {
    switch (s.filter) {
      case WebFilterMode.night:
        return '#111111';
      default:
        return '#1f2d3d';
    }
  }

  static String _jsString(String s) {
    final escaped = s
        .replaceAll(r'\\', r'\\\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', '');
    return "'$escaped'";
  }
}
