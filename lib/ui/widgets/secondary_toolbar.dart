import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../core/web/web_enhance_settings.dart';
import '../../services/ui_state.dart';
import '../../services/web_enhance_service.dart';
import 'zb_slider.dart';
import 'zb_tool_button.dart';

/// 二级工具栏：资源嗅探、阅读模式、无图、网页滤镜、全屏、字号调节。
///
/// 由主工具栏的「工具箱」按钮展开/收起（见 [BrowserUiState.secondaryOpen]）。
class SecondaryToolbar extends StatefulWidget {
  const SecondaryToolbar({super.key});

  @override
  State<SecondaryToolbar> createState() => _SecondaryToolbarState();
}

class _SecondaryToolbarState extends State<SecondaryToolbar> {
  bool _readerActive = false;
  bool _fullscreen = false;

  /// 设置改动后立即把增强效果注入当前页
  Future<void> _reapply() async {
    final tab = context.read<TabManager>().active;
    if (tab != null) {
      await context.read<WebEnhanceService>().applyTo(tab.kernel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<BrowserUiState>();
    final enhance = context.watch<WebEnhanceService>();
    final s = enhance.settings;
    final tm = context.watch<TabManager>();
    final hasTab = tm.active != null;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
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
                    tooltip: '资源嗅探',
                    selected: ui.sniffOpen,
                    onTap: hasTab
                        ? () {
                            ui.toggleSniff();
                            if (ui.sniffOpen) tm.active?.kernel.triggerSniff();
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
                            final kernel = tm.active!.kernel;
                            await enhance.toggleReader(kernel);
                            setState(() => _readerActive = !_readerActive);
                          }
                        : null,
                  ),
                  _Gap(),
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
                  // 全屏
                  ZbToolButton(
                    icon: _fullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen_outlined,
                    tooltip: _fullscreen ? '退出全屏' : '全屏',
                    selected: _fullscreen,
                    onTap: () {
                      setState(() => _fullscreen = !_fullscreen);
                      SystemChrome.setEnabledSystemUIMode(
                        _fullscreen
                            ? SystemUiMode.immersiveSticky
                            : SystemUiMode.edgeToEdge,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 22,
            width: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          // 字号调节
          SizedBox(
            width: 150,
            child: Row(
              children: [
                Text('A',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
                Expanded(
                  child: ZbSlider(
                    value: s.fontScale,
                    min: 0.8,
                    max: 2.0,
                    divisions: 24,
                    label: '${(s.fontScale * 100).round()}%',
                    onChanged: hasTab
                        ? (v) => context
                            .read<WebEnhanceService>()
                            .setFontScale(v)
                        : (_) {},
                    onChangeEnd: hasTab ? (_) => _reapply() : null,
                  ),
                ),
                Text('A',
                    style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.75))),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

class _Gap extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 4);
}
