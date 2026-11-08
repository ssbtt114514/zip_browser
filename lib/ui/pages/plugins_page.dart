import 'package:flutter/material.dart';

/// 插件管理页（已随 v0.12.0 移除 zip 功能插件接口）。
///
/// 历史说明：v0.11 及之前支持安装 zip 功能插件（JS 扩展 / UI 扩展），
/// v0.12.0 起该接口整体下线，仅保留独立内核包（.zbk）的安装与切换
/// （见 KernelsPage）。此文件仅作占位说明，可安全删除。
class PluginsPage extends StatelessWidget {
  const PluginsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('插件管理')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'zip 功能插件接口已在本版本移除。\n\n'
            '独立浏览器内核请使用「内核管理」安装 .zbk 内核包。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.6),
          ),
        ),
      ),
    );
  }
}
