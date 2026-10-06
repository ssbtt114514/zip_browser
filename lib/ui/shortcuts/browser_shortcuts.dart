import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tab/tab_manager.dart';
import '../../core/tab/tab_model.dart';
import '../../services/bookmarks_service.dart';
import '../../services/config_service.dart';
import '../../services/ui_state.dart';
import '../omnibox_controller.dart';
import '../pages/bookmarks_page.dart';
import '../pages/downloads_page.dart';
import '../pages/history_page.dart';
import 'browser_focus.dart';

/// 构建浏览器键盘快捷键绑定表。
///
/// 说明：
/// * 只绑定"浏览器级"组合键（Ctrl+T / Ctrl+W / Ctrl+L / Alt+← …），
///   不劫持 Ctrl+A / Ctrl+C / Ctrl+V 等编辑类组合键，避免破坏输入框行为；
/// * Windows / Linux / Android 外接键盘统一使用 Ctrl，符合主流浏览器习惯；
/// * 快捷键依赖焦点位于 [CallbackShortcuts] 子树内，因此地图栏收起、
///   内容区被点击等场景会用 [BrowserFocus] 把焦点收回根节点。
Map<ShortcutActivator, VoidCallback> browserShortcutBindings(
  BuildContext context,
) {
  final tm = context.read<TabManager>();
  final config = context.read<ConfigService>();
  final ui = context.read<BrowserUiState>();
  final omnibox = context.read<OmniboxController>();
  final bookmarks = context.read<BookmarksService>();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  void toast(String message) {
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1400),
    ));
  }

  TabModel? active() => tm.active;

  void openPage(Widget page) {
    navigator.push(MaterialPageRoute(builder: (_) => page));
  }

  final bindings = <ShortcutActivator, VoidCallback>{
    // —— 标签页 ——
    const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
      tm.createTab();
    },
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
      tm.createTab();
    },
    const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
        () {
      tm.createTab(private: true);
      toast('已新建隐私标签');
    },
    const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
      final tab = active();
      if (tab != null) tm.closeTab(tab.id);
    },
    const SingleActivator(LogicalKeyboardKey.keyT,
        control: true, shift: true): () {
      tm.reopenClosedTab();
    },
    const SingleActivator(LogicalKeyboardKey.tab, control: true): () {
      tm.activateNext();
    },
    const SingleActivator(LogicalKeyboardKey.tab,
        control: true, shift: true): () {
      tm.activatePrevious();
    },
    const SingleActivator(LogicalKeyboardKey.digit9, control: true): () {
      tm.activateAt(tm.tabs.length - 1);
    },

    // —— 地址栏与查找 ——
    const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
      omnibox.focusNode.requestFocus();
    },
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
      ui.openFind();
    },
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (ui.findOpen) {
        active()?.kernel.findClear();
        ui.closeFind();
        BrowserFocus.take(context);
      } else if (ui.sniffOpen) {
        ui.closeSniff();
      } else if (ui.secondaryOpen) {
        ui.setSecondaryOpen(false);
      } else {
        omnibox.close();
        BrowserFocus.take(context);
      }
    },

    // —— 导航 ——
    const SingleActivator(LogicalKeyboardKey.f5): () {
      active()?.kernel.reload();
    },
    const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
      active()?.kernel.reload();
    },
    const SingleActivator(LogicalKeyboardKey.keyR,
        control: true, shift: true): () async {
      final tab = active();
      if (tab == null) return;
      await tab.kernel.clearCache();
      await tab.kernel.reload();
    },
    const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () {
      active()?.kernel.goBack();
    },
    const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () {
      active()?.kernel.goForward();
    },
    const SingleActivator(LogicalKeyboardKey.browserBack): () {
      active()?.kernel.goBack();
    },
    const SingleActivator(LogicalKeyboardKey.browserForward): () {
      active()?.kernel.goForward();
    },
    const SingleActivator(LogicalKeyboardKey.home, alt: true): () {
      tm.navigateActive(config.homePage);
    },

    // —— 缩放 ——
    const SingleActivator(LogicalKeyboardKey.equal, control: true): () {
      tm.zoomIn();
    },
    const SingleActivator(LogicalKeyboardKey.add, control: true): () {
      tm.zoomIn();
    },
    const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () {
      tm.zoomIn();
    },
    const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
      tm.zoomOut();
    },
    const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () {
      tm.zoomOut();
    },
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): () {
      tm.resetZoom();
      toast('缩放已重置为 100%');
    },

    // —— 书签与数据面板 ——
    const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
      final tab = active();
      if (tab == null) return;
      final url = tab.url.value;
      if (url.startsWith('data:') || url == 'about:home') {
        toast('内置页面无法加入书签');
        return;
      }
      if (bookmarks.isBookmarked(url)) {
        bookmarks.removeByUrl(url);
        toast('已移除书签');
      } else {
        bookmarks.add(title: tab.title.value, url: url);
        toast('已加入书签');
      }
    },
    const SingleActivator(LogicalKeyboardKey.keyO,
        control: true, shift: true): () {
      openPage(BookmarksPage(onOpen: (u) => tm.navigateActive(u)));
    },
    const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
      openPage(HistoryPage(onOpen: (u) => tm.navigateActive(u)));
    },
    const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () {
      openPage(const DownloadsPage());
    },
    const SingleActivator(LogicalKeyboardKey.keyB,
        control: true, shift: true): () {
      config.setShowBookmarksBar(!config.showBookmarksBar);
    },

    // —— 视图 ——
    const SingleActivator(LogicalKeyboardKey.keyA,
        control: true, shift: true): () {
      toast('标签页搜索：点击标签栏右侧的搜索按钮');
    },
    const SingleActivator(LogicalKeyboardKey.f11): () {
      ui.toggleFullscreen();
    },
    const SingleActivator(LogicalKeyboardKey.f12): () {
      toast('当前内核未提供开发者工具');
    },
  };

  // —— 按序号切换标签（Ctrl+1..8 → 第 1..8 个）——
  // LogicalKeyboardKey(0x31 + i) 即 digit1..digit8
  for (var i = 0; i < 8; i++) {
    bindings[SingleActivator(LogicalKeyboardKey(0x31 + i), control: true)] =
        () {
      tm.activateAt(i);
    };
  }

  return bindings;
}
