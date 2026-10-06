// com.zipbrowser.darkmode
// 演示：DOM 操作 + 通过 bridge 使用 storage 权限
(function () {
  var STYLE_ID = '__zb_dark_mode__';

  function applyDarkMode() {
    if (document.getElementById(STYLE_ID)) return;
    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = [
      'html { filter: invert(1) hue-rotate(180deg) !important; background: #111 !important; }',
      'img, picture, video, canvas, svg, [style*="background-image"] {',
      '  filter: invert(1) hue-rotate(180deg) !important;',
      '}'
    ].join('\n');
    (document.head || document.documentElement).appendChild(style);
  }

  // bridge 调用：统计注入次数（需要 storage 权限）
  try {
    window.zipBrowser
      .call('storage.get', { key: 'injected_count' })
      .then(function (value) {
        var next = (value || 0) + 1;
        return window.zipBrowser.call('storage.set', {
          key: 'injected_count',
          value: next
        });
      })
      .catch(function (err) {
        // 未授予权限或页面不支持时静默
      });
  } catch (e) {}

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', applyDarkMode);
  } else {
    applyDarkMode();
  }
})();
