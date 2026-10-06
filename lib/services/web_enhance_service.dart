import 'package:flutter/foundation.dart';

import '../core/kernel/browser_kernel.dart';
import '../core/web/web_enhance_script.dart';
import '../core/web/web_enhance_settings.dart';
import 'config_service.dart';

/// 网页阅读增强服务：持有设置并把效果注入到内核页面。
class WebEnhanceService extends ChangeNotifier {
  final ConfigService config;

  WebEnhanceService(this.config);

  WebEnhanceSettings get settings => config.webEnhance;

  Future<void> update(WebEnhanceSettings next) async {
    await config.setWebEnhance(next);
    notifyListeners();
  }

  Future<void> setFilter(WebFilterMode mode) =>
      update(settings.copyWith(filter: mode));

  Future<void> setNoImage(bool value) =>
      update(settings.copyWith(noImage: value));

  Future<void> setFontScale(double value) => update(
      settings.copyWith(fontScale: value.clamp(0.8, 2.0).toDouble()));

  Future<void> setLineHeight(double value) => update(
      settings.copyWith(lineHeight: value.clamp(1.2, 2.4).toDouble()));

  Future<void> setAutoReader(bool value) =>
      update(settings.copyWith(autoReader: value));

  /// 页面加载完成后应用增强（在每次导航完成时调用）
  Future<void> applyTo(BrowserKernel kernel) async {
    await kernel.evaluateJavascript(WebEnhanceScript.apply(settings));
    if (settings.autoReader) {
      // 避免重复打开：仅在阅读层不存在时创建
      final open = await kernel.evaluateJavascript(
          WebEnhanceScript.readerState());
      if (open != 'true') {
        await kernel.evaluateJavascript(WebEnhanceScript.toggleReader(settings));
      }
    }
  }

  /// 切换当前页阅读模式
  Future<void> toggleReader(BrowserKernel kernel) async {
    await kernel.evaluateJavascript(WebEnhanceScript.toggleReader(settings));
  }

  Future<void> closeReader(BrowserKernel kernel) async {
    await kernel.evaluateJavascript(WebEnhanceScript.closeReader());
  }
}
