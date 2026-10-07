import 'dart:async';

import 'package:flutter/services.dart';

/// 剪贴板链接检测。
///
/// 周期性读取剪贴板文本，从中识别 URL，去重后通过 [links] 广播。
/// 用途：用户复制了链接（微信 / 短信 / 其它 App），回到浏览器后提示
/// "检测到剪贴板链接 → 访问"，避免手动粘贴。
///
/// 注意：
/// * 只在宿主进程存活期间轮询（BrowserShell 挂载时 start / 销毁时 stop）；
/// * Android 13+ 前台读取剪贴板会弹一次性系统提示，属正常行为；
/// * 桌面端同样适用（Windows / Linux 剪贴板可读）。
class ClipboardLinkDetector {
  ClipboardLinkDetector({this.interval = const Duration(seconds: 3)});

  /// 轮询间隔。太短会频繁读取剪贴板（耗电/打扰），默认 3 秒。
  final Duration interval;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  Timer? _timer;
  bool _running = false;

  /// 上一次读到的剪贴板文本（内容没变就不重复广播）
  String _lastText = '';

  /// 最近一次提示过的链接（防止同一链接反复弹提示）
  String _lastNotified = '';

  /// 识别出的链接流（每条都是补全过 scheme 的完整地址）
  Stream<String> get links => _controller.stream;

  /// 从一段文本中提取第一个 URL；提取不到返回 null。
  ///
  /// 优先级：带 scheme 的完整 URL → www. 开头 → 裸域名/IP。
  static String? extractUrl(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;

    // 完整 URL（http/https/data/file 等，允许尾部被标点截断）
    const schemes = ['http://', 'https://', 'file://', 'data:', 'ftp://'];
    for (final scheme in schemes) {
      final idx = t.indexOf(scheme);
      if (idx >= 0) {
        var end = t.indexOf('\n', idx);
        if (end < 0) end = t.length;
        var url = t.substring(idx, end).trim();
        // 去掉常见尾部标点（中文/英文语境）
        url = url.replaceAll(RegExp(r'[，。！？、；：,.!?;:]+$'), '');
        if (url.isNotEmpty) return url;
      }
    }

    // www. 开头 → 补 http://（host 部分不含引号，字符类不列引号避免 raw 串转义）
    final www = RegExp(r"www\.[^\s<>\[\]{}]+", caseSensitive: false)
        .firstMatch(t);
    if (www != null) {
      var host = www.group(0)!.replaceAll(
          RegExp(r'[，。！？、；：,.!?;:]+$'), '');
      return 'http://$host';
    }

    // 裸域名 domain.tld（可带端口/路径），无空格且非纯数字
    final domain =
        RegExp(r'([\w-]+\.)+[a-z]{2,}(:\d+)?(\/[\w\-./~?%=&+#:]*)?',
                caseSensitive: false)
            .firstMatch(t);
    if (domain != null && !t.contains(' ')) {
      final host = domain.group(0)!.replaceAll(
          RegExp(r'[，。！？、；：,.!?;:]+$'), '');
      if (host.isNotEmpty) return 'https://$host';
    }

    return null;
  }

  void start() {
    if (_running) return;
    _running = true;
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (!_running) return;
    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    } catch (_) {
      return; // 剪贴板不可读时静默跳过，不打扰用户
    }
    if (text == null || text.isEmpty) return;
    if (text == _lastText) return;
    _lastText = text;

    final url = extractUrl(text);
    if (url == null || url == _lastNotified) return;
    _lastNotified = url;
    if (!_controller.isClosed) {
      _controller.add(url);
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
