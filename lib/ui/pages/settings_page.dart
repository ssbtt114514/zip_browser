import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/kernel/kernel_registry.dart';
import '../../core/kernel/kernel_types.dart';
import '../../platform/windows_system_kernel.dart';
import '../../services/config_service.dart';
import 'appearance_page.dart';
import 'desktop_mode_page.dart';
import 'home_settings_page.dart';
import 'kernels_page.dart';
import 'reading_page.dart';
import 'search_engines_page.dart';
import '../widgets/adaptive.dart';

/// 设置主页：分类卡片入口 + 当前内核概要 + 内容安全
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigService>();
    final registry = context.read<KernelRegistry>();
    final current = registry.effectiveDescriptor();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // —— 通用分类入口 ——
          const _SectionTitle('通用'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _NavTile(
                  icon: Icons.palette_outlined,
                  title: '外观',
                  subtitle: '主题、颜色、字体、起始页背景',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppearancePage()),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _NavTile(
                  icon: Icons.search,
                  title: '搜索引擎',
                  subtitle: '默认搜索引擎与自定义',
                  trailing: _currentSearchEngineName(config),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SearchEnginesPage()),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _NavTile(
                  icon: Icons.home_outlined,
                  title: '新标签页',
                  subtitle: '快捷方式数量、最近访问、主页地址',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const HomeSettingsPage()),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _NavTile(
                  icon: Icons.chrome_reader_mode_outlined,
                  title: '阅读与显示',
                  subtitle: '阅读模式、夜间/护眼过滤、字号行距、无图',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReadingPage()),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _NavTile(
                  icon: Icons.desktop_windows_outlined,
                  title: '桌面模式',
                  subtitle: '自定义 UA、视口、设备像素比',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const DesktopModePage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // —— 浏览器内核 ——
          const _SectionTitle('浏览器内核'),
          if (WindowsSystemKernel.environmentWarning != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      WindowsSystemKernel.environmentWarning!,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(_kernelIcon(current), size: 20),
                  title: Text(current.displayName,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${current.engine.label}'
                    '${current.version == null ? '' : ' · v${current.version}'}'
                    ' · ${_originLabel(current.origin)}'
                    '${current.available ? '' : ' · 当前不可用'}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: current.available
                      ? null
                      : const Icon(Icons.error_outline,
                          size: 18, color: Colors.orange),
                  isThreeLine: false,
                ),
                // 引擎适配包：如实提示当前内核不渲染网页
                if (current.packageType == 'engine_adapter')
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber,
                            size: 18, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前内核是「引擎适配包」：它只探测本机 Gecko 运行时，'
                            '不提供网页渲染。要浏览网页请切换到系统内核或其它内核包。',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: Colors.brown.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1, indent: 56),
                _NavTile(
                  icon: Icons.memory_outlined,
                  title: '内核管理',
                  subtitle: '安装 / 切换 / 卸载独立内核包',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const KernelsPage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // —— 内容与安全 ——
          const _SectionTitle('内容与安全'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: const Text('启用 JavaScript',
                      style: TextStyle(fontSize: 13.5)),
                  trailing: AdaptiveSwitch(
                    value: config.jsEnabled,
                    onChanged: config.setJsEnabled,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('广告拦截',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('屏蔽常见广告/跟踪请求与页面广告位',
                      style: TextStyle(fontSize: 11.5)),
                  trailing: AdaptiveSwitch(
                    value: config.adBlockEnabled,
                    onChanged: config.setAdBlockEnabled,
                  ),
                ),
                if (config.adBlockEnabled) ...[
                  const Divider(height: 1),
                  _NavTile(
                    icon: Icons.edit_outlined,
                    title: '自定义拦截域名',
                    subtitle: config.adBlockCustomDomains.isEmpty
                        ? '内置规则已启用，可追加自定义域名'
                        : '已添加 ${config.adBlockCustomDomains.length} 个域名',
                    onTap: () => _editDomains(
                      context,
                      title: '自定义拦截域名',
                      hint: '每行一个域名，例如：ads.example.com',
                      initial: config.adBlockCustomDomains,
                      save: config.setAdBlockCustomDomains,
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  _NavTile(
                    icon: Icons.verified_user_outlined,
                    title: '白名单域名',
                    subtitle: config.adBlockAllowDomains.isEmpty
                        ? '误拦截时可在此放行（优先于拦截规则）'
                        : '已放行 ${config.adBlockAllowDomains.length} 个域名',
                    onTap: () => _editDomains(
                      context,
                      title: '白名单域名',
                      hint: '每行一个域名，例如：example.com',
                      initial: config.adBlockAllowDomains,
                      save: config.setAdBlockAllowDomains,
                    ),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  title: const Text('仅允许受信任白名单插件',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('开启后未在白名单中的 zip 将被拒绝安装',
                      style: TextStyle(fontSize: 11.5)),
                  trailing: AdaptiveSwitch(
                    value: config.enforceTrustedOnly,
                    onChanged: config.setEnforceTrustedOnly,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Zip Browser ${BrowserConstants.appVersion} · 独立内核包 · 多平台浏览器框架',
              style: TextStyle(fontSize: 11.5, color: Colors.black38),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _kernelIcon(KernelDescriptor d) {
    switch (d.engine) {
      case KernelEngine.chromium:
        return Icons.travel_explore;
      case KernelEngine.gecko:
        return Icons.local_fire_department_outlined;
      case KernelEngine.system:
        return Icons.android;
      case KernelEngine.custom:
        return Icons.memory;
    }
  }

  static String _originLabel(KernelOrigin origin) {
    switch (origin) {
      case KernelOrigin.system:
        return '系统内核';
      case KernelOrigin.standalone:
        return '独立安装包';
      case KernelOrigin.plugin:
        return '插件携带';
    }
  }

  String _currentSearchEngineName(ConfigService config) {
    final url = config.searchEngine;
    if (url.contains('bing.com')) return 'Bing';
    if (url.contains('google.com')) return 'Google';
    if (url.contains('duckduckgo')) return 'DuckDuckGo';
    if (url.contains('baidu.com')) return '百度';
    if (url.contains('you.com')) return 'You';
    return '自定义';
  }

  /// 编辑域名列表（逗号/换行/空格分隔）
  Future<void> _editDomains(
    BuildContext context, {
    required String title,
    required String hint,
    required List<String> initial,
    required Future<void> Function(List<String>) save,
  }) async {
    final controller = TextEditingController(text: initial.join('\n'));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hint, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 6,
              minLines: 3,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '每行一个域名',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final domains = result
        .split(RegExp(r'[\n,，;；\s]+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
    await save(domains);
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

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 11.5)),
      trailing: trailing == null
          ? const Icon(Icons.chevron_right, size: 18)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(trailing!,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black45)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
      onTap: onTap,
    );
  }
}
