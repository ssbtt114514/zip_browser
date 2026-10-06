import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../services/url_suggest_service.dart';
import '../design/zb_design.dart';
import '../omnibox_controller.dart';
import '../shortcuts/browser_focus.dart';

/// 地址栏联想下拉面板。
///
/// 渲染在**内容区顶部的 Stack** 中（而不是工具栏内），这样它才能真正覆盖
/// 网页内容而不被工具栏高度裁切；水平位置与宽度通过 [OmniboxController] 的
/// [LayerLink] 与实测宽度对齐到地址栏正下方。
class OmniboxSuggestions extends StatelessWidget {
  const OmniboxSuggestions({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OmniboxController>();
    if (!controller.showSuggestions) return const SizedBox.shrink();

    final zb = context.zb;
    final items = controller.suggestions;
    final width = controller.width;

    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: controller.layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 7),
        child: SizedBox(
          width: width,
          child: Material(
            color: zb.chromeElevated,
            elevation: 0,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: zb.hairline),
                boxShadow: zb.panelShadow(),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ListView.builder(
                      padding:
                          const EdgeInsets.symmetric(vertical: ZbTokens.s2),
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (_, i) => _SuggestionRow(
                        suggestion: items[i],
                        selected: i == controller.highlight,
                        onHover: () => controller.setHighlight(i),
                        onTap: () {
                          final tm = context.read<TabManager>();
                          controller.close();
                          BrowserFocus.take(context);
                          tm.navigateActive(items[i].url);
                        },
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: zb.hairline)),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: ZbTokens.s5, vertical: ZbTokens.s3),
                    child: Row(
                      children: [
                        Icon(Icons.keyboard, size: 13, color: zb.textFaint),
                        const SizedBox(width: ZbTokens.s3),
                        Expanded(
                          child: Text(
                            '↑ ↓ 选择 · Enter 打开 · Esc 收起 · Tab 补全',
                            style:
                                TextStyle(fontSize: 11, color: zb.textFaint),
                          ),
                        ),
                        Text(
                          '${items.length} 条建议',
                          style: TextStyle(fontSize: 11, color: zb.textFaint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final UrlSuggestion suggestion;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  const _SuggestionRow({
    required this.suggestion,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final primary = Theme.of(context).colorScheme.primary;

    final IconData icon;
    final Color iconColor;
    switch (suggestion.kind) {
      case SuggestionKind.search:
        icon = Icons.search;
        iconColor = zb.textMuted;
      case SuggestionKind.bookmark:
        icon = Icons.star;
        iconColor = const Color(0xFFF5A623);
      case SuggestionKind.open:
        icon = Icons.north_east;
        iconColor = primary;
      case SuggestionKind.history:
        icon = Icons.history;
        iconColor = zb.textMuted;
    }

    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: ZbTokens.s5),
          decoration: BoxDecoration(
            color: selected ? zb.suggestionHighlight : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: iconColor),
              const SizedBox(width: ZbTokens.s5),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: zb.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (suggestion.subtitle.isNotEmpty)
                      Text(
                        suggestion.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: zb.textFaint),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.keyboard_return, size: 15, color: zb.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
