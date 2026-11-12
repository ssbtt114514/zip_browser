# 设计：UI 风格、网页体验与 Windows 平台能力

## 1. 现状

- 主题：`ThemeEngine` 生成 ThemeData（`useMaterial3: true`）；配色来源
  `ZbMonetEngine`（material_color_utilities HCT 调色板）。
- 系统取色：`DynamicColorPlugin.getCorePalette()` 仅 Android 12+ 可用，
  其他平台返回 null → 回退内置引擎。
- Windows 原生：`native_plugins/zb_native_surface/windows` 已注册
  MethodChannel `zip_browser/native_surface`，由 `tool/enable_native_surface.py`
  注入 runner。
- WebView：Windows 走 `webview_windows` 0.4.0。

## 2. Windows 莫奈取色

### 2.1 原生侧（C++，扩展现有 channel）

新增方法 `readSystemTheme`，返回 EncodableMap：

| 键 | 类型 | 说明 |
|---|---|---|
| `accentColor` | int | 0xAARRGGBB，来自 `DwmGetColorizationColor`（ABGR 转 RGB） |
| `darkMode` | bool | 注册表 `HKCU\...\Themes\Personalize\AppsUseLightTheme` |
| `wallpaperPath` | string | `SystemParametersInfoW(SPI_GETDESKWALLPAPER)`；为空时回退 `%APPDATA%\Microsoft\Windows\Themes\TranscodedWallpaper` |

依赖：`dwmapi` 由 Flutter runner 默认链接；`advapi32` 通过
`#pragma comment(lib, "advapi32.lib")` 引入，不改 CMake。
任一步失败返回 null 字段，Dart 侧降级。

### 2.2 Dart 侧

- `lib/platform/windows_system_theme.dart`：读取并解析，非 Windows 返回 null。
- `lib/services/wallpaper_color.dart`：`instantiateImageCodec` 解码壁纸
  （目标宽 64px），RGBA 直方图取主色；纯函数 `dominantColorFromRgba`
  便于单测。策略：跳过接近灰/黑的像素，按色相 24 桶投票，返回桶内均值。
- `lib/platform/windows_theme_bootstrap.dart`：启动时按 `MonetSource` 计算
  种子（system → 强调色；wallpaper → 壁纸主色，失败回退强调色），写入
  `AppearanceSettings.systemSeedOverride`（运行期，不持久化）。

### 2.3 主题合成顺序

```
莫奈关闭                     → ColorScheme.fromSeed(手动种子色)
莫奈开 + system + 系统色板可用 → 系统色板（Android 12+）
莫奈开 + system/wallpaper + override 非空 → 内置引擎(override)
莫奈开 + 其他                → 内置引擎(手动种子色)
```

## 3. Windows 开发者工具（关键约束）

WebView2 只提供 `OpenDevToolsWindow()`（独立窗口），**没有**把 Edge
DevTools 嵌入第三方窗口的官方能力。完整嵌入式 DevTools 需要拉起
DevTools 前端 + CDP WebSocket，离线场景不可行。

因此采用两层方案：

1. **内置面板**（应用内，跨页面统一）：
   - 控制台：注入脚本 hook `console.*` / `window.onerror`，经 JsBridge 回传；
   - 执行 JS：调用内核 `evaluateJs`，回显结果；
   - 页面信息：URL/标题/UA/视口；
   - 网络：hook `fetch` / `XMLHttpRequest`，记录方法与 URL、耗时；
   - 一键「打开原生 DevTools 窗口」按钮（Windows）。
2. **原生窗口**：`WebviewController.openDevTools()`（webview_windows 0.4.0）。

入口：菜单「工具 → 开发者工具」+ F12（Windows 生效），默认需在设置中
开启「允许开发者工具」。

## 4. 网页访问 / 字体 / 内存

- 网页访问：预连接（DNS 预取）、首屏资源优先级提示、按需注入拦截脚本，
  全部收敛到 `WebViewTuningService` 并可整体开关。
- 字体：设置页明确区分「界面字体」（`ThemeData.fontFamily`）与
  「网页字体」（注入 CSS `font-family`），后者可选。
- 内存：后台标签超过阈值后调用内核 `suspend()`（Android `pauseTimers`、
  Windows 释放渲染进程可选）；保留 URL 与表单快照，恢复时重新加载。

## 5. 风险

| 风险 | 处置 |
|---|---|
| Windows 强调色取色格式差异 | 只取低 24 位，异常值回退手动种子色 |
| 壁纸为幻灯片/纯色 | 回退 TranscodedWallpaper，再失败回退强调色 |
| DevTools 嵌入期望无法完全满足 | 面板提供核心能力 + 原生窗口按钮，文档说明 |
| 内存优化导致状态丢失 | 快照 + 恢复，提供全局开关 |
