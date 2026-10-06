import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;

import '../core/tab/tab_model.dart';
import '../services/url_suggest_service.dart';

/// 地址栏（Omnibox）共享控制器。
///
/// 地址栏输入框与"建议下拉面板"位于组件树的两个不同位置（输入框在工具栏，
/// 下拉面板在内容区顶部的 Stack 中，才能正确覆盖网页内容），因此把
/// 焦点、文本、建议、锚点（[LayerLink]）集中到这里，两端都监听同一个
/// [ChangeNotifier]。
///
/// 注意：本类会在地址栏 `build` 期间被调用（同步宽度、绑定标签），
/// 因此**绝不能**在 build 阶段直接 [notifyListeners] 或改写
/// TextEditingController 的文本 —— 那会让 TextField / 面板在构建期
/// 被标记重建并抛出异常。所有此类更新都经 [_notifySafely] 延迟到帧后。
class OmniboxController extends ChangeNotifier {
  /// 下拉面板的定位锚点（绑定到地址栏 Pill 的 LayerLink）
  final LayerLink layerLink = LayerLink();

  final FocusNode focusNode = FocusNode(debugLabel: 'omnibox');
  final TextEditingController text = TextEditingController();

  UrlSuggestService? _suggest;

  /// 地址栏 Pill 的实时宽度（下拉面板对齐用）
  double width = 0;

  List<UrlSuggestion> _suggestions = const [];
  int _highlight = -1;

  /// 当前绑定的标签（用于跟随地址变化）
  TabModel? _tab;
  VoidCallback? _urlListener;

  bool _focused = false;
  bool _disposed = false;

  /// 待应用文本（在 build 阶段触发时延迟到帧后写入）
  String? _pendingText;

  OmniboxController() {
    focusNode.addListener(_onFocusChanged);
  }

  void attach(UrlSuggestService service) {
    _suggest = service;
  }

  List<UrlSuggestion> get suggestions => _suggestions;

  int get highlight => _highlight;

  bool get isFocused => _focused;

  /// 下拉面板是否应显示
  bool get showSuggestions => _focused && _suggestions.isNotEmpty;

  /// 地址栏文本的展示形式：内置页与 data: 页不显示地址
  static String displayUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('data:') || url == 'about:home') return '';
    return url;
  }

  static bool get _inBuildPhase =>
      WidgetsBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  /// 安全通知：build 阶段一律推迟到帧后，避免"构建期重建"异常
  void _notifySafely() {
    if (_disposed) return;
    if (_inBuildPhase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  /// 绑定活动标签：切换时重新挂监听，并同步一次显示文本
  void bindTab(TabModel? tab) {
    if (identical(tab, _tab)) return;
    final oldTab = _tab;
    final oldListener = _urlListener;
    if (oldTab != null && oldListener != null) {
      oldTab.url.removeListener(oldListener);
    }
    _tab = tab;
    _urlListener = null;
    if (tab == null) return;

    void onUrlChanged() {
      if (!_focused) _applyText(displayUrl(tab.url.value));
    }

    _urlListener = onUrlChanged;
    tab.url.addListener(onUrlChanged);

    _applyText(displayUrl(tab.url.value));
  }

  /// 写入显示文本；build 阶段延后执行
  void _applyText(String value) {
    if (text.text == value) return;
    if (_inBuildPhase) {
      _pendingText = value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        final pending = _pendingText;
        _pendingText = null;
        if (pending != null) _writeText(pending);
      });
      return;
    }
    _writeText(value);
  }

  void _writeText(String value) {
    if (text.text == value) return;
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void setWidth(double value) {
    if ((value - width).abs() < 0.5) return;
    width = value;
    // 宽度变化只需重绘下拉面板；build 阶段延后
    _notifySafely();
  }

  void _onFocusChanged() {
    final nowFocused = focusNode.hasFocus;
    if (nowFocused == _focused) return;
    _focused = nowFocused;
    if (_focused) {
      // 聚焦时全选，方便直接覆写
      final len = text.text.length;
      text.selection = TextSelection(baseOffset: 0, extentOffset: len);
      _recompute();
    } else {
      _suggestions = const [];
      _highlight = -1;
      // 失焦后回到当前页面地址
      final tab = _tab;
      if (tab != null) _applyText(displayUrl(tab.url.value));
    }
    notifyListeners();
  }

  /// 输入变化
  void onQueryChanged(String query) {
    _recompute(query: query);
    notifyListeners();
  }

  void _recompute({String? query}) {
    final service = _suggest;
    final q = query ?? text.text;
    if (service == null) {
      _suggestions = const [];
      _highlight = -1;
      return;
    }
    _suggestions = service.suggest(q);
    _highlight = _suggestions.isEmpty ? -1 : 0;
  }

  /// 键盘上下移动高亮项
  void moveHighlight(int delta) {
    if (_suggestions.isEmpty) return;
    var next = _highlight + delta;
    if (next < 0) next = _suggestions.length - 1;
    if (next >= _suggestions.length) next = 0;
    _highlight = next;
    notifyListeners();
  }

  void setHighlight(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    if (_highlight == index) return;
    _highlight = index;
    notifyListeners();
  }

  /// 提交当前输入，返回要导航的目标（null 表示不导航）。
  ///
  /// [rawInput] 为空时回退到高亮建议；若高亮项是"搜索 / 直达"建议则优先采用。
  UrlSuggestion? commitTarget(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      if (_highlight >= 0 && _highlight < _suggestions.length) {
        return _suggestions[_highlight];
      }
      return null;
    }
    if (_highlight >= 0 && _highlight < _suggestions.length) {
      final s = _suggestions[_highlight];
      if (s.kind == SuggestionKind.search || s.kind == SuggestionKind.open) {
        return s;
      }
    }
    return UrlSuggestion(
      text: trimmed,
      url: trimmed,
      kind: SuggestionKind.open,
    );
  }

  /// 关闭下拉并失焦
  void close() {
    _suggestions = const [];
    _highlight = -1;
    if (focusNode.hasFocus) {
      focusNode.unfocus();
    } else {
      notifyListeners();
    }
  }

  /// 仅收起下拉，保持焦点
  void collapseSuggestions() {
    if (_suggestions.isEmpty && _highlight == -1) return;
    _suggestions = const [];
    _highlight = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final tab = _tab;
    final listener = _urlListener;
    if (tab != null && listener != null) {
      tab.url.removeListener(listener);
    }
    focusNode.removeListener(_onFocusChanged);
    focusNode.dispose();
    text.dispose();
    super.dispose();
  }
}
