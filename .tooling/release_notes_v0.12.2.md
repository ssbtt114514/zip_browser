# v0.12.2

> 修复按平台打包内核包时被跨平台清单拦截的问题，并让打包器在 Windows
> 控制台以 UTF-8 输出，避免中文提示触发编码异常。

> v0.12.0 的安装包构建因静态检查与安装器参数问题失败，v0.12.1 完成修复，
> v0.12.2 补齐内核包按平台拆分。以下为 v0.12.0 起包含的全部变更。

## 破坏性变更

- **移除 zip 功能插件接口**：插件管理页、工具栏扩展按钮、受信任插件白名单
  开关全部下线，历史插件不再加载。
- **内核安装入口下线**：内核改为随安装包内置，应用内不再提供「安装 .zbk /
  切换内核」菜单；已安装的历史内核包仍会在设置页列出。
- **构建风味改为三档**：`ZIP_FLAVOR=none|chromium|gecko`（默认 `chromium`）。
  `full` / `single` 已废弃，`none` 使用占位内核不加载网页，`gecko` 随包
  内置 `assets/bundled/kernel.zbk` 并首次启动自动安装选中。

## 修复

- **带端口地址识别**：`localhost:8080` / `example.com:8080/x` 被 scheme
  正则误判成未知协议，`isLikelyUrl` 直接返回 false；现在与 `toUrl` 共用
  「scheme 后必须跟 //」的判定，带端口地址恢复正常。
- **内核选择被风味限制**：Chromium 风味此前忽略已安装内核的选择，
  导致内核包选中后仍走系统 WebView；现在三种网页风味都优先使用选中的
  内核包，未选择时才回落系统内核。
- **CI 静态检查失败**：首页内置 JS 正则中的 `$/` 在 Dart 模板串里未转义，
  触发 `missing_identifier`；OCR 服务多余 `await` 触发 `await_only_futures`。
  两处已修复，`flutter analyze` 恢复通过。
- **Windows 安装器（安装后无法运行系列）**：
  - 修复 CI 向 ISCC 传 `/DFavor=` 而脚本读取 `#ifndef Flavor` 的拼写错位：
    此前三种风味的安装器全部按同一风味打包，AppId 相同、输出文件同名互相
    覆盖。现在各风味拥有独立 AppId、独立安装目录与正确命名。
  - 沿用旧版运行时保障：安装时静默装 VC++ 运行库与 WebView2 常青版，
    Release 目录 app-local 捆绑 VCRUNTIME140 / WebView2Loader.dll。

## 新增

- **内核三风味随包内置**：Android / Windows / Linux 均产出 none / chromium /
  gecko 三个安装包；gecko 风味在 CI 侧编译内核并打包为 `.zbk` 内置，
  首次启动由 `seedBundledKernel()` 安装并选中，失败静默回落系统内核。
- **x86 架构补齐**：Android 内核库改为四 ABI（arm64-v8a / armeabi-v7a /
  x86 / x86_64）；Android APK 同时产出 x86。Linux 提供 x64 与 arm64；
  Windows 应用包固定 x64（Flutter 的 windows 构建不支持 `--target-platform`，
  x64 主机无法产出 arm64 应用包）。
- **内核 DLL 交叉编译**：build-kernel 用 MSVC 编译 Windows arm64 内核并校验
  16 个 ABI 导出符号，保证内核库覆盖 ARM64。
- **文字识别（OCR）**：菜单「工具 → 文字识别（图片取字）」，选图取字、
  可一键复制。Android 内置 ML Kit 离线识别（中文脚本，图片不上传）；
  Windows / Linux 走「设置 → AI 解读」配置的多模态接口。
- **AI 视觉取字**：AiService 新增多模态消息支持（image_url + base64），
  OCR 与后续图片理解共用该通道。
- **二级菜单**：桌面主菜单重构为「标签页 / 页面 / 数据 / 显示 / 工具 / 系统」
  六组二级菜单（MenuAnchor + SubmenuButton），开关项带勾选状态，
  快捷键提示保留；窄屏底部面板沿用扁平分组。

## 变更

- Android minSdk 钉死 21（Flutter 引擎下限），Android 4.0–4.4 的支持尝试
  结论与原因见 docs/ANDROID_COMPAT.md。
- 开发者工具箱「插件系统」行改为「已移除（v0.12.0）」，「内核安装」行改为
  「已移除（内核随安装包内置）」；使用手册同步更新。
