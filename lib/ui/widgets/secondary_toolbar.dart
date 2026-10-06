import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../core/web/web_enhance_settings.dart';
import '../../services/config_service.dart';
import '../../services/ui_state.dart';
import '../../services/web_enhance_service.dart';
import '../../services/zoom_service.dart';
import '../design/zb_design.dart';
import 'zb_tool_button.dart';

/// 二级工具栏（工具箱）：资源嗅探、阅读模式、无图、网页滤镜、缩放、全屏。
///
/// 由主工具栏的「工具箱」按钮展开/收起（见 [BrowserUiState.secondaryOpen]）。
class SecondaryToolbar extends StatefulWidget {
  const SecondaryToolbar({super.key});

  @override
  State<SecondaryToolbar> createState() => _SecondaryToolbarState();
}

class _SecondaryToolbarState extends State<SecondaryToolbar> {
  bool _readerActive = false;

  /// 设置改动后立即把增强效果注入当前页
  Future<void> _reapply() async {
    final tab = context.read<TabManager>().active;
    if (tab != null) {
      await context.read<WebEnhanceService>().applyTo(tab.kernel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final ui = context.watch<BrowserUiState>();
    final enhance = context.watch<WebEnhanceService>();
    final config = context.watch<ConfigService>();
    final zoomSvc = context.watch<ZoomService>();
    final s = enhance.settings;
    final tm = context.watch<TabManager>();
    final tab = tm.active;
    final hasTab = tab != null;
    final zoom = tab == null ? 1.0 : tm.zoomFor(tab);

    return Container(
      height: ZbTokens.secondaryBarHeight,
      decoration: BoxDecoration(
        color: zb.chromeElevated,
        border: Border(bottom: BorderSide(color: zb.hairline, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: ZbTokens.s6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 资源嗅探
                  ZbToolButton(
                    icon: ui.sniffOpen
                        ? Icons.satellite_alt
                        : Icons.satellite_alt_outlined,
                    tooltip: '资源嗅探（媒体/图片/脚本）',
                    selected: ui.sniffOpen,
                    onTap: hasTab
                        ? () {
                            ui.toggleSniff();
                            if (ui.sniffOpen) tab.kernel.triggerSniff();
                          }
                        : null,
                  ),
                  // 阅读模式
                  ZbToolButton(
                    icon: Icons.chrome_reader_mode_outlined,
                    tooltip: _readerActive ? '退出阅读模式' : '阅读模式',
                    selected: _readerActive,
                    onTap: hasTab
                        ? () async {
                            await enhance.toggleReader(tab.kernel);
                            if (mounted) {
                              setState(() => _readerActive = !_readerActive);
                            }
                          }
                        : null,
                  ),
                  _divider(zb),
                  // 无图模式
                  ZbToolButton(
                    icon: s.noImage
                        ? Icons.image_not_supported
                        : Icons.image_outlined,
                    tooltip: s.noImage ? '关闭无图模式' : '无图模式（省流）',
                    selected: s.noImage,
                    onTap: hasTab
                        ? () async {
                            await enhance.setNoImage(!s.noImage);
                            await _reapply();
                          }
                        : null,
                  ),
                  // 网页滤镜（循环切换）
                  ZbToolButton(
                    icon: _filterIcon(s.filter),
                    tooltip: '网页滤镜：${s.filter.label}（点击切换）',
                    selected: s.filter != WebFilterMode.none,
                    onTap: hasTab
                        ? () async {
                            const order = [
                              WebFilterMode.none,
                              WebFilterMode.sepia,
                              WebFilterMode.night,
                              WebFilterMode.gray,
                            ];
                            final next = order[
                                (order.indexOf(s.filter) + 1) % order.length];
                            await enhance.setFilter(next);
                            await _reapply();
                          }
                        : null,
                  ),
                  _divider(zb),
                  // 缩放
                  ZbToolButton(
                    icon: Icons.remove,
                    tooltip: '缩小（Ctrl+-）',
                    onTap: hasTab ? () => tm.zoomOut() : null,
                  ),
                  Tooltip(
                    message: '当前缩放 ${ZoomService.label(zoom)}（点击重置为 100%）',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: hasTab ? () => tm.resetZoom() : null,
                      child: Container(
                        height: 30,
                        constraints: const BoxConstraints(minWidth: 50),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: ZbTokens.s4),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          ZoomService.label(zoom),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ZbToolButton(
                    icon: Icons.add,
                    tooltip: '放大（Ctrl++）',
                    onTap: hasTab ? () => tm.zoomIn() : null,
                  ),
                  _divider(zb),
                  // 按站点记忆缩放
                  ZbToolButton(
                    icon: zoomSvc.perSiteEnabled
                        ? Icons.bookmark_added_outlined
                        : Icons.bookmark_remove_outlined,
                    tooltip: zoomSvc.perSiteEnabled
                        ? '按站点记忆缩放：已开启'
                        : '按站点记忆缩放：已关闭',
                    selected: zoomSvc.perSiteEnabled,
                    onTap: () => zoomSvc
                        .setPerSiteEnabled(!zoomSvc.perSiteEnabled),
                  ),
                  _divider(zb),
                  // 全屏
                  ZbToolButton(
                    icon: ui.fullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen_outlined,
                    tooltip: ui.fullscreen ? '退出全屏（F11）' : '全屏（F11）',
                    selected: ui.fullscreen,
                    onTap: () => ui.toggleFullscreen(),
                  ),
                  // 桌面版网站
                  ZbToolButton(
                    icon: Icons.desktop_windows_outlined,
                    tooltip: tab?.desktopMode.value ?? false
                        ? '切换到移动版网站'
                        : '请求桌面版网站',
                    selected: tab?.desktopMode.value ?? false,
                    onTap: tab == null ? null : () => tm.toggleDesktopMode(tab),
                  ),
                  // JavaScript
                  ZbToolButton(
                    icon: config.jsEnabled
                        ? Icons.javascript
                        : Icons.javascript_outlined,
                    tooltip: config.jsEnabled ? 'JavaScript：已启用' : 'JavaScript：已禁用',
                    selected: config.jsEnabled,
                    onTap: () async {
                      await config.setJsEnabled(!config.jsEnabled);
                      if (hasTab) await tab.kernel.reload();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ZbColors zb) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: ZbTokens.s4),
        color: zb.hairline,
      );

  IconData _filterIcon(WebFilterMode mode) {
    switch (mode) {
      case WebFilterMode.none:
        return Icons.color_lens_outlined;
      case WebFilterMode.night:
        return Icons.dark_mode_outlined;
      case WebFilterMode.sepia:
        return Icons.remove_red_eye_outlined;
      case WebFilterMode.gray:
        return Icons.palette_outlined;
    }
  }
}
