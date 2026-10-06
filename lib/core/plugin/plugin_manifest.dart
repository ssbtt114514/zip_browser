/// zip 插件包清单（manifest.json）的 Dart 模型。
///
/// 包结构：
/// ```
/// my_plugin.zip
/// ├── manifest.json           必需
/// ├── extension.js            content scripts（由 manifest 引用）
/// ├── background.js           可选：常驻脚本
/// ├── icons/icon.png          可选
/// ├── ui/popup.html           可选：工具栏弹窗
/// ├── kernels/                可选：插件携带的内核
/// │   ├── windows/xxx.dll
/// │   └── android/libxxx.so
/// └── signature.sig           可选：签名
/// ```
class PluginManifest {
  final int manifestVersion;
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? author;
  final String? homepage;

  /// 最低宿主（本浏览器）版本，语义化版本
  final String? minHostVersion;

  /// 权限：tabs / storage / webNavigation / downloads /
  ///       nativeMessaging / kernel / menus
  final List<String> permissions;

  /// 主机权限（可访问的站点范围），如 https://*.example.com/*
  final List<String> hostPermissions;

  /// 网页可访问资源（扩展内可被页面引用的文件）
  final List<String> webAccessibleResources;

  /// 来源：zip（原生）/ chromium / gecko（导入的浏览器扩展）
  final String source;

  final List<ContentScriptRule> contentScripts;
  final BackgroundSpec? background;
  final PluginKernelSpec? kernel;
  final PluginUiSpec? ui;

  PluginManifest({
    required this.manifestVersion,
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.author,
    this.homepage,
    this.minHostVersion,
    this.permissions = const [],
    this.hostPermissions = const [],
    this.webAccessibleResources = const [],
    this.source = 'zip',
    this.contentScripts = const [],
    this.background,
    this.kernel,
    this.ui,
  });

  static PluginManifest fromJson(Map<String, dynamic> json) {
    final errors = <String>[];

    String req(String key) {
      final v = json[key];
      if (v is! String || v.trim().isEmpty) {
        errors.add('字段 "$key" 缺失或不是非空字符串');
        return '';
      }
      return v;
    }

    final id = req('id');
    final name = req('name');
    final version = req('version');
    final mv = json['manifest_version'];
    if (mv is! int) errors.add('字段 "manifest_version" 必须是整数');

    if (id.isNotEmpty && !RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+)+$').hasMatch(id)) {
      errors.add(
        '"id" 必须采用反向域名格式（小写字母/数字/下划线，点分隔），如 com.example.darkmode',
      );
    }

    return PluginManifest(
      manifestVersion: mv is int ? mv : 1,
      id: id,
      name: name,
      version: version,
      description: json['description'] as String?,
      author: json['author'] as String?,
      homepage: json['homepage'] as String?,
      minHostVersion: json['min_host_version'] as String?,
      permissions: (json['permissions'] as List?)?.whereType<String>().toList() ?? const [],
      hostPermissions: (json['host_permissions'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      webAccessibleResources: _parseWebResources(json['web_accessible_resources']),
      source: json['source'] as String? ?? 'zip',
      contentScripts: (json['content_scripts'] as List?)
              ?.whereType<Map>()
              .map((e) => ContentScriptRule.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      background: json['background'] is Map
          ? BackgroundSpec.fromJson(Map<String, dynamic>.from(json['background'] as Map))
          : null,
      kernel: json['kernel'] is Map
          ? PluginKernelSpec.fromJson(Map<String, dynamic>.from(json['kernel'] as Map))
          : null,
      ui: json['ui'] is Map
          ? PluginUiSpec.fromJson(Map<String, dynamic>.from(json['ui'] as Map))
          : null,
    ).._validationErrors.addAll(errors);
  }

  /// 解析 web_accessible_resources：兼容 MV2（字符串数组）
  /// 与 MV3（对象数组 {resources, matches}）。
  static List<String> _parseWebResources(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      if (e is String) {
        out.add(e);
      } else if (e is Map && e['resources'] is List) {
        out.addAll((e['resources'] as List).whereType<String>());
      }
    }
    return out;
  }

  final List<String> _validationErrors = <String>[];

  /// 清单校验错误；为空表示合法
  List<String> get validationErrors => List.unmodifiable(_validationErrors);

  bool hasPermission(String permission) => permissions.contains(permission);
}

/// content_scripts 规则
class ContentScriptRule {
  final List<String> matches;
  final List<String> js;
  final String runAt; // document_start / document_end

  const ContentScriptRule({
    required this.matches,
    required this.js,
    this.runAt = 'document_end',
  });

  factory ContentScriptRule.fromJson(Map<String, dynamic> json) {
    return ContentScriptRule(
      matches: (json['matches'] as List?)?.whereType<String>().toList() ?? const ['<all_urls>'],
      js: (json['js'] as List?)?.whereType<String>().toList() ?? const [],
      runAt: json['run_at'] as String? ?? 'document_end',
    );
  }
}

/// background 常驻脚本（在隐藏的扩展页面中运行）
class BackgroundSpec {
  final List<String> js;
  final String? page;

  const BackgroundSpec({this.js = const [], this.page});

  factory BackgroundSpec.fromJson(Map<String, dynamic> json) {
    return BackgroundSpec(
      js: (json['js'] as List?)?.whereType<String>().toList() ?? const [],
      page: json['page'] as String?,
    );
  }
}

/// 插件携带内核的声明
class PluginKernelSpec {
  /// `ffi`：原生库通过 dart:ffi 加载
  /// `webview2_fixed`：WebView2 Fixed Version 运行时目录（Windows）
  final String type;

  /// FFI ABI 版本，需与宿主支持的 ABI 匹配
  final int abiVersion;

  /// 平台 -> 库文件相对路径，键：windows / android / linux / macos。
  /// 值为字符串：该平台单一库；
  /// 值为 Map（Android）：按 ABI 选择，键 arm64-v8a / armeabi-v7a / x86_64。
  final Map<String, dynamic> libraries;

  /// Fixed Version 运行时目录（相对插件目录）
  final String? runtimeDir;

  /// 内核展示名（将出现在内核选择列表中）
  final String? displayName;

  const PluginKernelSpec({
    required this.type,
    this.abiVersion = 1,
    this.libraries = const {},
    this.runtimeDir,
    this.displayName,
  });

  /// 解析当前平台（Android 需指定 [abi]）的库相对路径
  String? libraryRelativeFor(String platform, {String? abi}) {
    final v = libraries[platform];
    if (v is String) return v;
    if (v is Map && abi != null) {
      final s = v[abi];
      return s is String ? s : null;
    }
    return null;
  }

  factory PluginKernelSpec.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> parseLibraries(Map raw) {
      return raw.map((k, v) {
        if (v is Map) {
          return MapEntry(k.toString(), Map<String, String>.from(
            v.map((kk, vv) => MapEntry(kk.toString(), vv.toString())),
          ));
        }
        return MapEntry(k.toString(), v.toString());
      });
    }

    return PluginKernelSpec(
      type: json['type'] as String? ?? 'ffi',
      abiVersion: json['abi_version'] as int? ?? 1,
      libraries: json['libraries'] is Map
          ? parseLibraries(json['libraries'] as Map)
          : const {},
      runtimeDir: json['runtime_dir'] as String?,
      displayName: json['display_name'] as String?,
    );
  }
}

/// 声明式 UI 扩展
class PluginUiSpec {
  final ToolbarButton? toolbarButton;
  final List<MenuItem> menuItems;

  const PluginUiSpec({this.toolbarButton, this.menuItems = const []});

  factory PluginUiSpec.fromJson(Map<String, dynamic> json) {
    return PluginUiSpec(
      toolbarButton: json['toolbar_button'] is Map
          ? ToolbarButton.fromJson(Map<String, dynamic>.from(json['toolbar_button'] as Map))
          : null,
      menuItems: (json['menu_items'] as List?)
              ?.whereType<Map>()
              .map((e) => MenuItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }
}

class ToolbarButton {
  final String icon;
  final String title;
  final String? popup;

  const ToolbarButton({required this.icon, required this.title, this.popup});

  factory ToolbarButton.fromJson(Map<String, dynamic> json) {
    return ToolbarButton(
      icon: json['icon'] as String? ?? 'icons/icon.png',
      title: json['title'] as String? ?? '插件',
      popup: json['popup'] as String?,
    );
  }
}

class MenuItem {
  final String id;
  final String title;

  /// 点击后执行的 bridge 方法（在扩展 background 上下文中）
  final String? action;

  const MenuItem({required this.id, required this.title, this.action});

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      action: json['action'] as String?,
    );
  }
}
