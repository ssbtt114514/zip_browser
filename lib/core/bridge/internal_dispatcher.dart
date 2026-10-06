import 'dart:async';
import 'dart:convert';

import '../kernel/browser_kernel.dart';
import '../sniff/sniff_model.dart';

/// 宿主内置消息分发（区别于插件 bridge）：
/// 当前承载长按 / 右键菜单、下载、用户脚本识别、资源嗅探，可扩展宿主内部事件。
class InternalDispatcher {
  final StreamController<ContextMenuInfo> contextMenuCtrl =
      StreamController<ContextMenuInfo>.broadcast();
  final StreamController<String> downloadCtrl =
      StreamController<String>.broadcast();

  /// 检测到可安装的用户脚本链接（单个，点击时）
  final StreamController<String> userscriptDetectedCtrl =
      StreamController<String>.broadcast();

  /// 页面扫描到的用户脚本链接列表
  final StreamController<List<String>> userscriptListCtrl =
      StreamController<List<String>>.broadcast();

  /// 嗅探到的页面资源
  final StreamController<List<SniffedResource>> sniffCtrl =
      StreamController<List<SniffedResource>>.broadcast();

  Stream<ContextMenuInfo> get contextMenu => contextMenuCtrl.stream;
  Stream<String> get downloads => downloadCtrl.stream;
  Stream<String> get userscriptDetected => userscriptDetectedCtrl.stream;
  Stream<List<String>> get userscriptList => userscriptListCtrl.stream;
  Stream<List<SniffedResource>> get sniffedResources => sniffCtrl.stream;

  /// 返回 true：internal 消息已处理；false：是普通插件消息
  bool dispatch(String raw) {
    Map<dynamic, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      msg = decoded;
    } catch (_) {
      return false;
    }

    if (msg['scope'] != 'internal') return false;

    final payload = msg['payload'];
    if (payload is String && payload.startsWith('contextMenu:')) {
      try {
        final info = jsonDecode(payload.substring(12)) as Map;
        contextMenuCtrl.add(ContextMenuInfo(
          pageUrl: info['pageUrl'] as String? ?? '',
          linkUrl: info['linkUrl'] as String?,
          imageUrl: info['imageUrl'] as String?,
          selectedText: info['selectedText'] as String?,
        ));
      } catch (_) {}
    } else if (payload is String && payload.startsWith('download:')) {
      final url = payload.substring(9).trim();
      if (url.isNotEmpty) downloadCtrl.add(url);
    } else if (payload is String && payload.startsWith('userscript:')) {
      final url = payload.substring(11).trim();
      if (url.isNotEmpty) userscriptDetectedCtrl.add(url);
    } else if (payload is String && payload.startsWith('userscriptList:')) {
      try {
        final list = jsonDecode(payload.substring(15)) as List;
        final urls = list.whereType<String>().toList();
        if (urls.isNotEmpty) userscriptListCtrl.add(urls);
      } catch (_) {}
    } else if (payload is String && payload.startsWith('sniff:')) {
      try {
        final list = jsonDecode(payload.substring(6)) as List;
        final resources = list
            .whereType<Map>()
            .map((e) => SniffedResource.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (resources.isNotEmpty) sniffCtrl.add(resources);
      } catch (_) {}
    }
    return true;
  }

  Future<void> close() async {
    await contextMenuCtrl.close();
    await downloadCtrl.close();
    await userscriptDetectedCtrl.close();
    await userscriptListCtrl.close();
    await sniffCtrl.close();
  }
}
