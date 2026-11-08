/// 地址栏输入解析：URL / 域名补全 / 搜索词。
///
/// 识别规则（与内置新标签页的 JavaScript 判定保持一致）：
/// * 带 scheme：http(s) / ftp / ws(s) / file / data / about / blob / javascript，
///   scheme 大小写不敏感，`HTTP://` 也能识别；
/// * 协议相对地址：`//example.com`；
/// * 本机地址：localhost / 127.0.0.1 / [::1]，可带端口、路径；
/// * IPv4：四段且每段 0-255（`999.1.1.1` 不会被误判为地址）；
/// * 域名：支持中文等 Unicode 字母、显式端口（`:8080`）与 `/? #` 起始的路径；
/// * 粘贴的文本会先清洗：只取第一行、去掉零宽字符与「」<> 等包裹符号、
///   去掉句末中英文标点。
///
/// 判断"是不是地址"统一走 [isLikelyUrl]，避免地址栏、建议列表、
/// 剪贴板识别三处规则各写一份而逐渐漂移。
class UrlInput {
  UrlInput._();

  /// 允许直接交给内核加载的 scheme（其余 scheme 一律按搜索词处理）
  static const Set<String> _webSchemes = {
    'http',
    'https',
    'ftp',
    'ws',
    'wss',
    'file',
    'data',
    'about',
    'blob',
    'javascript',
  };

  static final RegExp _schemeRe =
      RegExp(r'^([a-z][a-z0-9+.\-]*):', caseSensitive: false);

  static final RegExp _spaceRe = RegExp(r'\s');

  static final RegExp _ipv4Re =
      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

  static final RegExp _ipv6Re =
      RegExp(r'^\[([0-9a-fA-F:]+)\](?::(\d{1,5}))?(.*)$');

  /// 域名标签：字母 / 数字 / 下划线 / 连字符，首尾不能是连字符
  static final RegExp _labelRe = RegExp(
    r'^[\p{L}\p{N}_](?:[\p{L}\p{N}_-]*[\p{L}\p{N}_])?$',
    unicode: true,
  );

  static final RegExp _letterStartRe =
      RegExp(r'^[\p{L}]', unicode: true);

  static final RegExp _digitsRe = RegExp(r'^\d+$');

  /// 句末标点（中英文），仅在识别地址时剥离
  static final RegExp _trailingPunctRe =
      RegExp(r'[。，、！？；：,.!?;:]+$');

  /// 全角句末标点与右包裹符号：即使输入带 scheme 也剥离
  static final RegExp _fullWidthTailRe =
      RegExp(r'[。，、！？；：）】」』》]+$');

  /// 地址里常见的成对包裹符号
  static const Map<String, String> _wrapPairs = {
    '<': '>',
    '>': '<',
    '(': ')',
    ')': '(',
    '[': ']',
    ']': '[',
    '{': '}',
    '}': '{',
    '「': '」',
    '」': '「',
    '『': '』',
    '』': '『',
    '【': '】',
    '】': '【',
    '《': '》',
    '》': '《',
    '"': '"',
    "'": "'",
    '“': '”',
    '”': '“',
    '‘': '’',
    '’': '‘',
  };

  /// 清洗输入：去首尾空白、只取第一行、去零宽字符与包裹符号。
  static String normalize(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return t;
    final nl = t.indexOf(RegExp(r'[\r\n]'));
    if (nl >= 0) t = t.substring(0, nl).trim();
    if (t.isEmpty) return t;
    t = t.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    var changed = true;
    while (changed && t.length > 1) {
      changed = false;
      final first = t.substring(0, 1);
      final last = t.substring(t.length - 1);
      final closing = _wrapPairs[first];
      if (closing != null && closing == last) {
        t = t.substring(1, t.length - 1).trim();
        changed = true;
      }
    }
    return t;
  }

  /// 把输入解析为最终地址：地址原样返回（裸域名补全 scheme），
  /// 其余视为搜索词并套用搜索引擎模板。
  static String resolve(
    String input, {
    required String searchEngineTemplate,
    required String homeDataUri,
  }) {
    final t = normalize(input);
    if (t.isEmpty) return homeDataUri;

    if (t == 'about:blank') return 'about:blank';
    if (t.startsWith('about:')) return homeDataUri;
    // about: 判定大小写不敏感
    if (t.toLowerCase().startsWith('about:')) return homeDataUri;

    final url = toUrl(t);
    if (url != null) return url;

    return searchUrl(searchEngineTemplate, t);
  }

  /// 判定输入是否是"可直接访问的地址"（URL / 域名 / 本机 IP）。
  ///
  /// 与 [resolve] 的区别：不做搜索引擎兜底——不是地址就返回 null，
  /// 调用方据此决定是导航、弹窗提示还是转搜索。二维码扫描结果与
  /// 剪贴板链接识别都使用它，避免把纯文本误当成网址打开。
  static String? tryResolveUrl(String input) {
    final t = normalize(input);
    if (t.isEmpty) return null;

    if (t == 'about:blank') return t;
    if (t.startsWith('about:')) return t;

    return toUrl(t);
  }

  /// 把输入转换成可访问的绝对地址；不是地址返回 null。
  static String? toUrl(String t) {
    if (t.isEmpty) return null;

    // 1. 完整 scheme（大小写不敏感）。
    //    注意 "localhost:3000" / "example.com:8080" 也会匹配 scheme 正则，
    //    必须同时要求 scheme 后跟 "//"（或 data:/about: 这类不带斜杠的写法），
    //    否则带端口的地址会被误判成未知 scheme 而送进搜索。
    final schemeMatch = _schemeRe.firstMatch(t);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!.toLowerCase();
      final rest = t.substring(schemeMatch.end);
      const bareSchemes = {'data', 'about', 'blob', 'javascript'};
      final isScheme = rest.startsWith('//') || bareSchemes.contains(scheme);
      if (isScheme && _webSchemes.contains(scheme)) {
        // 粘贴的"链接 + 说明文字"在首个空白处截断；查询串里的空格则编码保留
        var url = t;
        final ws = _spaceRe.firstMatch(url);
        if (ws != null) {
          final head = url.substring(0, ws.start);
          url = (head.contains('?') || head.contains('#'))
              ? url.replaceAll(' ', '%20')
              : head;
        }
        url = url.replaceFirst(_fullWidthTailRe, '');
        return url;
      }
      if (isScheme) return null;
      // 形如 host:port 的输入继续走下面的主机判定
    }

    // 2. 协议相对地址
    if (t.startsWith('//') && t.length > 2) {
      return _isValidAuthority(t.substring(2)) ? 'https:$t' : null;
    }

    // 3. 带空格的文本一律按搜索词处理
    if (_spaceRe.hasMatch(t)) return null;

    final core = t.replaceFirst(_trailingPunctRe, '');
    if (core.isEmpty) return null;

    // 4. 本机 / IP：http
    if (_isLocalAuthority(core)) return 'http://$core';

    // 5. 域名：https
    if (_isDomainAuthority(core)) return 'https://$core';

    return null;
  }

  /// 判定输入是否"看起来像地址"（供建议列表与首页脚本使用）。
  static bool isLikelyUrl(String input) {
    final t = normalize(input);
    if (t.isEmpty) return false;
    if (t.startsWith('//')) return _isValidAuthority(t.substring(2));
    final schemeMatch = _schemeRe.firstMatch(t);
    if (schemeMatch != null) {
      return _webSchemes.contains(schemeMatch.group(1)!.toLowerCase());
    }
    return toUrl(t) != null;
  }

  /// 从一段文本中提取第一个可访问地址（用于剪贴板识别）。
  ///
  /// 与地址栏不同，这里允许地址前后有文字，例如
  /// "看这个 https://example.com/a 挺好"。识别不到返回 null。
  static String? firstUrlIn(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;

    // 1. 任意位置的 scheme:// 地址（要求前一个字符是边界）
    final schemeRe =
        RegExp(r'[a-z][a-z0-9+.\-]*://[^\s<>"「」『』【】《》]+',
            caseSensitive: false);
    for (final m in schemeRe.allMatches(t)) {
      final before = m.start == 0 ? '' : t.substring(m.start - 1, m.start);
      if (before.isNotEmpty && RegExp(r'[a-z0-9+.\-]', caseSensitive: false).hasMatch(before)) {
        continue; // 属于更长单词的一部分（如 xhttp://）
      }
      final candidate = _cleanExtracted(m.group(0)!);
      if (candidate.isNotEmpty && isLikelyUrl(candidate)) return candidate;
    }

    // 2. www. 开头（可出现在文本中间）
    final www =
        RegExp(r'www\.[^\s<>"「」『』【】《》]+', caseSensitive: false)
            .firstMatch(t);
    if (www != null) {
      final candidate = _cleanExtracted('http://${www.group(0)!}');
      if (isLikelyUrl(candidate)) return candidate;
    }

    // 3. 裸域名：仅当整段文本没有空白时才认定（避免把句子里的词当网址）
    if (!_spaceRe.hasMatch(t)) {
      final bare = _cleanExtracted(t);
      if (bare.isNotEmpty && _isDomainAuthority(bare)) return 'https://$bare';
    }

    return null;
  }

  /// 生成搜索地址；模板缺少 `{q}` 时追加查询参数，避免关键词被静默丢弃。
  static String searchUrl(String template, String query) {
    final encoded = Uri.encodeQueryComponent(query);
    if (template.contains('{q}')) {
      return template.replaceFirst('{q}', encoded);
    }
    final sep = template.contains('?') ? '&' : '?';
    return '$template${sep}q=$encoded';
  }

  // —— 内部工具 ——

  /// 去掉提取结果的尾随标点与成对包裹符号
  static String _cleanExtracted(String raw) {
    var s = raw.trim();
    // 句中出现全角标点说明地址已结束（中文里网址后常紧跟"。"）
    final cut = RegExp(r'[。，、！？；：]').firstMatch(s);
    if (cut != null) s = s.substring(0, cut.start);
    s = s.replaceFirst(_trailingPunctRe, '');
    s = s.replaceAll(RegExp(r'[）)】」』》>\]]+$'), '');
    return s;
  }

  /// `host[:port][/path]` 形式是否合法（用于协议相对地址）
  static bool _isValidAuthority(String s) {
    if (s.isEmpty) return false;
    final host = _hostPart(s);
    if (host.isEmpty) return false;
    final lower = host.toLowerCase();
    return lower == 'localhost' ||
        _isIpv4(host) ||
        _ipv6Re.hasMatch(host) ||
        _isDomainHost(host);
  }

  /// 判断是否本机 / IP 地址（可带端口与路径）
  static bool _isLocalAuthority(String s) {
    final ipv6 = _ipv6Re.firstMatch(s);
    if (ipv6 != null) {
      if (!_validPort(ipv6.group(2))) return false;
      return true; // 任意 IPv6 字面量都按本机/局域网地址处理
    }
    final host = _hostPart(s).toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.localhost')) return true;
    return _isIpv4(host);
  }

  /// 判断是否域名（必须含点，TLD 为字母或 punycode，可带端口与路径）
  static bool _isDomainAuthority(String s) {
    final host = _hostPart(s);
    return _isDomainHost(host);
  }

  static bool _isDomainHost(String host) {
    if (host.isEmpty || host.length > 253) return false;
    final split = _splitPort(host);
    if (!_validPort(split.$2)) return false;
    final hostOnly = split.$1;
    if (hostOnly.isEmpty) return false;
    final labels = hostOnly.split('.');
    if (labels.length < 2) return false;
    for (final label in labels) {
      if (label.isEmpty || label.length > 63) return false;
      if (!_labelRe.hasMatch(label)) return false;
    }
    final tld = labels.last.toLowerCase();
    if (tld.startsWith('xn--')) return true;
    if (tld.length < 2) return false;
    if (_digitsRe.hasMatch(tld)) return false;
    return _letterStartRe.hasMatch(tld);
  }

  static bool _isIpv4(String host) {
    final m = _ipv4Re.firstMatch(host);
    if (m == null) return false;
    for (var i = 1; i <= 4; i++) {
      final v = int.tryParse(m.group(i)!);
      if (v == null || v > 255) return false;
    }
    return true;
  }

  /// 取 `host[:port][/path]` 中的 host 部分（保留 IPv6 的方括号写法）
  static String _hostPart(String s) {
    final ipv6 = _ipv6Re.firstMatch(s);
    if (ipv6 != null) return '[${ipv6.group(1)}]';
    var end = s.length;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '/' || c == '?' || c == '#') {
        end = i;
        break;
      }
    }
    final authority = s.substring(0, end);
    final colon = authority.lastIndexOf(':');
    if (colon < 0) return authority;
    final port = authority.substring(colon + 1);
    if (!_validPort(port)) return authority;
    return authority.substring(0, colon);
  }

  /// 拆分 `host:port` 为 (host, port)
  static (String, String?) _splitPort(String s) {
    final colon = s.lastIndexOf(':');
    if (colon < 0) return (s, null);
    final port = s.substring(colon + 1);
    if (!_validPort(port)) return (s, null);
    return (s.substring(0, colon), port);
  }

  static bool _validPort(String? port) {
    if (port == null) return true;
    if (port.isEmpty || !_digitsRe.hasMatch(port)) return false;
    final v = int.tryParse(port);
    return v != null && v >= 1 && v <= 65535;
  }
}
