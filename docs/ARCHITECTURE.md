# Zip Browser 架构设计

一个使用 **Flutter** 开发、可通过 **zip 插件**扩展功能与浏览器内核的多平台浏览器框架。

- 当前支持：**Android**、**Windows**
- 规划支持：**Linux**、**macOS**

---

## 1. 分层总览

```
┌──────────────────────────────────────────────────────────┐
#  UI 层  lib/ui
│   BrowserShell / TabBar / AddressBar / Toolbar
│   PluginsPage（安装/启停）/ SettingsPage（内核切换）
├──────────────────────────────────────────────────────────┤
#  应用核心  lib/core
│   tab/        TabManager、TabModel（多标签状态）
│   kernel/     BrowserKernel 抽象、KernelRegistry
│   bridge/     JsBridgeHub（JS <-> Dart 消息与权限）
│   plugin/     PluginManager、PluginPackage（zip 安装）、
│               PluginSecurity、FfiKernelLoader
├──────────────────────────────────────────────────────────┤
#  平台适配  lib/platform
│   AndroidSystemKernel   webview_flutter → 系统 Android System WebView
│   WindowsSystemKernel   webview_windows → 系统 WebView2 / Fixed Version
│   PluginFfiKernel       dart:ffi → 插件携带的原生内核
│   StubKernel            Linux/macOS 占位
└──────────────────────────────────────────────────────────┘
        │ 原生表面（可选，插件内核渲染）
        ▼
native_plugins/zb_native_surface   注册 Flutter 纹理 / 帧提交
```

### 关键决策：为什么插件是 zip，以及 Flutter 的能力边界

Flutter 在 release（AOT）模式下**无法在运行时动态加载 Dart 源码或字节码**，
因此 zip 插件不能携带 Dart 代码。插件能力通过以下三种机制实现，
覆盖了浏览器扩展的绝大多数需求：

| 机制 | 载体 | 能力 | 示例 |
|------|------|------|------|
| **JS 扩展** | `extension.js` 等 | 操作页面 DOM、监听事件、调用宿主 API（Promise） | 夜间模式、去广告、翻译、油猴脚本 |
| **原生内核/原生库** | `.dll` / `.so`（C ABI） | 替换浏览器内核，或提供原生计算能力 | 携带固定版本 Chromium、自研内核 |
| **声明式 UI** | `manifest.ui` | 工具栏按钮、菜单项、popup 页面 | 扩展入口、设置弹窗 |

JS 扩展在网页内核的 JS 引擎中执行（与 Chrome 扩展的 content script、
Tampermonkey 脚本同构），通过统一的 `window.zipBrowser.call(method, params)`
调用宿主能力，宿主按插件声明的权限做白名单控制。

---

## 2. 浏览器内核抽象

`lib/core/kernel/browser_kernel.dart` 定义统一接口 `BrowserKernel`，
一个实例对应一个标签页：

```text
initialize(config)   buildView()
loadUrl / goBack / goForward / reload / stop
evaluateJavascript
registerBridgeHandler
事件流：navigationEvents / progress / urlChanges /
        titleChanges / resourceErrors
```

### 内核来源 `KernelOrigin`

- **system（系统内核）**
  - Android：系统 **Android System WebView**
    （`com.google.android.webview`，由系统统一更新）
  - Windows：**WebView2 Evergreen Runtime**（Edge Chromium，系统组件）
- **plugin（插件内核）**
  - Windows：插件 zip 携带的 **WebView2 Fixed Version** 固定版本运行时
    （`browserExecutableFolder`），或任意遵循 C ABI 的第三方内核（`.dll`）
  - Android：插件携带的 `.so` 内核（实验性，需 JNI/EGL 表面桥）

### 内核选择 `KernelRegistry`

1. `SettingsPage` 中选择内核，id 持久化在 `ConfigService`。
2. 每个新标签页 `createKernel(tabId)`：
   - 未选择 → 平台默认系统内核
   - `plugin.<id>` → 插件 Fixed Runtime 或 FFI 内核；加载失败自动回退系统内核
3. 切换内核**只影响新标签页**（WebView2 环境为进程级，切换 Fixed Version
   需重启应用，UI 会提示）。

---

## 3. zip 插件包格式

```text
my_plugin.zip
├── manifest.json            必需：元数据 / 权限 / 脚本 / 内核 / UI
├── extension.js             content script（manifest 引用）
├── background.js            可选：常驻脚本
├── icons/
│   └── icon.png
├── ui/
│   └── popup.html           可选：工具栏弹窗
├── kernels/                 可选：插件内核
│   ├── windows/xxx.dll
│   ├── android/libxxx.so
│   ├── linux/libxxx.so
│   └── macos/libxxx.dylib
└── signature.sig            可选：数字签名（见 §5）
```

### manifest.json（关键字段）

```json
{
  "manifest_version": 1,
  "id": "com.example.darkmode",
  "name": "夜间模式",
  "version": "1.0.0",
  "min_host_version": "0.1.0",
  "permissions": ["storage", "tabs"],
  "content_scripts": [
    { "matches": ["<all_urls>"], "js": ["extension.js"],
      "run_at": "document_end" }
  ],
  "kernel": {
    "type": "ffi",
    "abi_version": 1,
    "libraries": { "windows": "kernels/windows/xxx.dll" }
  },
  "ui": {
    "toolbar_button": { "icon": "icons/icon.png",
                        "title": "扩展", "popup": "ui/popup.html" }
  }
}
```

### 权限 → bridge 方法映射

| 权限 | 授予的宿主方法 |
|------|----------------|
| `tabs` | `tabs.create / close / update / query / active` |
| `storage` | `storage.get / set / remove / keys`（按插件分区） |
| `webNavigation` | `webNavigation.getFrame / getAllFrames` |
| `downloads` | `downloads.create / query` |
| `nativeMessaging` | `nativeMessaging.send / connect` |
| `menus` | `menus.create / remove / onClick` |
| `kernel` | `kernel.query / switch` |

### 安装流程（`PluginPackage.install`）

1. `archive` 解码 zip，定位并解析 `manifest.json`，做字段与 id 格式校验
2. **Zip Slip 防护**：拒绝 `..`、绝对路径、盘符等非法条目路径
3. 计算 zip **SHA-256**，按白名单校验（如启用）
4. 解压到临时目录 → 计算目录指纹 → 原子重命名为 `plugins/<id>/`
5. 写入 `install.json`（版本、指纹、安装时间、启用状态）

---

## 4. JS Bridge 设计

`JsBridgeHub` 生成一段 `documentStart` 注入的引导脚本，在页面建立：

```js
window.zipBrowser.call('storage.get', { key: 'x' }).then(value => ...)
window.zipBrowser.on('event', data => ...)
```

- 页面消息 → 内核通道（Android `JavaScriptChannel` /
  Windows `chrome.webview.postMessage`）→ `handleRaw`
- 权限：仅 `allowedMethods` 内的方法可调用，否则返回
  `permission denied`
- 宿主结果由内核执行回页面（`__respond`）；宿主可主动 `__emit` 事件
- 不同内核只需负责“原始字符串进出”，通信逻辑完全复用

---

## 5. 安全模型

当前实现：

1. **安装指纹**：zip 的 SHA-256 展示给用户确认
2. **防篡改**：安装时记录目录文件清单哈希；每次启动重算，
   不一致则强制停用并在插件页告警
3. **白名单**：`trusted_plugins.json`（插件 id → 允许的 zip 哈希），
   可在设置中强制仅允许白名单
4. **权限最小化**：插件仅能调用其声明权限对应的 bridge 方法
5. **原生库安全**：FFI 库必须 ABI 版本匹配；建议配合签名使用

升级路径：引入 `pointycastle` 对 `signature.sig` 做
**RSASSA-PKCS1-v1_5 + SHA-256** 验签（内置宿主公钥），
形成完整的插件签名链。

---

## 6. 平台策略对照

| 平台 | 系统内核 | 承载插件 | 插件内核 | 状态 |
|------|----------|----------|----------|------|
| Android | Android System WebView | `webview_flutter` | `.so`（实验） | ✅ |
| Windows | WebView2 (Edge Chromium) | `webview_windows` | Fixed Version / `.dll` | ✅ |
| Linux | 规划（WebKitGTK / CEF） | 待定 | `.so` | 🚧 占位 |
| macOS | 规划（WKWebView / CEF） | 待定 | `.dylib` | 🚧 占位 |

> Android 端“浏览器内核调用系统的 Android System WebView”——
> `webview_flutter_android` 内部即实例化系统 `android.webkit.WebView`，
> 不打包任何内核，随系统组件更新。
>
> Windows 端使用 WebView2：Evergreen 为系统运行时；
> Fixed Version 可由插件 zip 携带，实现“内核在插件里”且版本完全可控。

---

## 7. 目录结构

```text
zip_browser/
├── pubspec.yaml
├── lib/
│   ├── main.dart / app.dart
│   ├── core/{kernel,plugin,bridge,tab}/
│   ├── platform/                 # 各平台内核实现
│   ├── ui/{widgets,pages}/
│   └── services/                 # 路径 / 配置 / 宿主 API
├── native_plugins/zb_native_surface/   # 原生表面（插件内核渲染）
│   ├── include/zb_plugin_kernel_abi.h
│   ├── windows/*.cpp *.h
│   └── android/*.kt
├── example_plugins/
│   ├── dark_mode/                # JS 扩展示例
│   └── hello_ffi_kernel/         # FFI 内核示例
└── tool/                          # 初始化 / 打包 / 集成脚本
```

---

## 8. 后续路线图

- [ ] Linux：WebKitGTK 或 CEF 系统内核适配
- [ ] macOS：WKWebView 系统内核适配
- [ ] background 常驻脚本与 popup 的完整渲染容器
- [ ] RSASSA-PKCS1 插件签名验签
- [ ] 插件市场 / 在线安装与更新
- [ ] 下载管理器、历史、书签等内置 API 完善
- [ ] 插件内核的 GPU（OpenGL/ANGLE）零拷贝表面
