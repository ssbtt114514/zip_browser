import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';

/// 内置使用手册。
class ManualPage extends StatelessWidget {
  const ManualPage({super.key});

  static const authorHome = 'https://ssbtt114514.github.io';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('使用手册'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.person_outline, size: 18),
            label: const Text('作者主页'),
            onPressed: () {
              context.read<TabManager>().createTab(url: authorHome);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Block(
            icon: Icons.travel_explore,
            title: '基础浏览',
            lines: const [
              '顶部地址栏输入网址直接访问，输入关键词则用默认搜索引擎搜索。',
              '地址栏左侧为后退 / 前进，右侧可刷新、收藏当前页。',
              '标签栏可新建、切换、关闭标签；长按或菜单可恢复刚关闭的标签。',
              '菜单中可新建「隐私标签」，隐私标签不写入历史与书签。',
            ],
          ),
          _Block(
            icon: Icons.tune,
            title: '工具箱（二级工具栏）',
            lines: const [
              '点击主工具栏的「调节」图标展开 / 收起工具箱。',
              '资源嗅探：抓取页面中的视频、音频、图片，可下载或复制链接。',
              '阅读模式：去除广告与干扰，只保留正文，可调字号 / 行距 / 背景。',
              '无图模式、色彩滤镜、全屏浏览、字号滑块均可快速切换。',
            ],
          ),
          _Block(
            icon: Icons.satellite_alt,
            title: '资源嗅探与预览',
            lines: const [
              '开启自动嗅探后，发现视频 / 音频会在页面顶部弹出提示，点击查看。',
              '图片显示缩略图，点击可全屏缩放预览；视频 / 音频可直接播放。',
              '每个资源都可一键下载、复制链接或分享。',
              '主菜单「扫一扫」可扫描二维码，识别网址自动打开。',
            ],
          ),
          _Block(
            icon: Icons.palette_outlined,
            title: '外观与主题',
            lines: const [
              '设置 → 外观：深色 / 浅色主题、多套强调色与自定义种子色。',
              '动态取色（Material You）：Android 12+ 跟随壁纸生成主题。',
              '视觉风格：可在 Material 与 Cupertino 两种控件风格间切换。',
            ],
          ),
          _Block(
            icon: Icons.extension,
            title: '插件与内核',
            lines: const [
              '插件管理：安装 zip 功能插件（脚本扩展、界面扩展）。',
              '内核管理：安装 .zbk 独立内核包，并在系统内核 / 插件内核间切换。',
              '桌面版网站：以桌面 UA 与视口加载，便于访问 PC 站点。',
              '插件开发与内核 ABI 见仓库 docs/ 目录。',
            ],
          ),
          _Block(
            icon: Icons.security,
            title: '隐私与安全',
            lines: const [
              '可在「内容与安全」中开关 JavaScript、设置受信任插件白名单。',
              '清除浏览数据：一键清理 Cookie、缓存与历史记录。',
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Zip Browser · 作者 ssbtt114514',
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;
  const _Block(
      {required this.icon, required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 19, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(l,
                          style: const TextStyle(height: 1.45, fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
