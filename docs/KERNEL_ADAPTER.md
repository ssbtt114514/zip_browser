# 引擎适配包（`type: engine_adapter`）

引擎适配包是一种**不携带渲染库**的内核包：它把一个引擎谱系（当前是
`gecko`）接进「内核管理」，由宿主的适配器内核负责**探测本机是否已有该引擎的
运行时**，并把探测结果如实展示给用户。

> 结论先写在前面：**引擎适配包不渲染网页。** 它不加载 `xul.dll` /
> `libxul.so`，不创建任何渲染表面，也不会让标签页显示网页内容。
> 现成示例见 [`build_kernel_pkg/zb_gecko_kernel/`](../build_kernel_pkg/zb_gecko_kernel/README.md)。

## 与其它两种类型的关系

| | `ffi` | `webview2_fixed` | `engine_adapter` |
|---|---|---|---|
| 携带产物 | 原生库（`libraries`） | 运行时目录（`runtime_dir`） | **无** |
| 加载方式 | `dart:ffi` 加载导出符号 | 交给系统内核以固定版本运行时启动 | 纯 Dart 探测，不加载任何东西 |
| 平台可用性 | 仅清单声明的平台 | 仅 Windows | 全平台（`availableOn()` 恒为 true） |
| 能力位 | 由清单声明 | 由清单声明 | 必须为空（`capabilities: []`） |
| 能否渲染 | 能 | 能 | **不能** |

三者共用同一套安装与选择流程：`KernelPackage.install()` → `KernelManager` →
`KernelRegistry.describe()` → 「内核管理」列表 → `KernelRegistry.createKernel()`。
差异只在最后一步实例化出哪种 `BrowserKernel`。

## kernel.json 字段

```json
{
  "manifest_version": 1,
  "id": "com.zipbrowser.kernel.gecko",
  "name": "Gecko 内核适配包",
  "display_name": "Gecko 内核适配包（不提供网页渲染）",
  "version": "1.0.0",
  "engine": "gecko",
  "type": "engine_adapter",
  "abi_version": 1,
  "description": "只探测本机 Gecko 运行时，不提供离屏渲染。",
  "capabilities": []
}
```

| 字段 | 必需 | 说明 |
|---|---|---|
| `type` | 是 | 固定 `engine_adapter` |
| `engine` | 是 | 适配的引擎谱系（当前只有 `gecko` 有探测实现） |
| `capabilities` | 是 | 必须为空数组：适配包不提供任何渲染能力 |
| `libraries` | 否 | **不应出现**：适配包不携带原生库 |
| `runtime_dir` | 否 | **不应出现**：适配包不携带运行时目录 |
| `abi_version` | 否 | 仍须与宿主 `kSupportedKernelAbiVersion` 一致（当前 `1`） |

校验规则（`KernelPackage.install()` 与 `tool/pack_kernel.py` 一致）：

- 允许 `libraries` 与 `runtime_dir` **同时为空**——这正是适配包的正常形态；
  `ffi` / `webview2_fixed` 的产物校验保持不变。
- 因为不携带平台产物，`InstalledKernel.availableOn()` 对所有平台返回 `true`，
  `KernelManifest.supportsPlatform()` 同理。这只回答「能不能安装 / 能不能选中」，
  **不回答「能不能渲染」**——后者由运行时探测结果决定。

## 运行时探测（Gecko）

`EngineRuntimeLocator`（`lib/platform/engine_adapter_kernel.dart`）是纯 Dart 的
探测器，所有探测动作都可注入（文件存在探测、文本读取、环境变量、平台字符串），
因此单元测试不依赖任何真实环境。

候选来源与优先级：

1. **内置安装路径**（`knownPath`）：Windows `%ProgramFiles%` /
   `%ProgramFiles(x86)%` / `%LOCALAPPDATA%` 下的 `Mozilla Firefox\xul.dll` 与
   Firefox ESR；Linux `/usr/lib/firefox`、`/usr/lib/firefox-esr`、
   `/usr/lib64/firefox`、`/opt/firefox`、snap 的 `libxul.so`；Android
   `/system/lib64`、`/system/lib`、`/product/lib64`、`/vendor/lib64` 下的
   `libxul.so` / `libgeckoview.so`；macOS `Firefox.app/Contents/MacOS/libxul.dylib`。
2. **环境变量**（`environment`）：`MOZ*` 开头且值形如路径的项；值是目录就按平台
   库名拼子路径，值本身就是库文件则直接作为运行时库。
3. **PATH 可执行文件**（`pathExecutable`）：`firefox` / `firefox.exe` /
   `firefox-esr`——**这只是安装痕迹**，不能证明运行时可用。

判定规则：

- 只有**运行时库**命中才算 `found == true`；浏览器可执行文件命中只算线索
  （`hasClueOnly`），文案明确写「发现安装痕迹，但未确认可加载的运行时库」。
- 版本号只从运行时同目录的 `platform.ini`（`Milestone`）或 `application.ini`
  （`Version`）里读；读不到就是 `null`，界面显示「未读取到（不编造版本号）」，
  **绝不**用清单里的 `version` 冒充引擎版本。

## 能力边界（明确"不渲染"）

`EngineAdapterKernel` 的行为是刻意"什么都不做"的：

| 接口 | 行为 |
|---|---|
| `buildView()` | 只显示探测报告：引擎名、探测结论、命中方式、版本、候选路径命中表、"为什么不渲染"说明、"重新检测"按钮 |
| `loadUrl(url)` | 记录请求地址，发出**一条 `blocked` 导航事件**；不发 `start` / `finished` / `progress`，因此没有假加载动画，也不会把没加载的地址写进历史记录 |
| `evaluateJavascript()` | 返回 `''`（没有页面上下文） |
| `findStart()` / `findNext()` | 返回 `0` / 无操作 |
| `sniffedResources` / `downloadRequests` / `userscriptDetected` … | 全部为空流 |
| `clearCookies()` / `clearCache()` | 无害 no-op |
| `capabilities` | 空集合：界面不会显示"网页加载 / 脚本执行"等标签 |

「内核管理」与设置页会为 `type: engine_adapter` 的包显示琥珀色提示，例如
「引擎适配包：只探测本机引擎运行时，不提供网页渲染」，避免用户误以为切过去
就能上网。

## 要做真正的 Gecko 内核需要什么

Gecko 目前**没有**可供第三方离屏嵌入渲染的发行版：Mozilla 只发行 Firefox 应用
与 GeckoView（Android 上编译进宿主 APK 的组件），两者都不提供"把渲染结果交给
宿主 Flutter 视图"的接口。所以一个 `.zbk` 现阶段**不可能**实现 Gecko 渲染：

- **桌面端**：需要 Mozilla 提供可离屏渲染的 Gecko 发行版（并解决窗口/合成器
  嵌入、进程模型、协议桥接），目前不存在。
- **Android**：需要宿主 APK 集成 GeckoView（AAR），由宿主内核实现渲染与
  `GeckoSession` 生命周期——这属于宿主侧工程，无法通过内核包下发。
- **现在就想上网**：在内核管理里切回系统内核（Windows WebView2 / Linux
  WebKitGTK / Android System WebView），或安装携带 FFI 原生库、WebView2 固定
  版本运行时的内核包。

如果将来出现了可嵌入的 Gecko 发行版，本类型的适配器内核就是它的接入点：
新增一个 `type: engine_adapter` 的实现（或升级为携带产物的 `ffi` 包），
在 `KernelRegistry.createKernel()` 里替换掉当前的探测内核即可。
