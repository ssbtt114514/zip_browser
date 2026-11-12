import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_keys.dart';
import '../../core/debug/debug_injector.dart';
import '../../core/debug/debug_log.dart';
import '../../core/debug/debug_log_source.dart';
import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
import '../design/zb_design.dart';

/// 页面调试面板：控制台 / 网络 / 执行 JS / 页面信息。
///
/// 说明：WebView2 不提供把 Edge DevTools 嵌入第三方窗口的能力，
/// 因此这里提供应用内自研面板；Windows 下可另开原生 DevTools 窗口。
class DebuggerPage extends StatefulWidget {
  const DebuggerPage({super.key});

  @override
  State<DebuggerPage> createState() => _DebuggerPageState();
}

class _DebuggerPageState extends State<DebuggerPage>
    with SingleTickerProviderStateMixin {
  final List<DebugLogEntry> _entries = [];
  final ScrollController _consoleScroll = ScrollController();
  final TextEditingController _jsInput = TextEditingController();
  final FocusNode _jsFocus = FocusNode();

  late final TabController _tabs =
      TabController(length: 4, vsync: this);
  TabModel? _tab;
  StreamSubscription<DebugLogEntry>? _sub;
  bool _followTail = true;

  String _jsResult = '';
  bool _jsRunning = false;
  Map<String, String> _info = const {};
  bool _infoLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _consoleScroll.dispose();
    _jsInput.dispose();
    _jsFocus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _attach() {
    if (!mounted) return;
    final tm = context.read<TabManager>();
    final tab = tm.active;
    if (tab == null) return;
    _tab = tab;

    final kernel = tab.kernel;
    if (kernel is DebugLogSource) {
      // DebugLogSource 与 BrowserKernel 无继承关系，需显式转换
      _sub = (kernel as DebugLogSource).debugLogs.listen((entry) {
        if (!mounted) return;
        setState(() {
          _entries.add(entry);
          if (_entries.length > 500) _entries.removeAt(0);
        });
        if (_followTail && _tabs.index == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_consoleScroll.hasClients) {
              _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
            }
          });
        }
      });
    }

    _installHooks();
    _refreshInfo();
  }

  /// 页面若在开关关闭时加载，补齐当前文档的调试钩子（脚本自身幂等）
  Future<void> _installHooks() async {
    final tab = _tab;
    if (tab == null || tab.kernel is! DebugLogSource) return;
    await tab.kernel.evaluateJavascript(
      DebugInjector.buildScript(
        bridgeGlobalName: tab.kernel.bridge.globalName,
      ),
    );
  }

  Future<void> _refreshInfo() async {
    final tab = _tab;
    if (tab == null) return;
    setState(() => _infoLoading = true);
    final raw = await tab.kernel.evaluateJavascript('''
(function(){
  try {
    return JSON.stringify({
      url: location.href,
      title: document.title,
      ua: navigator.userAgent,
      viewport: innerWidth + ' × ' + innerHeight,
      dpr: String(devicePixelRatio),
      state: document.readyState
    });
  } catch (e) { return ''; }
})()
''');
    var text = _unwrapJson(raw);
    if (text == null) {
      setState(() {
        _info = {
          '页面': '当前内核无法读取页面信息',
        };
        _infoLoading = false;
      });
      return;
    }
    Map<String, dynamic> map = const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) map = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    setState(() {
      _info = {
        'URL': '${map['url'] ?? '-'}',
        '标题': '${map['title'] ?? '-'}',
        '视口': '${map['viewport'] ?? '-'}',
        'DPR': '${map['dpr'] ?? '-'}',
        '文档状态': '${map['state'] ?? '-'}',
        'User-Agent': '${map['ua'] ?? '-'}',
      };
      _infoLoading = false;
    });
  }

  /// 内核可能返回 JSON 字符串的字符串形式，逐层解开
  String? _unwrapJson(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') return null;
    var value = raw;
    for (var i = 0; i < 3; i++) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is String) {
          value = decoded;
          continue;
        }
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  Future<void> _runJs() async {
    final tab = _tab;
    final code = _jsInput.text.trim();
    if (tab == null || code.isEmpty) return;
    setState(() {
      _jsRunning = true;
      _jsResult = '';
    });
    try {
      final raw = await tab.kernel.evaluateJavascript('''
(function(){
  var __r = (function(){ $code
  })();
  try { return JSON.stringify(__r === undefined ? 'undefined' : __r); }
  catch (e) { return String(__r); }
})()
''');
      if (!mounted) return;
      setState(() {
        _jsResult = _unwrapJson(raw) ?? '（无返回值）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _jsResult = '执行失败：$e');
    } finally {
      if (mounted) setState(() => _jsRunning = false);
    }
  }

  Future<void> _openNativeDevTools() async {
    final tab = _tab;
    final kernel = tab?.kernel;
    if (kernel is! NativeDevTools) return;
    final ok = await (kernel as NativeDevTools).openNativeDevTools();
    if (!ok && mounted) {
      messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('打开原生 DevTools 失败')),
      );
    }
  }

  Future<void> _copyAll() async {
    final text = _entries
        .map((e) => '[${e.timeLabel}] ${e.kindLabel} ${e.displayText}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('已复制当前日志'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final zb = context.zb;
    final tab = _tab;
    final supported = tab?.kernel is DebugLogSource;
    final hasNative = tab?.kernel is NativeDevTools && Platform.isWindows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('页面调试'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '控制台'),
            Tab(text: '网络'),
            Tab(text: '执行 JS'),
            Tab(text: '页面信息'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '跟随最新日志',
            isSelected: _followTail,
            icon: const Icon(Icons.vertical_align_bottom),
            onPressed: () => setState(() => _followTail = !_followTail),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(_entries.clear),
          ),
          IconButton(
            tooltip: '复制日志',
            icon: const Icon(Icons.copy_all),
            onPressed: _copyAll,
          ),
          if (hasNative)
            IconButton(
              tooltip: '打开原生 DevTools 窗口',
              icon: const Icon(Icons.open_in_new),
              onPressed: _openNativeDevTools,
            ),
        ],
      ),
      body: Column(
        children: [
          if (!supported)
            Container(
              width: double.infinity,
              color: zb.suggestionHighlight,
              padding: const EdgeInsets.all(ZbTokens.s5),
              child: Text(
                '当前内核不提供调试钩子通道（仅 Android WebView / Windows WebView2 支持）',
                style: TextStyle(fontSize: 12, color: zb.textPrimary),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildLogList(context, network: false),
                _buildLogList(context, network: true),
                _buildJsPanel(context),
                _buildInfoPanel(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(BuildContext context, {required bool network}) {
    final zb = context.zb;
    final list = _entries
        .where((e) =>
            network ? e.kind == DebugLogKind.network : e.kind != DebugLogKind.network)
        .toList();
    if (list.isEmpty) {
      return Center(
        child: Text(
          network ? '暂无网络请求记录' : '暂无日志，页面输出会实时出现在这里',
          style: TextStyle(fontSize: 12.5, color: zb.textMuted),
        ),
      );
    }
    return ListView.builder(
      controller: network ? null : _consoleScroll,
      padding: const EdgeInsets.symmetric(vertical: ZbTokens.s2),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final e = list[i];
        return Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ZbTokens.s5, vertical: ZbTokens.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.timeLabel,
                style: TextStyle(
                    fontSize: 11, fontFamily: 'monospace', color: zb.textMuted),
              ),
              const SizedBox(width: ZbTokens.s4),
              SizedBox(
                width: 64,
                child: Text(
                  e.kindLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: _kindColor(context, e.kind),
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  e.displayText,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontFamily: 'monospace',
                    color: _kindColor(context, e.kind),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _kindColor(BuildContext context, DebugLogKind kind) {
    final scheme = Theme.of(context).colorScheme;
    return switch (kind) {
      DebugLogKind.error || DebugLogKind.exception => scheme.error,
      DebugLogKind.warn => const Color(0xFFB26A00),
      DebugLogKind.network => scheme.primary,
      DebugLogKind.info => scheme.tertiary,
      DebugLogKind.log => DefaultTextStyle.of(context).style.color ??
          scheme.onSurface,
    };
  }

  Widget _buildJsPanel(BuildContext context) {
    final zb = context.zb;
    return ListView(
      padding: const EdgeInsets.all(ZbTokens.s5),
      children: [
        TextField(
          controller: _jsInput,
          focusNode: _jsFocus,
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: const InputDecoration(
            labelText: 'JavaScript',
            hintText: '例如：document.title',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: ZbTokens.s4),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _jsRunning ? null : _runJs,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(_jsRunning ? '执行中…' : '运行'),
            ),
            const SizedBox(width: ZbTokens.s4),
            TextButton(
              onPressed: () => setState(() {
                _jsInput.clear();
                _jsResult = '';
              }),
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: ZbTokens.s5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(ZbTokens.s5),
          decoration: BoxDecoration(
            color: zb.chromeElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            _jsResult.isEmpty ? '（结果会显示在这里）' : _jsResult,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontFamily: 'monospace',
              color: _jsResult.isEmpty ? zb.textMuted : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoPanel(BuildContext context) {
    if (_infoLoading && _info.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ZbTokens.s5),
      children: [
        Row(
          children: [
            const Text('页面信息', style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: _infoLoading ? null : _refreshInfo,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            ),
          ],
        ),
        for (final e in _info.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZbTokens.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: Text(e.key,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: SelectableText(e.value,
                      style: const TextStyle(fontSize: 12.5, height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
