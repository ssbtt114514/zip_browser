import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../services/bookmarks_service.dart';

/// 地址栏：URL 展示 / 搜索与导航 / 安全标识 / 停止-刷新
class AddressBar extends StatefulWidget {
  const AddressBar({super.key});

  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _boundTabId;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  String _displayUrl(String url) {
    if (url.startsWith('data:') || url == 'about:home') return '';
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    // 书签变化时刷新星标
    context.watch<BookmarksService>();
    final tab = tm.active;

    if (tab == null) {
      return Expanded(child: Container());
    }

    // 切换标签时重新绑定
    if (_boundTabId != tab.id) {
      _boundTabId = tab.id;
      if (!_focusNode.hasFocus) {
        _controller.text = _displayUrl(tab.url.value);
      }
    }

    return Expanded(
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: _focusNode.hasFocus ? Colors.white : const Color(0xFFF1F5F8),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: _focusNode.hasFocus
                ? Theme.of(context).colorScheme.primary
                : const Color(0xFFD3DEE6),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            ValueListenableBuilder<String>(
              valueListenable: tab.url,
              builder: (_, url, __) {
                final secure = url.startsWith('https://');
                final internal =
                    url.startsWith('data:') || url.startsWith('about:');
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    internal
                        ? Icons.home_outlined
                        : secure
                            ? Icons.lock_outline
                            : Icons.lock_open,
                    size: 15,
                    color: internal
                        ? Colors.black38
                        : secure
                            ? Colors.green.shade600
                            : Colors.black45,
                  ),
                );
              },
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: tab.url,
                builder: (_, url, __) {
                  if (!_focusNode.hasFocus) {
                    _controller.text = _displayUrl(url);
                  }
                  return TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.go,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '搜索或输入网址',
                      contentPadding: EdgeInsets.symmetric(vertical: 9),
                    ),
                    onSubmitted: (value) async {
                      await tm.navigateActive(value);
                      _focusNode.unfocus();
                    },
                    onTap: () {
                      // 聚焦时全选，方便直接替换
                      _controller.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _controller.text.length,
                      );
                    },
                  );
                },
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: tab.isLoading,
              builder: (_, loading, __) {
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => loading
                      ? tab.kernel.stopLoading()
                      : tab.kernel.reload(),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      loading ? Icons.close : Icons.refresh,
                      size: 17,
                    ),
                  ),
                );
              },
            ),
            // 书签星标
            ValueListenableBuilder<String>(
              valueListenable: tab.url,
              builder: (_, url, __) {
                final internal =
                    url.startsWith('data:') || url == 'about:home';
                final marked =
                    !internal && context.read<BookmarksService>().isBookmarked(url);
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: internal
                      ? null
                      : () {
                          final bm = context.read<BookmarksService>();
                          if (marked) {
                            bm.removeByUrl(url);
                          } else {
                            bm.add(title: tab.title.value, url: url);
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      marked ? Icons.star : Icons.star_border,
                      size: 17,
                      color: marked ? Colors.amber.shade700 : null,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
