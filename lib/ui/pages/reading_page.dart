import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../core/web/web_enhance_settings.dart';
import '../../services/web_enhance_service.dart';

/// 阅读与显示增强页：阅读模式、滤镜、字号行距、无图模式。
///
/// 所有设置持久化到 [WebEnhanceService]，并在每次页面加载完成时
/// 通过内核注入 CSS / JS 自动生效。
class ReadingPage extends StatelessWidget {
  const ReadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<WebEnhanceService>();
    final s = service.settings;
    final tm = context.read<TabManager>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读与显示'),
        actions: [
          IconButton(
            tooltip: '应用到当前页面',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final kernel = tm.active?.kernel;
              if (kernel == null) return;
              await service.applyTo(kernel);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('已应用到当前页面'),
                  duration: Duration(seconds: 1),
                ));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // —— 阅读模式 ——
          const _SectionTitle('阅读模式'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('打开页面自动进入阅读模式',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('按正文权重提取内容，去除广告与侧栏',
                      style: TextStyle(fontSize: 11.5)),
                  value: s.autoReader,
                  onChanged: service.setAutoReader,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.chrome_reader_mode_outlined, size: 20),
                  title: const Text('切换当前页阅读模式',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('对当前标签页立即生效',
                      style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () async {
                    final kernel = tm.active?.kernel;
                    if (kernel == null) return;
                    await service.toggleReader(kernel);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // —— 网页滤镜 ——
          const _SectionTitle('网页滤镜'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in WebFilterMode.values)
                    ChoiceChip(
                      label: Text(mode.label),
                      selected: s.filter == mode,
                      onSelected: (_) => service.setFilter(mode),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // —— 正文排版 ——
          const _SectionTitle('正文排版'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SliderRow(
                    label: '字号倍率',
                    value: '${(s.fontScale * 100).toStringAsFixed(0)}%',
                    slider: Slider(
                      value: s.fontScale,
                      min: 0.8,
                      max: 2.0,
                      divisions: 24,
                      label: '${(s.fontScale * 100).toStringAsFixed(0)}%',
                      onChanged: service.setFontScale,
                    ),
                  ),
                  _SliderRow(
                    label: '正文行距',
                    value: s.lineHeight.toStringAsFixed(1),
                    slider: Slider(
                      value: s.lineHeight,
                      min: 1.2,
                      max: 2.4,
                      divisions: 12,
                      label: s.lineHeight.toStringAsFixed(1),
                      onChanged: service.setLineHeight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '调整会作用于所有页面正文（含阅读模式）。预览：春江潮水连海平，海上明月共潮生。',
                    style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // —— 省流 ——
          const _SectionTitle('省流'),
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('无图模式', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text('隐藏网页图片，仅保留文字，节省流量',
                  style: TextStyle(fontSize: 11.5)),
              value: s.noImage,
              onChanged: service.setNoImage,
            ),
          ),
          const SizedBox(height: 18),

          // —— 复位 ——
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('恢复默认'),
              onPressed: () =>
                  service.update(const WebEnhanceSettings()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget slider;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        slider,
      ],
    );
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
