import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../services/config_service.dart';
import '../../services/ui_state.dart';
import '../design/zb_design.dart';
import 'main_toolbar.dart'
    show mainMenuEntries, handleMainMenuAction, openQrScan;


/// Firefox 风格底部导航栏（仅窄屏显示）。
///
/// 悬浮圆角 dock：后退 / 前进 / 主页 / 扫一扫 / 菜单。
/// 菜单弹底部面板，条目与主菜单完全一致（复用 [mainMenuEntries]）。
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final tm = context.watch<TabManager>();
    final ui = context.watch<BrowserUiState>();
    final tab = tm.active;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      decoration: BoxDecoration(
        color: zb.chromeElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: zb.hairline, width: 1),
        boxShadow: zb.panelShadow(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ZbIconAction(
            icon: Icons.arrow_back,
            tooltip: '后退',
            size: 20,
            extent: 42,
            onTap: (tab?.canGoBack.value ?? false)
                ? () => tab?.kernel.goBack()
                : null,
          ),
          ZbIconAction(
            icon: Icons.arrow_forward,
            tooltip: '前进',
            size: 20,
            extent: 42,
            onTap: (tab?.canGoForward.value ?? false)
                ? () => tab?.kernel.goForward()
                : null,
          ),
          ZbIconAction(
            icon: Icons.home_outlined,
            tooltip: '主页',
            size: 20,
            extent: 42,
            onTap: () {
              context
                  .read<TabManager>()
                  .navigateActive(context.read<ConfigService>().homePage);
            },
          ),
          ZbIconAction(
            icon: Icons.qr_code_scanner,
            tooltip: '扫一扫',
            size: 20,
            extent: 42,
            onTap: () => openQrScan(context),
          ),
          ZbIconAction(
            icon: ui.secondaryOpen ? Icons.tune : Icons.tune_outlined,
            tooltip: '工具箱',
            size: 20,
            extent: 42,
            selected: ui.secondaryOpen,
            onTap: ui.toggleSecondary,
          ),
          ZbIconAction(
            icon: Icons.more_horiz,
            tooltip: '菜单',
            size: 20,
            extent: 42,
            onTap: () => _openBottomMenu(context),
          ),
        ],
      ),
    );
  }

  /// 底部弹出主菜单（Firefox 移动端风格）
  Future<void> _openBottomMenu(BuildContext context) async {
    final zb = context.zb;
    final tm = context.read<TabManager>();
    final config = context.read<ConfigService>();
    final tab = tm.active;
    final entries = mainMenuEntries(context, tm: tm, config: config, tab: tab);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: zb.chromeElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final zb2 = ctx.zb;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: ZbTokens.s3),
            children: [
              for (final e in entries) ...[
                if (e.dividerBefore)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  dense: true,
                  enabled: e.value != 'zoom_show',
                  leading: Icon(e.icon, size: 20, color: zb2.textMuted),
                  title: Text(e.label,
                      style:
                          TextStyle(fontSize: 14, color: zb2.textPrimary)),
                  trailing: e.hint == null
                      ? null
                      : Text(e.hint!,
                          style:
                              TextStyle(fontSize: 11, color: zb2.textFaint)),
                  onTap: e.value == 'zoom_show'
                      ? null
                      : () => Navigator.pop(ctx, e.value),
                ),
              ],
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    await handleMainMenuAction(context, action);
  }
}
