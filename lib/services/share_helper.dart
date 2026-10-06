import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_keys.dart';

/// 分享助手：移动端系统分享；桌面端降级为复制到剪贴板
class ShareHelper {
  static Future<void> share(String text) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(ShareParams(text: text));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messengerKey.currentState?.showSnackBar(
      const SnackBar(
          content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }
}
