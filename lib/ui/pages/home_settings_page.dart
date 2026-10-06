import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/config_service.dart';

/// 新标签页设置：主页地址、快捷方式数量、最近访问开关。
class HomeSettingsPage extends StatefulWidget {
  const HomeSettingsPage({super.key});

  @override
  State<HomeSettingsPage> createState() => _HomeSettingsPageState();
}

class _HomeSettingsPageState extends State<HomeSettingsPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: context.read<ConfigService>().homePage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveHomePage() async {
    final value = _controller.text.trim();
    final config = context.read<ConfigService>();
    final messenger = ScaffoldMessenger.of(context);
    await config.setHomePage(value.isEmpty ? 'about:home' : value);
    messenger.showSnackBar(const SnackBar(
      content: Text('主页已保存（新建标签页生效）'),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigService>();

    return Scaffold(
      appBar: AppBar(title: const Text('新标签页')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // —— 主页地址 ——
          const _SectionTitle('主页地址'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'about:home 或 https://example.com',
                      labelText: '启动 / 新建标签页加载的地址',
                    ),
                    onSubmitted: (_) => _saveHomePage(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('恢复内置新标签页'),
                        onPressed: () {
                          _controller.text = 'about:home';
                          _saveHomePage();
                        },
                      ),
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: _saveHomePage,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // —— 常用站点 ——
          const _SectionTitle('常用站点'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('快捷方式数量'),
                      Text('${config.homeShortcutCount} 个',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Slider(
                    value: config.homeShortcutCount.toDouble(),
                    min: 4,
                    max: 16,
                    divisions: 12,
                    label: '${config.homeShortcutCount}',
                    onChanged: (v) =>
                        config.setHomeShortcutCount(v.round()),
                  ),
                  const Text('书签优先，不足时按访问次数补齐',
                      style: TextStyle(fontSize: 12, color: Colors.black45)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // —— 最近访问 ——
          const _SectionTitle('内容区块'),
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('展示「最近访问」',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: const Text('在新标签页底部列出最近打开过的页面',
                  style: TextStyle(fontSize: 11.5)),
              value: config.homeShowRecent,
              onChanged: config.setHomeShowRecent,
            ),
          ),
          const SizedBox(height: 14),
          const Text('提示：新标签页内容在标签页创建时生成，修改后新建标签页即可看到效果。',
              style: TextStyle(fontSize: 12, color: Colors.black38)),
        ],
      ),
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
