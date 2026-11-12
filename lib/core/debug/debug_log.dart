/// 调试日志类别
enum DebugLogKind {
  log,
  info,
  warn,
  error,
  exception,
  network,
}

/// 一条来自页面调试钩子的日志
class DebugLogEntry {
  final DebugLogKind kind;
  final String message;

  /// 网络条目：请求 URL / 方法 / 状态码 / 耗时
  final String? url;
  final String? method;
  final int? status;
  final int? durationMs;

  final DateTime time;

  DebugLogEntry({
    required this.kind,
    required this.message,
    this.url,
    this.method,
    this.status,
    this.durationMs,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  /// 从注入脚本回传的 JSON 解析；非法内容返回 null
  static DebugLogEntry? fromJson(Map<dynamic, dynamic> json) {
    final rawKind = json['kind'];
    final kind = DebugLogKind.values.firstWhere(
      (k) => k.name == rawKind,
      orElse: () => DebugLogKind.log,
    );
    final message = json['message'];
    if (message is! String) return null;

    int? asInt(dynamic v) => v is num ? v.toInt() : null;
    String? asStr(dynamic v) => v is String ? v : null;

    return DebugLogEntry(
      kind: kind,
      message: message,
      url: asStr(json['url']),
      method: asStr(json['method']),
      status: asInt(json['status']),
      durationMs: asInt(json['durationMs']),
    );
  }

  String get kindLabel => switch (kind) {
        DebugLogKind.log => 'LOG',
        DebugLogKind.info => 'INFO',
        DebugLogKind.warn => 'WARN',
        DebugLogKind.error => 'ERROR',
        DebugLogKind.exception => 'UNCAUGHT',
        DebugLogKind.network => 'NET',
      };

  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  /// 单行展示文本（网络条目带方法 / 状态 / 耗时）
  String get displayText {
    if (kind == DebugLogKind.network) {
      final parts = <String>[
        if (method != null) method!,
        if (status != null) status.toString(),
        if (durationMs != null) '${durationMs}ms',
        url ?? message,
      ];
      return parts.join(' ');
    }
    return message;
  }
}
