/// 地址栏输入解析：URL / 域名补全 / 搜索词
class UrlInput {
  /// 把输入解析为最终地址：URL 原样返回（域名自动补全 scheme），
  /// 其余视为搜索词并套用搜索引擎模板。
  static String resolve(
    String input, {
    required String searchEngineTemplate,
    required String homeDataUri,
  }) {
    final t = input.trim();
    if (t.isEmpty) return homeDataUri;

    if (t == 'about:blank') return 'about:blank';
    if (t.startsWith('about:')) return homeDataUri;

    const schemes = ['http://', 'https://', 'file://', 'data:', 'javascript:'];
    for (final scheme in schemes) {
      if (t.startsWith(scheme)) return t;
    }

    // localhost / 本机 IP
    if (RegExp(r'^(localhost|127\.0\.0\.1)(:\d+)?(\/.*)?$').hasMatch(t)) {
      return 'http://$t';
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(\/.*)?$').hasMatch(t)) {
      return 'http://$t';
    }

    // 形如 domain.tld（可含端口/路径），且无空格
    final domainRegex =
        RegExp(r'^([\w-]+\.)+[a-z]{2,}(:\d+)?(\/.*)?$', caseSensitive: false);
    if (!t.contains(' ') && domainRegex.hasMatch(t)) return 'https://$t';

    // 其余视为搜索词
    return searchEngineTemplate.replaceFirst(
      '{q}',
      Uri.encodeQueryComponent(t),
    );
  }

  /// 判定输入是否是"可直接访问的地址"（URL / 域名 / 本机 IP）。
  ///
  /// 与 [resolve] 的区别：不做搜索引擎兜底——不是地址就返回 null，
  /// 调用方据此决定是导航、弹窗提示还是转搜索。二维码扫描结果与
  /// 剪贴板链接识别都使用它，避免把纯文本误当成网址打开。
  static String? tryResolveUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;

    if (t == 'about:blank') return 'about:blank';
    if (t.startsWith('about:')) return t;

    const schemes = ['http://', 'https://', 'file://', 'data:', 'javascript:'];
    for (final scheme in schemes) {
      if (t.startsWith(scheme)) return t;
    }

    if (RegExp(r'^(localhost|127\.0\.0\.1)(:\d+)?(\/.*)?$').hasMatch(t)) {
      return 'http://$t';
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(\/.*)?$').hasMatch(t)) {
      return 'http://$t';
    }

    final domainRegex =
        RegExp(r'^([\w-]+\.)+[a-z]{2,}(:\d+)?(\/.*)?$', caseSensitive: false);
    if (!t.contains(' ') && domainRegex.hasMatch(t)) return 'https://$t';

    return null;
  }
}
