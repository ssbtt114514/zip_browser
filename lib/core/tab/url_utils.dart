/// 地址栏输入解析：URL / 域名补全 / 搜索词
class UrlInput {
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
}
