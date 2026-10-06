# Gecko 内核适配包（zb_gecko_kernel）

内核 id：`com.zipbrowser.kernel.gecko`　类型：`engine_adapter`（引擎适配包）
引擎：`gecko`　版本：`1.0.0`

## 这个包做什么

- 在应用内「内核管理」里作为一个可选内核出现，选中后标签页显示**探测报告**：
  本机是否存在 Gecko 运行时文件、命中了哪条候选路径、命中方式、以及（能读到
  `platform.ini` / `application.ini` 时）Gecko 的版本号与 BuildID。
- 列出全部被探测的候选路径与命中情况（Windows / Linux / Android / macOS 各自的
  常见安装位置、`MOZ*` / `MOZILLA*` 环境变量、`PATH` 上的 `firefox`）。
- 没检测到运行时的时候，给出可照做的提示（本平台该装什么、路径在哪）。

探测到的版本号来自 Gecko 自带的 `platform.ini` / `application.ini`；读不到就是
`未读取到（不编造版本号）`，不会凭清单里的 `version` 冒充引擎版本。

## 这个包不做什么

- **不渲染网页，也不加载 Gecko。** 它不包含 `libraries`，也不包含 `runtime_dir`，
  包里没有一行 Gecko 代码。即使探测到了 `xul.dll` / `libxul.so`，它也不会去
  `dlopen` / `LoadLibrary` 那个文件。
- 不声明任何能力（`capabilities: []`），所以「内核管理」里它不会显示"网页加载 /
  脚本执行"之类的标签。
- `loadUrl` 不会假装成功：它只记录请求地址、发出一条 `blocked` 导航事件，页面区域
  显示"最近一次请求地址（未加载）"。既不会有假的加载动画，也不会把没加载的地址
  写进历史记录。
- `evaluateJavascript` 返回空串，页面内查找返回 0，嗅探 / 下载 / 用户脚本事件流为空。

## 怎样才能真正渲染网页

Gecko 目前**没有**任何可供第三方离屏嵌入渲染的发行版：Mozilla 只发行 Firefox 应用
与 GeckoView（Android 上编译进宿主 APK 的组件），都不提供"把渲染结果交给宿主
Flutter 视图"的接口。因此：

- **现在就想上网**：在「内核管理」里切回系统内核（Windows WebView2 / Linux
  WebKitGTK / Android System WebView），或安装携带 FFI 原生库、WebView2 固定版本
  运行时的内核包。
- **Android 上真用 Gecko**：需要宿主 APK 集成 GeckoView（AAR），由宿主内核实现渲染
  ——这属于宿主侧的工程，不是一个 `.zbk` 能提供的。
- **桌面端**：需要 Mozilla 提供可离屏渲染的 Gecko 发行版；目前不存在。

## 打包

```bash
python tool/pack_kernel.py build_kernel_pkg/zb_gecko_kernel
```

产物为 `zb_gecko_kernel.zbk`，安装方式与其它内核包一致（「内核管理 → 安装」）。
清单字段与语义见 [`docs/KERNEL_ADAPTER.md`](../../docs/KERNEL_ADAPTER.md)。
