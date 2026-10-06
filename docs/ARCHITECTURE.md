# Zip Browser 架构设计

一个使用 **Flutter** 开发、可通过 **zip 插件**扩展功能与浏览器内核的多平台浏览器框架。

- 当前支持：**Android**、**Windows**
- 规划支持：**Linux**、**macOS**

---

## 1. 分层总览

```
┌──────────────────────────────────────────────────────────┐
#  UI 层  lib/ui
│   design/     设计令牌 + 语义色板 ZbColors（外壳统一取色）
│   browser_shell.dart   外壳装配 + 根焦点 + 键盘快捷键宿主
│   widgets/    TabBar / AddressBar / OmniboxSuggestions /
│               BookmarksBar / MainToolbar / SecondaryToolbar
│   shortcuts/  browserShortcutBindings + BrowserFocus
│   omnibox_controller.dart  地址栏与联想面板的共享状态
│   pages/      PluginsPage / SettingsPage / KernelsPage …
├──────────────────────────────────────────────────────────┤
#  应用核心  lib/core
│   tab/        TabManager、TabModel（多标签状态）
│   kernel/     BrowserKernel 抽象、KernelRegistry
│   bridge/     JsBridgeHub（JS <-> Dart 消息与权限）
│   plugin/     PluginManager、PluginPackage（zip 安装）、
│               PluginSecurity、FfiKernelLoader
│   theme/      ThemeEngine（亮/暗色 + 莫奈取色）
├──────────────────────────────────────────────────────────┤
#  服务层  lib/services
│   config / paths / host_bridge_api（含 net.fetch）
│   zoom（按站点缩放）/ session（会话恢复）/ url_suggest（补全）
│   bookmarks / history / downloads / ui_state / web_enhance
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

        │ 内核实现（可选，可热插拔）
        ▼
native_kernels/zb_lite_kernel      零依赖 C99 软件渲染内核
```

### 界面层设计（v0.6.0 重新设计）

重设计之前，外壳组件把颜色写死在组件里（标签栏 `Color(0xFFE7EDF2)`、
地址栏 `Colors.white`、标签文字 `Colors.black87`），导致深色主题下外壳整片
发白、文字不可读。现在改为**单一颜色来源**：

- `lib/ui/design/zb_design.dart` 提供两层抽象：
  - `ZbTokens`：尺寸 / 间距 / 动效时长等设计令牌；
  - `ZbColors`：把 `ColorScheme` 映射为外壳语义色
    （`chrome` / `chromeElevated` / `tabActive` / `omniboxFill` /
    `hairline` / `hover` / `pressed` / `secure` / `privateSurface` …），
    经 `context.zb` 取用。所有外壳组件只引用语义色，颜色随深色模式与
    莫奈动态取色实时联动。
- `ZbColors` 的正确性由 `test/ui_design_test.dart` 锁死：断言深色主题下
  标签栏 / 工具栏亮度 < 0.2、浅色主题 > 0.6、活动标签与外壳存在层次差、
  地址栏文字与底色对比度达标等。

**外壳装配**（`browser_shell.dart`）：

```
CallbackShortcuts(browserShortcutBindings)
└─ Focus(根焦点)
   └─ BrowserFocus(InheritedWidget，向任意后代暴露根 FocusNode)
      └─ Scaffold
         ├─ [宽屏] BrowserTabBar
         ├─ MainToolbar（导航 + AddressBar + 工具箱 + 扩展 + 主菜单）
         ├─ [可选] BookmarksBar
         ├─ [可选] SecondaryToolbar（AnimatedSize 展开/收起）
         ├─ 进度条 / [窄屏] BrowserTabBar
         ├─ [可选] FindBar
         └─ Listener(内容区)
            └─ Stack(clipBehavior: none)
               ├─ IndexedStack(各标签内核视图，保活)
               ├─ 嗅探提示横幅
               ├─ OmniboxSuggestions（联想下拉）
               └─ [可选] SniffPanel
```

两个关键约束：

1. **联想下拉为什么放在内容区**：它必须覆盖网页内容而不被工具栏高度裁切。
   因此面板渲染在内容区顶部 Stack 中，通过 `CompositedTransformFollower`
   绑定到地址栏 Pill 的 `LayerLink`，并读取实测宽度对齐；Stack 需要
   `clipBehavior: Clip.none`，否则面板顶部会被裁掉几像素。
2. **键盘快捷键为什么需要根焦点**：快捷键依赖"活动焦点位于
   `CallbackShortcuts` 子树内"。地址栏主动收起、点击网页等场景会让焦点
   落到作用域之外，导致快捷键整体失效。因此：
   - 主动收起时 `BrowserFocus.take()` 无条件把焦点交给根节点；
   - 被动场景（点击内容区）用 `BrowserFocus.ensureHeld()`，仅在
     `primaryFocus == null` 时才收回，避免抢走网页表单的输入焦点。

**状态共享**（`lib/ui/omnibox_controller.dart`）：地址栏输入框与联想面板
位于组件树两处，共享同一个 `OmniboxController`（焦点 / 文本 / 建议 /
高亮 / 锚点）。它会在地址栏 `build` 期间被调用（同步宽度、绑定标签），
因此**绝不能在 build 阶段直接 `notifyListeners()` 或改写
`TextEditingController`** —— 那会让 TextField 与面板在构建期被标记重建并
抛异常。所有此类更新都经内部 `_notifySafely()` 推迟到帧后。

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
4. **权限最小化**：页面与 content script 仅能调用其声明权限对应的 bridge
   方法（`JsBridgeHub.handleRaw` 按 `allowedMethods` 白名单拦截）
5. **原生库安全**：FFI 库必须 ABI 版本匹配；建议配合签名使用
6. **原生内核的调用路径（重要区别）**：插件内核经 `host_dispatch` 发起的宿主
   能力请求走 `JsBridgeHub.invokeLocal`，**不经过上面的权限白名单**。这是刻意
   设计 —— 原生库本身就是宿主体内的任意代码，白名单无法约束它。因此对插件
   内核的信任依据是「安装指纹 + 目录防篡改 + ABI 版本匹配」，而非权限声明。
   相应地，宿主对内核可用的能力做了收敛：`net.fetch` 只接受 http/https 与
   GET/POST，并设默认 2 MiB、硬上限 16 MiB 的响应体截断。

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
│   ├── core/{kernel,plugin,bridge,tab,theme,script,sniff,web}/
│   ├── platform/                 # 各平台内核实现
│   ├── ui/
│   │   ├── design/               # 设计令牌 + 语义色板（外壳唯一取色来源）
│   │   ├── shortcuts/            # 键盘快捷键绑定 + 根焦点作用域
│   │   ├── widgets/              # 标签栏 / 地址栏 / 联想下拉 / 书签栏 / 工具栏
│   │   ├── pages/                # 设置 / 书签 / 历史 / 下载 / 内核 / 插件 …
│   │   ├── omnibox_controller.dart
│   │   └── browser_shell.dart
│   └── services/                 # 配置 / 路径 / 宿主 API / 缩放 / 会话 / 补全 …
├── native_plugins/zb_native_surface/   # 原生表面（插件内核渲染）
│   ├── include/zb_plugin_kernel_abi.h
│   ├── windows/*.cpp *.h
│   └── android/*.kt
├── native_kernels/zb_lite_kernel/      # 零依赖 C99 软件渲染内核（源码 + 自检）
├── example_plugins/
│   ├── dark_mode/                # JS 扩展示例
│   ├── hello_ffi_kernel/         # FFI 内核示例
│   └── lite_kernel/              # 轻量文本内核插件（manifest + 图标 + dll）
├── build_kernel_pkg/zb_lite_kernel/    # 独立内核包（.zbk）源目录
├── test/                         # 单元 + 集成测试（含 FFI ABI 端到端）
└── tool/                          # 初始化 / 打包 / 构建 / 集成 / 一键验证脚本
```

### 验证体系

| 层次 | 手段 | 覆盖内容 |
|------|------|----------|
| C 内核 | `tests/zb_lite_kernel_selftest.c` | create → load HTML → attach 假 surface → tick → 校验帧缓冲确有像素，106 项断言 |
| C↔Dart ABI | `test/ffi_kernel_integration_test.dart` | 用真实 `FfiKernelLink` 加载 DLL，校验 `stride`、帧内容、eval_js、输入事件、改尺寸重排版 |
| 打包链路 | `test/lite_kernel_package_test.dart` | 打包 → `PluginPackage` / `KernelPackage` 安装 → ABI 与导出符号 |
| 界面 | `test/ui_design_test.dart` | 深/浅色外壳语义色、对比度、层次差；内置新标签页结构 |
| 服务 | `test/zoom_service_test.dart` 等 | 缩放档位与站点记忆、会话快照、地址栏补全 |
| 全量 | `python tool/verify_all.py` | 把上述可离线项 + 工作流校验串成一条命令 |

---

## 8. 后续路线图

v0.6.0 已完成：界面层重新设计（统一语义色板）、按站点缩放、会话恢复、
地址栏本地补全、完整键盘快捷键、标签固定/复制/批量关闭、`net.fetch` 宿主能力、
可交互的软件渲染内核（`zb_lite_kernel`）。

下一步：

- [ ] Linux：WebKitGTK 或 CEF 系统内核适配
- [ ] macOS：WKWebView 系统内核适配
- [ ] 站点权限管理（摄像头 / 麦克风 / 定位 / 通知 / 剪贴板）
- [ ] 自动填充与密码管理
- [ ] 标签页 / 书签云同步（需后端）
- [ ] background 常驻脚本与 popup 的完整渲染容器
- [ ] RSASSA-PKCS1 插件签名验签
- [ ] 插件市场 / 在线安装与更新
- [ ] 打印 / 另存为 / 页面截图等系统集成
- [ ] 插件内核的 GPU（OpenGL/ANGLE）零拷贝表面
- [ ] `zb_lite_kernel`：CJK 真实字形（当前为等宽豆腐块占位）、
      `table` 列对齐、`pre` 横向滚动、真正的 JS 引擎（当前为命令式 eval_js）
