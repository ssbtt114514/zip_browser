import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_keys.dart';
import '../../core/build_flavor.dart';
import '../../core/constants.dart';
import '../../core/kernel/kernel_registry.dart';
import '../../services/config_service.dart';
import '../../services/crash_log.dart';
import '../../services/data_export_service.dart';
import '../../services/downloads_service.dart';
import '../../services/bookmarks_service.dart';
import '../../services/history_service.dart';
import '../../services/paths.dart';
import '../design/zb_design.dart';
import 'update_dialog.dart';

/// 开发者工具箱：构建信息、内核诊断、数据目录、崩溃日志与数据导出入口。
class DevToolsPage extends StatelessWidget {
  const DevToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final config = context.watch<ConfigService>();
    final registry = context.watch<KernelRegistry>();

    return Scaffold(
      appBar: AppBar(title: const Text('开发者工具箱')),
      body: ListView(
        padding: const EdgeInsets.all(ZbTokens.s5),
        children: [
          _Card(
            title: '构建信息',
            children: [
              _row('版本', BrowserConstants.appVersion),
              _row('构建风味', '${BuildFlavorInfo.label} (${BuildFlavorInfo.current.name})'),
              _row('平台',
                  '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'),
              _row('Dart 版本', Platform.version.split(' ').first),
              _row('插件系统', BuildFlavorInfo.pluginSystemEnabled ? '启用' : '已移除'),
              _row('内核管理', BuildFlavorInfo.kernelManagementEnabled ? '启用' : '已移除'),
            ],
          ),
          _Card(
            title: '内核',
            children: [
              for (final d in registry.describe())
                _row(d.displayName, d.available ? '可用' : '不可用'),
            ],
          ),
          _Card(
            title: '数据目录',
            children: [
              _rowCopyable(context, '数据根目录', AppPaths.supportDir.path),
              _rowCopyable(context, '配置文件', AppPaths.profilesDir.path),
              _row('设置项数量', '${config.prefs.getKeys().length}'),
            ],
          ),
          _Card(
            title: '工具',
            children: [
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: const Text('检查更新'),
                subtitle: const Text('查询 GitHub 最新版本'),
                onTap: () => _checkUpdate(context),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('导出用户数据'),
                subtitle: const Text('设置 / 书签 / 历史 / 下载 → JSON 备份'),
                onTap: () => _exportData(context),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('导入用户数据'),
                subtitle: const Text('从 JSON 备份恢复（重启生效）'),
                onTap: () => _importData(context),
              ),
              ListTile(
                leading: const Icon(Icons.copy_all),
                title: const Text('复制诊断信息'),
                subtitle: const Text('版本 / 平台 / 内核 / 数据目录'),
                onTap: () => _copyDiagnostics(context, config, registry),
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('清空崩溃日志'),
                onTap: () {
                  CrashLog.clear();
                  messengerKey.currentState?.showSnackBar(
                    const SnackBar(content: Text('已清空'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
          _Card(
            title: '崩溃 / 运行日志（crash.log 尾部）',
            children: [
              Padding(
                padding: const EdgeInsets.all(ZbTokens.s4),
                child: SelectableText(
                  CrashLog.tail(),
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      fontFamily: 'monospace',
                      color: zb.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZbTokens.s6),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: ZbTokens.s5, vertical: ZbTokens.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 96,
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600))),
            Expanded(
              child: SelectableText(v,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _rowCopyable(BuildContext context, String k, String v) => Stack(
        children: [
          _row(k, v),
          Positioned(
            right: 0,
            top: 0,
            child: SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 15,
                tooltip: '复制',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: v));
                  if (context.mounted) {
                    messengerKey.currentState?.showSnackBar(
                      const SnackBar(
                          content: Text('已复制'),
                          duration: Duration(seconds: 1)),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      );

  Future<void> _checkUpdate(BuildContext context) async {
    final messenger = messengerKey;
    messenger.currentState?.showSnackBar(
      const SnackBar(content: Text('正在检查更新…'), duration: Duration(seconds: 2)),
    );
    try {
      final info = await UpdateCheckHelper.checkWithUi();
      if (info == null) {
        messenger.currentState?.showSnackBar(
          const SnackBar(content: Text('已是最新版本')),
        );
      }
    } catch (e) {
      messenger.currentState?.showSnackBar(
        SnackBar(content: Text('检查失败：$e')),
      );
    }
  }

  Future<void> _exportData(BuildContext context) async {
    final msg = await DataExportService.export(
      context.read<ConfigService>(),
      bookmarks: context.read<BookmarksService>(),
      history: context.read<HistoryService>(),
      downloads: context.read<DownloadsService>(),
    );
    if (context.mounted) {
      messengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
    }
  }

  Future<void> _importData(BuildContext context) async {
    final msg = await DataExportService.import(
      context.read<ConfigService>(),
      profilesDir: AppPaths.profilesDir,
    );
    if (context.mounted) {
      messengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
    }
  }

  Future<void> _copyDiagnostics(
      BuildContext context, ConfigService config, KernelRegistry registry) async {
    final kernels =
        registry.describe().map((d) => '${d.displayName}:${d.available}').join(', ');
    final text = 'Zip Browser ${BrowserConstants.appVersion} '
        '(${BuildFlavorInfo.label})\n'
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
        '内核: $kernels\n数据目录: ${AppPaths.supportDir.path}';
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('诊断信息已复制'), duration: Duration(seconds: 1)),
      );
    }
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    return Card(
      margin: const EdgeInsets.only(bottom: ZbTokens.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZbTokens.s5, ZbTokens.s4, ZbTokens.s5, 0),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          ...children,
          SizedBox(height: zb.isDark ? 2 : 0),
        ],
      ),
    );
  }
}
