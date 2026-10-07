import '../core/adblock/adblock_data.dart';
import '../core/adblock/adblock_script.dart';
import '../core/kernel/kernel_types.dart';
import 'config_service.dart';

/// 广告拦截服务：把内置规则 + 用户自定义域名组装成注入页面脚本。
class AdBlockerService {
  final ConfigService _config;
  AdBlockerService(this._config);

  /// 组装注入脚本（在 TabManager 初始化标签时调用，注入所有内核）。
  ///
  /// 关闭开关时返回空列表；白名单优先于拦截规则。
  UserScript buildUserScript() {
    final custom = _config.adBlockCustomDomains;
    final allow = [
      ...kAdBlockAllowDomains,
      ..._config.adBlockAllowDomains,
    ];
    final domains = [...kAdBlockDomains, ...custom];
    return UserScript(
      source: AdBlocker.buildScript(
        domains: domains,
        allow: allow,
        selectors: kAdBlockSelectors,
      ),
      timing: UserScriptInjectionTiming.documentStart,
      pluginId: null,
    );
  }

  /// 判断单个 URL 是否命中拦截（供内核导航层主框架拦截使用）。
  bool isBlocked(String url) {
    final host = _hostOf(url);
    if (host.isEmpty) return false;
    for (final w in _config.adBlockAllowDomains) {
      if (host == w || host.endsWith('.$w')) return false;
    }
    for (final d in [...kAdBlockDomains, ..._config.adBlockCustomDomains]) {
      if (host == d || host.endsWith('.$d')) return true;
    }
    return false;
  }

  static String _hostOf(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme) return '';
      return uri.host.toLowerCase();
    } catch (_) {
      return '';
    }
  }
}
