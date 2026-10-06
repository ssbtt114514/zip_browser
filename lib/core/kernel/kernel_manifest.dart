import 'kernel_types.dart';

/// 独立内核包清单（包内 `kernel.json`）。
///
/// 内核包（.zbk，本质是 zip）结构示例：
/// ```
/// zip-browser-kernel-chromium-120.0.0.zbk
/// ├── kernel.json                 必需：本清单
/// ├── bin/
/// │   ├── windows/kernel.dll      按平台/ABI 存放的原生库
/// │   ├── linux/libkernel.so
/// │   └── android/arm64-v8a/libkernel.so
/// ├── runtime/                    可选：WebView2 Fixed Version 类运行时目录
/// └── README.md                   可选
/// ```
///
/// 清单字段：
/// ```json
/// {
///   "manifest_version": 1,
///   "id": "com.example.kernel.chromium",
///   "name": "Chromium 独立内核",
///   "version": "120.0.6099.1",
///   "engine": "chromium",
///   "type": "ffi",
///   "abi_version": 1,
///   "display_name": "Chromium 120（独立内核包）",
///   "description": "……",
///   "engine_version": "120.0.6099.1",
///   "capabilities": ["loadUrl", "evaluateJs", "multiTab"],
///   "libraries": {
///     "windows": "bin/windows/kernel.dll",
///     "linux": "bin/linux/libkernel.so",
///     "android": { "arm64-v8a": "bin/android/arm64-v8a/libkernel.so" }
///   },
///   "runtime_dir": "runtime"
/// }
/// ```
class KernelManifest {
  final int manifestVersion;
  final String id;
  final String name;
  final String version;

  /// 引擎谱系：chromium / gecko / system / custom
  final KernelEngine engine;

  /// 加载方式：`ffi`（dart:ffi 加载原生库）/ `webview2_fixed`（运行时目录）
  final String type;

  /// FFI ABI 版本，需与宿主支持的一致
  final int abiVersion;

  final String? displayName;
  final String? description;

  /// 底层引擎版本号（如 120.0.6099.1）
  final String? engineVersion;

  /// 声明的能力位（清单字符串，见 [KernelCapabilityKey]）
  final List<String> capabilities;

  /// 平台 -> 库文件相对路径。字符串：单库；Map（Android）：按 ABI 选择
  final Map<String, dynamic> libraries;

  /// Fixed Version 类运行时目录（相对包根）
  final String? runtimeDir;

  KernelManifest({
    required this.manifestVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.engine,
    required this.type,
    this.abiVersion = 1,
    this.displayName,
    this.description,
    this.engineVersion,
    this.capabilities = const [],
    this.libraries = const {},
    this.runtimeDir,
  });

  static const supportedTypes = {'ffi', 'webview2_fixed'};

  /// 展示名（缺省时回退到 name）
  String get title => displayName ?? name;

  /// 解析后的能力集合
  Set<KernelCapability> get capabilitySet {
    final out = <KernelCapability>{};
    for (final key in capabilities) {
      final c = KernelCapabilityKey.fromKey(key);
      if (c != null) out.add(c);
    }
    return out;
  }

  static KernelManifest fromJson(Map<String, dynamic> json) {
    final errors = <String>[];

    String req(String key) {
      final v = json[key];
      if (v is! String || v.trim().isEmpty) {
        errors.add('字段 "$key" 缺失或不是非空字符串');
        return '';
      }
      return v.trim();
    }

    final id = req('id');
    final name = req('name');
    final version = req('version');

    final mv = json['manifest_version'];
    if (mv is! int) errors.add('字段 "manifest_version" 必须是整数');

    if (id.isNotEmpty &&
        !RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+)+$').hasMatch(id)) {
      errors.add(
        '"id" 必须采用反向域名格式（小写字母/数字/下划线，点分隔），如 com.example.kernel.chromium',
      );
    }

    final type = (json['type'] as String? ?? 'ffi').trim();
    if (!supportedTypes.contains(type)) {
      errors.add('"type" 必须是 ${supportedTypes.join(' / ')} 之一，当前为 "$type"');
    }

    final abi = json['abi_version'];
    if (abi != null && abi is! int) {
      errors.add('字段 "abi_version" 必须是整数');
    }

    final libs = json['libraries'];
    if (libs != null && libs is! Map) {
      errors.add('字段 "libraries" 必须是对象');
    }

    final caps = json['capabilities'];
    if (caps != null && caps is! List) {
      errors.add('字段 "capabilities" 必须是数组');
    }

    return KernelManifest(
      manifestVersion: mv is int ? mv : 1,
      id: id,
      name: name,
      version: version,
      engine: KernelEngine.parse(json['engine'] as String?),
      type: type,
      abiVersion: abi is int ? abi : 1,
      displayName: json['display_name'] as String?,
      description: json['description'] as String?,
      engineVersion: json['engine_version'] as String?,
      capabilities:
          (caps as List?)?.whereType<String>().toList() ?? const [],
      libraries: libs is Map
          ? _parseLibraries(libs)
          : const {},
      runtimeDir: json['runtime_dir'] as String?,
    ).._validationErrors.addAll(errors);
  }

  static Map<String, dynamic> _parseLibraries(Map raw) {
    return raw.map((k, v) {
      if (v is Map) {
        return MapEntry(
          k.toString(),
          Map<String, String>.from(
            v.map((kk, vv) => MapEntry(kk.toString(), vv.toString())),
          ),
        );
      }
      return MapEntry(k.toString(), v.toString());
    });
  }

  final List<String> _validationErrors = <String>[];

  /// 清单校验错误；为空表示合法
  List<String> get validationErrors => List.unmodifiable(_validationErrors);

  /// 解析指定平台（Android 需给 [abi]）的库相对路径
  String? libraryRelativeFor(String platform, {String? abi}) {
    final v = libraries[platform];
    if (v is String) return v;
    if (v is Map && abi != null) {
      final s = v[abi];
      return s is String ? s : null;
    }
    return null;
  }

  /// 该内核包是否声明了当前平台的产物
  bool supportsPlatform(String platform, {String? abi}) =>
      libraryRelativeFor(platform, abi: abi) != null ||
      (type == 'webview2_fixed' && runtimeDir != null && platform == 'windows');
}
