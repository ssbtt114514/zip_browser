# 技术设计：v0.12.0 平台修复 / OCR / 二级菜单 / 插件接口移除

日期：2026-11-08
关联需求：requirements.md

## 1. 架构影响面

| 模块 | 变更 |
|---|---|
| `.github/workflows/build-windows.yml` | ISCC 参数 `/DFavor=` → `/DFlavor=` |
| `lib/ui/widgets/main_toolbar.dart` | 桌面主菜单重写为 MenuAnchor 二级菜单；移除插件入口；接入 OCR |
| `lib/ui/pages/plugins_page.dart` | 重写为占位说明页（解除 PluginManager 依赖） |
| `lib/ui/pages/settings_page.dart` | 移除「仅允许受信任白名单插件」开关 |
| `lib/ui/pages/devtools_page.dart` | 「插件系统」行 →「已移除（v0.12.0）」 |
| `lib/ui/pages/manual_page.dart` | 手册移除插件章节，新增智能工具章节 |
| `lib/core/build_flavor.dart` | 删除 `pluginSystemEnabled` / `userscriptsEnabled`；注释更新 |
| `lib/services/ocr_service.dart`（新） | OCR 门面：Android ML Kit / 其他平台 AI 视觉 |
| `lib/ui/pages/ocr_page.dart`（新） | 选图 → 识别 → 可复制结果 |
| `lib/services/ai_service.dart` | 新增 `ocrImage`（多模态 chat/completions） |
| `lib/core/constants.dart` + `pubspec.yaml` | 0.12.0+17；新增 google_mlkit_text_recognition ^0.17.0 |
| `tool/patch_android_gradle.py` | 新增 minSdk 21 钉定 + ML Kit 中文识别原生库注入 |
| 文档 | README、docs/ANDROID_COMPAT.md（新）、.tooling/release_notes_v0.12.0.md（新） |

## 2. 关键设计决策

### 2.1 OCR 引擎选型
- **Android**：ML Kit Text Recognition v2 中文脚本（`TextRecognitionScript.chinese`），
  离线、图片不出设备。插件只带 API，各脚本原生库需 app gradle 自行引入
  （pub.dev README 要求），由 patch 脚本注入
  `com.google.mlkit:text-recognition-chinese:16.0.1`。识别失败时回落拉丁脚本。
- **Windows / Linux**：webview_windows 0.4.0 无截图 API（已核实 pub.dev 文档），
  页面级截图取字不可行；WinRT OCR 的纯 Dart interop 复杂度高且无包依赖基础。
  采用用户配置的 OpenAI 兼容多模态接口（`image_url` + base64 data URL），
  与既有 AI 解读共用配置。模型不支持视觉时如实展示接口错误。
- 能力边界在 `OcrService` 文档注释与 OCR 页内明示（项目「诚实能力边界」惯例）。

### 2.2 二级菜单实现
- Flutter `PopupMenuButton` 原生无嵌套子菜单能力；Material 3 的
  `MenuAnchor` + `SubmenuButton`（Flutter 3.7+，项目要求 ≥3.22）提供原生
  嵌套菜单与键盘导航。开关项用 `MenuItemButton` + 自绘勾选图标
  （`MenuItemCheckbox` 状态管理受限，自绘可控且无 API 风险）。
- 动作处理保持单一入口 `handleMainMenuAction`，桌面 / 底部面板共用，
  避免双份 switch 漂移。

### 2.3 插件接口移除的范围界定
- **移除**：全部 UI 入口与插件安装路径（页面、菜单、工具栏按钮、设置开关）。
- **保留**：`core/plugin/*`（FFI 内核加载器、PluginManager）、
  `example_plugins/*`、打包工具与 `plugin_flow_test.dart`——独立内核包加载
  （`kernel_registry`）与 `ffi_kernel_integration_test.dart`（真实 DLL 加载）
  依赖该机制；这是「单内核」能力的实现载体。
- `PluginsPage` 因文件删除策略限制改为占位页，可安全手删。

### 2.4 Android 兼容性结论
三条硬边界（Flutter 引擎 minSdk 21 / KitKat WebView 停更于 Chromium 33/37 /
依赖生态无 API 19 变体）叠加后 Android 4.x 不可行，文档化而非硬降级。
详见 docs/ANDROID_COMPAT.md。

## 3. 风险与缓解

| 风险 | 缓解 |
|---|---|
| ML Kit ^0.17.0 与现有依赖约束冲突 | CI `flutter pub get` 即会暴露；版本查询自 pub.dev（0.17.0 现行） |
| MenuAnchor 行为差异（旧 Flutter） | pubspec 已要求 ≥3.22，MenuAnchor 自 3.7 可用 |
| 新增依赖增大 APK（中文识别原生库约 4MB/ABI） | 仅 Android 平台受影响；README/发布说明注明 |
| 三风味安装器此前同 AppId 叠装冲突 | 风味 AppId 已在 installer.iss 区分，本次修正传参使其实际生效 |
