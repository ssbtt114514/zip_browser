/// 用户脚本（Tampermonkey / Greasemonkey 格式）的元数据与源码。
class UserScriptMeta {
  final String name;
  final String? namespace;
  final String? description;
  final String? version;
  final String? author;
  final List<String> matches;
  final List<String> excludes;
  final String runAt; // document-start / document-end / document-idle
  final List<String> grants;
  final String source;

  const UserScriptMeta({
    required this.name,
    this.namespace,
    this.description,
    this.version,
    this.author,
    this.matches = const [],
    this.excludes = const [],
    this.runAt = 'document-end',
    this.grants = const [],
    required this.source,
  });

  /// 生成用于在页面中执行的完整源码（去除元数据头）
  String get executableSource {
    final lines = source.split('\n');
    final buffer = StringBuffer();
    bool inMeta = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == '// ==UserScript==') {
        inMeta = true;
        continue;
      }
      if (trimmed == '// ==/UserScript==') {
        inMeta = false;
        continue;
      }
      if (!inMeta) buffer.writeln(line);
    }
    return buffer.toString();
  }
}

/// 解析 `.user.js` 源码中的 `// ==UserScript==` 元数据块。
class UserScriptParser {
  static UserScriptMeta? parse(String source) {
    final meta = <String, List<String>>{};
    final lines = source.split('\n');
    bool inMeta = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == '// ==UserScript==') {
        inMeta = true;
        continue;
      }
      if (trimmed == '// ==/UserScript==') {
        inMeta = false;
        break;
      }
      if (!inMeta) continue;

      // 匹配 // @key value  或  // @key
      final m = RegExp(r'^//\s*@(\S+)(?:\s+(.*))?$').firstMatch(trimmed);
      if (m == null) continue;
      final key = m.group(1)!.toLowerCase();
      final value = (m.group(2) ?? '').trim();
      meta.putIfAbsent(key, () => []).add(value);
    }

    final nameList = meta['name'];
    if (nameList == null || nameList.isEmpty || nameList.first.isEmpty) {
      // 没有 name 则用文件名占位（调用方提供）
      return null;
    }

    final name = nameList.first;
    final matches = (meta['match'] ?? []).where((s) => s.isNotEmpty).toList();
    final excludes = (meta['exclude'] ?? []).where((s) => s.isNotEmpty).toList();
    final grants = (meta['grant'] ?? []).where((s) => s.isNotEmpty).toList();
    final runAt = (meta['run-at']?.first ?? 'document-end').toLowerCase();

    return UserScriptMeta(
      name: name,
      namespace: meta['namespace']?.firstOrNull,
      description: meta['description']?.firstOrNull,
      version: meta['version']?.firstOrNull,
      author: meta['author']?.firstOrNull,
      matches: matches.isEmpty ? ['<all_urls>'] : matches,
      excludes: excludes,
      runAt: runAt,
      grants: grants,
      source: source,
    );
  }

  /// 判断一段文本是否是 userscript（包含元数据头）
  static bool looksLikeUserscript(String source) {
    return source.contains('// ==UserScript==') &&
        source.contains('// ==/UserScript==');
  }
}

extension on List<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
