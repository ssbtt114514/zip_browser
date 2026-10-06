import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/bridge/js_bridge.dart';
import '../core/kernel/kernel_registry.dart';
import '../core/tab/tab_manager.dart';
import '../core/tab/url_utils.dart';
import '../core/tab/home_page.dart';
import 'config_service.dart';
import 'paths.dart';

/// 宿主向扩展 JS 暴露的全部能力实现。
/// 插件只有在 manifest 中声明对应权限后，方法才会进入白名单。
class HostBridgeApi {
  final TabManager tabManager;
  final ConfigService config;
  final KernelRegistry kernelRegistry;

  Map<String, dynamic> _storageRoot = {};
  bool _storageLoaded = false;

  HostBridgeApi({
    required this.tabManager,
    required this.config,
    required this.kernelRegistry,
  });

  File get _storageFile =>
      File(p.join(AppPaths.profilesDir.path, 'extension_storage.json'));

  Future<Map<String, dynamic>> _root() async {
    if (!_storageLoaded) {
      _storageLoaded = true;
      if (_storageFile.existsSync()) {
        try {
          _storageRoot =
              jsonDecode(_storageFile.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {
          _storageRoot = {};
        }
      }
    }
    return _storageRoot;
  }

  Future<Map<String, dynamic>> _partition(String? pluginId) async {
    final root = await _root();
    final key = pluginId ?? '_page';
    return root.putIfAbsent(key, () => <String, dynamic>{}) as Map<String, dynamic>;
  }

  Future<void> _flush() async {
    await _storageFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_storageRoot),
    );
  }

  Map<String, BridgeHandler> handlers() {
    return <String, BridgeHandler>{
      // —— tabs ——
      'tabs.create': (r) async {
        final url = r.paramsMap['url'] as String?;
        final tab = await tabManager.createTab(url: url);
        return BridgeResult.ok({'id': tab.id});
      },
      'tabs.close': (r) async {
        final id = r.paramsMap['id'] as String? ??
            tabManager.active?.id;
        if (id != null) await tabManager.closeTab(id);
        return BridgeResult.ok();
      },
      'tabs.update': (r) async {
        final id = r.paramsMap['id'] as String?;
        final url = r.paramsMap['url'] as String?;
        final tab = id == null ? tabManager.active : tabManager.byTabId(id);
        if (tab == null) return BridgeResult.fail('tab not found');
        if (url != null) {
          final resolved = UrlInput.resolve(url,
              searchEngineTemplate: config.searchEngine,
              homeDataUri: HomePage.dataUri(config.searchEngine));
          await tab.kernel.loadUrl(resolved);
        }
        return BridgeResult.ok();
      },
      'tabs.query': (r) async {
        return BridgeResult.ok(tabManager.tabs
            .map((t) => {'id': t.id, 'url': t.url.value, 'title': t.title.value})
            .toList());
      },
      'tabs.active': (r) async {
        final id = r.paramsMap['id'] as String?;
        if (id != null) tabManager.activate(id);
        return BridgeResult.ok({'id': tabManager.active?.id});
      },

      // —— storage（按插件分区）——
      'storage.get': (r) async {
        final part = await _partition(r.pluginId);
        final key = r.paramsMap['key'] as String?;
        return BridgeResult.ok(key == null ? part : part[key]);
      },
      'storage.set': (r) async {
        final part = await _partition(r.pluginId);
        part[r.paramsMap['key'].toString()] = r.paramsMap['value'];
        await _flush();
        return BridgeResult.ok();
      },
      'storage.remove': (r) async {
        final part = await _partition(r.pluginId);
        part.remove(r.paramsMap['key'].toString());
        await _flush();
        return BridgeResult.ok();
      },
      'storage.keys': (r) async {
        final part = await _partition(r.pluginId);
        return BridgeResult.ok(part.keys.toList());
      },

      // —— downloads ——
      'downloads.create': (r) async {
        final url = r.paramsMap['url'] as String?;
        if (url == null) return BridgeResult.fail('缺少 url');
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          return BridgeResult.fail('HTTP ${response.statusCode}');
        }
        final dir = await getDownloadsDirectory() ?? AppPaths.downloadCacheDir;
        dir.createSync(recursive: true);
        final name = url.split('?').first.split('/').last;
        final filename = name.isEmpty ? 'download_${DateTime.now().millisecondsSinceEpoch}' : name;
        final file = File(p.join(dir.path, filename));
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return BridgeResult.ok({'path': file.path, 'bytes': response.bodyBytes.length});
      },
      'downloads.query': (r) async => BridgeResult.ok(const []),

      // —— kernel ——
      'kernel.query': (r) async {
        return BridgeResult.ok(kernelRegistry.describe()
            .map((d) => {'id': d.id, 'name': d.displayName, 'origin': d.origin.name})
            .toList());
      },
      'kernel.switch': (r) async {
        final id = r.paramsMap['id'] as String?;
        await config.setSelectedKernelId(id == null || id == 'system' ? null : id);
        return BridgeResult.ok({'note': '新打开的标签页将使用所选内核'});
      },

      // —— webNavigation（简化：返回当前 URL）——
      'webNavigation.getFrame': (r) async =>
          BridgeResult.ok({'url': tabManager.active?.url.value}),
      'webNavigation.getAllFrames': (r) async =>
          BridgeResult.ok([
            {'frameId': 0, 'url': tabManager.active?.url.value}
          ]),

      // —— nativeMessaging（当前版本未启用）——
      'nativeMessaging.send': (r) async =>
          BridgeResult.fail('当前宿主版本未提供原生消息端口'),
      'nativeMessaging.connect': (r) async =>
          BridgeResult.fail('当前宿主版本未提供原生消息端口'),

      // —— menus（占位注册，由 UI 侧渲染）——
      'menus.create': (r) async => BridgeResult.ok(),
      'menus.remove': (r) async => BridgeResult.ok(),
      'menus.onClick': (r) async => BridgeResult.ok(),

      // —— cookies（基于当前标签页 document.cookie）——
      'cookies.get': (r) async {
        final kernel = tabManager.active?.kernel;
        if (kernel == null) return BridgeResult.fail('no active tab');
        final raw = await kernel
            .evaluateJavascript('document.cookie || ""');
        final jar = <String, String>{};
        if (raw != null) {
          for (final pair in raw.split(';')) {
            final idx = pair.indexOf('=');
            if (idx <= 0) continue;
            jar[pair.substring(0, idx).trim()] =
                pair.substring(idx + 1).trim();
          }
        }
        final name = r.paramsMap['name'] as String?;
        if (name != null) {
          return BridgeResult.ok(
              jar.containsKey(name) ? {'name': name, 'value': jar[name]} : null);
        }
        return BridgeResult.ok(jar);
      },
      'cookies.set': (r) async {
        final kernel = tabManager.active?.kernel;
        if (kernel == null) return BridgeResult.fail('no active tab');
        final name = r.paramsMap['name'] as String?;
        final value = r.paramsMap['value'] as String? ?? '';
        if (name == null) return BridgeResult.fail('缺少 name');
        await kernel.evaluateJavascript(
            'document.cookie = ${jsonEncode('$name=$value')};');
        return BridgeResult.ok();
      },
      'cookies.remove': (r) async {
        final kernel = tabManager.active?.kernel;
        if (kernel == null) return BridgeResult.fail('no active tab');
        final name = r.paramsMap['name'] as String?;
        if (name == null) return BridgeResult.fail('缺少 name');
        await kernel.evaluateJavascript(
            'document.cookie = ${jsonEncode('$name=')}; '
            "expires=Thu, 01 Jan 1970 00:00:00 GMT;");
        return BridgeResult.ok();
      },

      // —— notifications（以宿主 SnackBar 呈现）——
      'notifications.create': (r) async {
        final title = r.paramsMap['title'] as String? ?? '';
        final message = r.paramsMap['message'] as String? ?? '';
        tabManager.notifyExtension(
            message.isEmpty ? title : '$title：$message');
        return BridgeResult.ok();
      },
    };
  }
}
