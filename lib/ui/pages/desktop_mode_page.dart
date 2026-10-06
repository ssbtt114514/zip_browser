import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/desktop_mode_config.dart';
import '../../services/desktop_mode_config.dart';

/// 桌面模式设置页（UA / 视口 / DPR 自定义）
class DesktopModePage extends StatefulWidget {
  const DesktopModePage({super.key});

  @override
  State<DesktopModePage> createState() => _DesktopModePageState();
}

class _DesktopModePageState extends State<DesktopModePage> {
  late DesktopModeConfig _cfg;
  late final TextEditingController _ua;
  late final TextEditingController _vw;
  late final TextEditingController _vh;
  late final TextEditingController _dpr;

  @override
  void initState() {
    super.initState();
    _cfg = context.read<DesktopModePreferences>().config;
    _ua = TextEditingController(text: _cfg.userAgent);
    _vw = TextEditingController(
        text: _cfg.viewportWidth > 0 ? '${_cfg.viewportWidth}' : '');
    _vh = TextEditingController(
        text: _cfg.viewportHeight > 0 ? '${_cfg.viewportHeight}' : '');
    _dpr = TextEditingController(
        text: _cfg.devicePixelRatio > 0 ? '${_cfg.devicePixelRatio}' : '');
  }

  @override
  void dispose() {
    _ua.dispose();
    _vw.dispose();
    _vh.dispose();
    _dpr.dispose();
    super.dispose();
  }

  void _save() {
    final cfg = DesktopModeConfig(
      enabled: _cfg.enabled,
      userAgent: _ua.text.trim(),
      viewportWidth: int.tryParse(_vw.text.trim()) ?? 0,
      viewportHeight: int.tryParse(_vh.text.trim()) ?? 0,
      devicePixelRatio: double.tryParse(_dpr.text.trim()) ?? 0,
    );
    context.read<DesktopModePreferences>().update(cfg);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('桌面模式已保存，新标签页生效'),
          duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面模式'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('启用桌面模式', style: TextStyle(fontSize: 14)),
              subtitle: const Text('以桌面 UA 和视口渲染网页，强制桌面版布局',
                  style: TextStyle(fontSize: 11.5)),
              value: _cfg.enabled,
              onChanged: (v) {
                setState(() => _cfg = _cfg.copyWith(enabled: v));
                context
                    .read<DesktopModePreferences>()
                    .update(_cfg.copyWith(enabled: v));
              },
            ),
          ),
          const SizedBox(height: 16),

          // —— 预设 ——
          const _Label('快速预设'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Windows 桌面 (Edge)'),
                onPressed: () => _applyPreset(
                  ua: DesktopModeConfig.defaultDesktopUA,
                  vw: 1280,
                  vh: 720,
                  dpr: 1.0,
                ),
              ),
              ActionChip(
                label: const Text('macOS Safari'),
                onPressed: () => _applyPreset(
                  ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                      'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                      'Version/17.0 Safari/605.1.15',
                  vw: 1440,
                  vh: 900,
                  dpr: 2.0,
                ),
              ),
              ActionChip(
                label: const Text('iPad'),
                onPressed: () => _applyPreset(
                  ua: 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) '
                      'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                      'Version/17.0 Mobile/15E148 Safari/604.1',
                  vw: 1024,
                  vh: 1366,
                  dpr: 2.0,
                ),
              ),
              ActionChip(
                label: const Text('恢复默认'),
                onPressed: () => _applyPreset(ua: '', vw: 0, vh: 0, dpr: 0),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // —— User-Agent ——
          const _Label('User-Agent'),
          TextField(
            controller: _ua,
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(fontSize: 12.5),
            decoration: const InputDecoration(
              hintText: '留空使用默认桌面 UA：\n${DesktopModeConfig.defaultDesktopUA}',
              hintStyle: TextStyle(fontSize: 11),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),

          // —— 视口 ——
          const _Label('视口尺寸 (CSS 像素)'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vw,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '宽度',
                    hintText: '如 1280',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _vh,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '高度',
                    hintText: '如 720',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // —— DPR ——
          const _Label('设备像素比 (DPR)'),
          TextField(
            controller: _dpr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '如 1.0 / 2.0，留空使用内核默认',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.amber.shade50,
            margin: EdgeInsets.zero,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '视口与 DPR 通过页面脚本注入实现，部分依赖原生 UA 的特性可能受限。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applyPreset({
    required String ua,
    required int vw,
    required int vh,
    required double dpr,
  }) {
    setState(() {
      _ua.text = ua;
      _vw.text = vw > 0 ? '$vw' : '';
      _vh.text = vh > 0 ? '$vh' : '';
      _dpr.text = dpr > 0 ? '$dpr' : '';
    });
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

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
