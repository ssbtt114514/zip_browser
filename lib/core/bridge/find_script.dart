/// 页面内查找器（注入页面的 JS），跨内核一致：
/// 高亮所有匹配、返回数量、上一个/下一个并自动滚动。
const String kFindScript = r'''
(function () {
  if (window.zipBrowserFind) return;
  var F = window.zipBrowserFind = {
    marks: [], count: 0, index: -1, query: '',

    start: function (q) {
      this.clear();
      q = String(q || '');
      this.query = q;
      if (!q || !document.body) return 0;
      var self = this;
      var nodes = [];
      var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function (n) {
          if (!n.nodeValue) return NodeFilter.FILTER_REJECT;
          var p = n.parentNode;
          if (!p) return NodeFilter.FILTER_REJECT;
          var tag = p.nodeName;
          if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'MARK' ||
              tag === 'NOSCRIPT' || tag === 'TEXTAREA')
            return NodeFilter.FILTER_REJECT;
          if (n.nodeValue.toLowerCase().indexOf(q.toLowerCase()) < 0)
            return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      var n;
      while ((n = walker.nextNode())) nodes.push(n);

      nodes.forEach(function (node) {
        var text = node.nodeValue;
        var lower = text.toLowerCase(), ql = q.toLowerCase();
        var frag = document.createDocumentFragment();
        var idx = 0;
        while (true) {
          var at = lower.indexOf(ql, idx);
          if (at < 0) {
            frag.appendChild(document.createTextNode(text.substring(idx)));
            break;
          }
          if (at > idx)
            frag.appendChild(document.createTextNode(text.substring(idx, at)));
          var mark = document.createElement('mark');
          mark.style.backgroundColor = '#fff176';
          mark.style.color = 'inherit';
          mark.appendChild(document.createTextNode(text.substring(at, at + q.length)));
          frag.appendChild(mark);
          self.marks.push(mark);
          idx = at + q.length;
        }
        node.parentNode.replaceChild(frag, node);
      });

      this.count = this.marks.length;
      this.index = this.count ? 0 : -1;
      this.updateActive();
      return this.count;
    },

    next: function (forward) {
      if (!this.count) return;
      this.index = (this.index + (forward ? 1 : -1) + this.count) % this.count;
      this.updateActive();
    },

    updateActive: function () {
      var self = this;
      this.marks.forEach(function (m, i) {
        m.style.backgroundColor = i === self.index ? '#ff9800' : '#fff176';
      });
      if (this.index >= 0 && this.marks[this.index])
        this.marks[this.index].scrollIntoView({ block: 'center' });
    },

    clear: function () {
      this.marks.slice().forEach(function (m) {
        var parent = m.parentNode;
        if (!parent) return;
        while (m.firstChild) parent.insertBefore(m.firstChild, m);
        parent.removeChild(m);
        if (parent.normalize) parent.normalize();
      });
      this.marks = []; this.count = 0; this.index = -1;
    }
  };
})();
''';
