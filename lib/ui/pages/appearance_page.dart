import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/appearance_settings.dart';
import '../../core/theme/style_mode.dart';
import '../../services/config_service.dart';

/// 外观自定义页：主题模式、主色、强调色、字体、密度、圆角、起始页背景、纯黑模式
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppearanceSettings>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // —— 视觉风格（Material / Cupertino）——
          const _SectionTitle('视觉风格'),
          Builder(
            builder: (bctx) {
              final config = bctx.watch<ConfigService>();
              return Card(
                child: Column(
                  children: [
                    for (final mode in AppStyleMode.values)
                      RadioListTile<AppStyleMode>(
                        value: mode,
                        groupValue: config.styleMode,
                        title: Text(mode.label),
                        subtitle: Text(mode.description,
                            style: const TextStyle(fontSize: 11.5)),
                        secondary: Icon(mode == AppStyleMode.cupertino
                            ? Icons.phone_iphone
                            : Icons.android),
                        onChanged: (v) =>
                            v == null ? null : config.setStyleMode(v),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // —— 主题模式 ——
          const _SectionTitle('主题模式'),
          Card(
            child: Column(
              children: [
                for (final mode in ThemeModeOption.values)
                  RadioListTile<ThemeModeOption>(
                    value: mode,
                    groupValue: s.themeMode,
                    title: Text(_modeLabel(mode)),
                    secondary: Icon(_modeIcon(mode)),
                    onChanged: (v) => v == null ? null : s.setThemeMode(v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // —— 动态取色（莫奈 / Material You）——
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.auto_awesome),
              title: const Text('动态取色（Material You）'),
              subtitle: const Text('Android 12+ 跟随壁纸生成主题色，其他系统自动回退到主色调'),
              value: s.monetEnabled,
              onChanged: s.setMonetEnabled,
            ),
          ),
          const SizedBox(height: 16),

          // —— 主色调 ——
          const _SectionTitle('主色调'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in AppearanceSettings.palette)
                    _ColorDot(
                      color: c,
                      selected: s.seedColor.value == c.value,
                      onTap: () => s.setSeedColor(c),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // —— 强调色 ——
          const _SectionTitle('强调色（按钮 / 链接高亮）'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ColorDot(
                    color: s.seedColor,
                    selected: s.accentColor == null,
                    label: '跟随主色',
                    onTap: () => s.setAccentColor(null),
                  ),
                  for (final c in AppearanceSettings.accentPalette)
                    _ColorDot(
                      color: c,
                      selected: s.accentColor?.value == c.value,
                      onTap: () => s.setAccentColor(c),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // —— 字体缩放 ——
          const _SectionTitle('字体大小'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('缩放比例'),
                      Text('${(s.fontScale * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary)),
                    ],
                  ),
                  Slider(
                    value: s.fontScale,
                    min: 0.8,
                    max: 1.4,
                    divisions: 12,
                    label: '${(s.fontScale * 100).toStringAsFixed(0)}%',
                    onChanged: s.setFontScale,
                  ),
                  const Text('预览文本 ABC 中文 123',
                      style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // —— 控件密度 ——
          const _SectionTitle('控件密度'),
          Card(
            child: Column(
              children: [
                for (final d in DensityOption.values)
                  RadioListTile<DensityOption>(
                    value: d,
                    groupValue: s.density,
                    title: Text(_densityLabel(d)),
                    onChanged: (v) => v == null ? null : s.setDensity(v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // —— 圆角 ——
          const _SectionTitle('圆角'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                children: [
                  for (final r in RadiusLevel.values)
                    ChoiceChip(
                      label: Text(_radiusLabel(r)),
                      selected: s.radiusLevel == r,
                      onSelected: (_) => s.setRadiusLevel(r),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // —— 深色模式选项 ——
          if (isDark || s.themeMode == ThemeModeOption.dark) ...[
            const _SectionTitle('深色模式'),
            Card(
              child: SwitchListTile(
                title: const Text('纯黑背景（OLED 友好）'),
                subtitle: const Text('使用纯黑色 #000000 作为背景'),
                value: s.trueBlack,
                onChanged: s.setTrueBlack,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // —— 起始页背景 ——
          const _SectionTitle('起始页背景'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('背景颜色'),
                  trailing: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: s.homeBgColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                  onTap: () => _pickColor(context, s),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('背景图片'),
                  subtitle: Text(s.homeBgImage == null
                      ? '未设置'
                      : s.homeBgImage!),
                  trailing: s.homeBgImage == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => s.setHomeBgImage(null),
                        ),
                  onTap: () async {
                    // 由插件/文件选择器扩展；此处仅清除示例
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Zip Browser · 外观自定义',
                style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickColor(BuildContext context, AppearanceSettings s) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择背景色'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in [
              const Color(0xFFEEF4FB),
              const Color(0xFFF0E6FF),
              const Color(0xFFFFF3E0),
              const Color(0xFFE8F5E9),
              const Color(0xFFFFEBEE),
              const Color(0xFFE0F7FA),
              const Color(0xFFFFFFFF),
              const Color(0xFF1A1D22),
            ])
              GestureDetector(
                onTap: () => Navigator.pop(ctx, c),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black26),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (color != null) s.setHomeBgColor(color);
  }

  String _modeLabel(ThemeModeOption m) {
    switch (m) {
      case ThemeModeOption.system:
        return '跟随系统';
      case ThemeModeOption.light:
        return '浅色';
      case ThemeModeOption.dark:
        return '深色';
    }
  }

  IconData _modeIcon(ThemeModeOption m) {
    switch (m) {
      case ThemeModeOption.system:
        return Icons.brightness_auto;
      case ThemeModeOption.light:
        return Icons.light_mode;
      case ThemeModeOption.dark:
        return Icons.dark_mode;
    }
  }

  String _densityLabel(DensityOption d) {
    switch (d) {
      case DensityOption.comfortable:
        return '舒适';
      case DensityOption.compact:
        return '紧凑';
    }
  }

  String _radiusLabel(RadiusLevel r) {
    switch (r) {
      case RadiusLevel.none:
        return '无';
      case RadiusLevel.small:
        return '小';
      case RadiusLevel.medium:
        return '中';
      case RadiusLevel.large:
        return '大';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final String? label;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black26,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(label!, style: const TextStyle(fontSize: 10.5)),
            ),
        ],
      ),
    );
  }
}
