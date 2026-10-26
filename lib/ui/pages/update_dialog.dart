import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_keys.dart';
import '../../core/constants.dart';
import '../../core/tab/tab_manager.dart';
import '../../services/update_service.dart';

/// 「检查更新」共享流程：查询 → 无更新提示 / 有更新弹窗（跳转下载）。
class UpdateCheckHelper {
  UpdateCheckHelper._();

  /// 执行检查；发现新版本时弹出对话框。
  /// 返回 [UpdateInfo]（有更新）或 null（已是最新）。
  /// 网络错误抛出异常由调用方提示。
  static Future<UpdateInfo?> checkWithUi() async {
    final info = await UpdateService.check();
    if (info == null) return null;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return info;
    final ctx = navigator.context;
    if (!ctx.mounted) return info;
    await showDialog<void>(
      context: ctx,
      builder: (dctx) {
        return AlertDialog(
          icon: const Icon(Icons.system_update_alt),
          title: Text('发现新版本 ${info.version}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前版本：${BrowserConstants.appVersion}'),
                const SizedBox(height: 8),
                const Text('更新说明：',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
                const SizedBox(height: 4),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      info.notes.isEmpty ? '（无说明）' : info.notes,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('以后再说'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new, size: 17),
              label: const Text('打开下载页'),
              onPressed: () {
                Navigator.pop(dctx);
                ctx.read<TabManager>().createTab(url: info.htmlUrl);
              },
            ),
          ],
        );
      },
    );
    return info;
  }
}
