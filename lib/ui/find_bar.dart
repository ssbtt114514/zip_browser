import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 页面内查找栏
class FindBar extends StatefulWidget {
  final Future<int> Function(String query) onFind;
  final Future<void> Function(bool forward) onNext;
  final Future<void> Function() onClose;

  const FindBar({
    super.key,
    required this.onFind,
    required this.onNext,
    required this.onClose,
  });

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final TextEditingController _controller = TextEditingController();
  int _count = 0;
  Timer? _debounce;

  Future<void> _runFind(String value) async {
    if (value.isEmpty) {
      // 清空关键词时让内核一并清除页面高亮，避免残留旧匹配
      await widget.onFind('');
      if (mounted) setState(() => _count = 0);
      return;
    }
    final n = await widget.onFind(value);
    if (mounted) setState(() => _count = n);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      // 查找栏获得焦点时 Esc 也能关闭（全局快捷键被输入框吞掉时的兜底）
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          widget.onClose();
        },
      },
      child: Material(
        elevation: 3,
        color: scheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '在页面中查找',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixText: _controller.text.isEmpty ? null : '$_count',
                      suffixStyle: TextStyle(
                          color: _count > 0 ? scheme.primary : Colors.red,
                          fontSize: 13),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(
                          const Duration(milliseconds: 250), () => _runFind(v));
                    },
                    // Enter：立即查找并跳到下一个匹配，符合常见浏览器习惯
                    onSubmitted: (_) async {
                      _debounce?.cancel();
                      final v = _controller.text.trim();
                      if (v.isEmpty) return;
                      final n = await widget.onFind(v);
                      if (!mounted) return;
                      setState(() => _count = n);
                      if (n > 0) await widget.onNext(true);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: '上一个',
                  onPressed: () => widget.onNext(false),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: '下一个',
                  onPressed: () => widget.onNext(true),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭查找',
                  onPressed: () async {
                    _debounce?.cancel();
                    await widget.onClose();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
