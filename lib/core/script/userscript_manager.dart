import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../kernel/kernel_types.dart';
import 'userscript_parser.dart';

/// 已安装的用户脚本
class InstalledUserScript {
  final String id;
  final UserScriptMeta meta;
  final bool enabled;
  final DateTime installedAt;
  final File file;

  const InstalledUserScript({
    required this.id,
    required this.meta,
    required this.enabled,
    required this.installedAt,
    required this.file,
  });

  /// 转换为内核可注入的 UserScript
  UserScript toKernelScript() {
    return UserScript(
      source: meta.executableSource,
      matches: meta.matches,
      timing: meta.runAt == 'document-start'
          ? UserScriptInjectionTiming.documentStart
          : UserScriptInjectionTiming.documentEnd,
      pluginId: 'userscript:$id',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': meta.name,
        'namespace': meta.namespace,
        'version': meta.version,
        'enabled': enabled,
        'installed_at': installedAt.toIso8601String(),
      };
}

/// 用户脚本管理器：导入 / 启停 / 收集注入脚本。
/// 脚本存储在 [scriptsDir]，每个脚本一个文件，元数据缓存到 index.json。
class UserscriptManager extends ChangeNotifier {
  final Directory scriptsDir;
  final List<InstalledUserScript> _scripts = [];

  UserscriptManager({required this.scriptsDir}) {
    if (!scriptsDir.existsSync()) {
      scriptsDir.createSync(recursive: true);
    }
    loadAll();
  }

  List<InstalledUserScript> get scripts => List.unmodifiable(_scripts);

  List<InstalledUserScript> get enabledScripts =>
      _scripts.where((s) => s.enabled).toList();

  /// 收集所有启用脚本，供内核注入
  List<UserScript> collectScripts() {
    return enabledScripts.map((s) => s.toKernelScript()).toList();
  }

  void loadAll() {
    _scripts.clear();
    if (!scriptsDir.existsSync()) return;

    final indexFile = File(p.join(scriptsDir.path, 'index.json'));
    Map<String, dynamic> index = {};
    if (indexFile.existsSync()) {
      try {
        index = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {
        index = {};
      }
    }

    for (final entity in scriptsDir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.user.js') && !name.endsWith('.js')) continue;

      try {
        final source = entity.readAsStringSync();
        final meta = UserScriptParser.parse(source);
        if (meta == null) continue;

        final id = (index[name] as Map?)?['id'] as String? ??
            'us_${DateTime.now().microsecondsSinceEpoch}';
        final enabled = (index[name] as Map?)?['enabled'] as bool? ?? true;
        final installedAt = DateTime.tryParse(
                (index[name] as Map?)?['installed_at'] as String? ?? '') ??
            DateTime.now();

        _scripts.add(InstalledUserScript(
          id: id,
          meta: meta,
          enabled: enabled,
          installedAt: installedAt,
          file: entity,
        ));
      } catch (_) {
        // 跳过无法解析的脚本
      }
    }
    _scripts.sort((a, b) => a.meta.name.compareTo(b.meta.name));
    notifyListeners();
  }

  /// 从源码导入 userscript
  InstalledUserScript? importFromSource(String source, {String? filename}) {
    final meta = UserScriptParser.parse(source);
    if (meta == null) return null;

    final id = 'us_${DateTime.now().microsecondsSinceEpoch}';
    final safeName = (filename ?? '${meta.name}.user.js')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File(p.join(scriptsDir.path, safeName));
    file.writeAsStringSync(source);

    _persistIndex();
    loadAll();
    return _scripts.firstWhere((s) => s.id == id, orElse: () => _scripts.first);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    for (final s in _scripts) {
      if (s.id == id) {
        // 重新构造（enabled 是 final）
        final idx = _scripts.indexOf(s);
        _scripts[idx] = InstalledUserScript(
          id: s.id,
          meta: s.meta,
          enabled: enabled,
          installedAt: s.installedAt,
          file: s.file,
        );
        break;
      }
    }
    await _persistIndex();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final target = _scripts.firstWhereOrNull((s) => s.id == id);
    if (target == null) return;
    try {
      target.file.deleteSync();
    } catch (_) {}
    _scripts.removeWhere((s) => s.id == id);
    await _persistIndex();
    notifyListeners();
  }

  Future<void> _persistIndex() async {
    final index = <String, dynamic>{};
    for (final s in _scripts) {
      index[p.basename(s.file.path)] = {
        'id': s.id,
        'name': s.meta.name,
        'enabled': s.enabled,
        'installed_at': s.installedAt.toIso8601String(),
      };
    }
    final file = File(p.join(scriptsDir.path, 'index.json'));
    await file.writeAsString(jsonEncode(index));
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
