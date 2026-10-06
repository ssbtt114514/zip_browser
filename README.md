# Zip Browser

一个使用 **Flutter** 开发、可通过 **zip 插件**扩展功能与浏览器内核的多平台浏览器框架。

- ✅ **Android**：调用系统 **Android System WebView**（不打包内核，随系统更新）
- ✅ **Windows**：使用 **WebView2**（Edge Chromium），支持系统 Evergreen 内核
  与插件携带的 Fixed Version 固定内核
- 🚧 **Linux / macOS**：架构已预留（占位内核），后续适配
- 🔌 插件为标准 **zip**：JS 扩展（DOM/脚本）、原生内核（`.dll/.so`，C ABI）、
  声明式 UI（按钮/菜单）；独立内核包为 **`.zbk`**

## 功能特性

- 多标签页、前进 / 后退 / 刷新、隐私标签、恢复关闭的标签页
- 书签、历史记录、下载管理、清除浏览数据
- **资源嗅探**：自动嗅探页面视频 / 音频 / 图片，顶部浮动提示，可手动开关
- **资源预览**：图片全屏缩放预览，视频 / 音频直接播放，一键下载
- **二维码扫描**：扫一扫，识别 URL 直接打开
- **阅读模式**、无图模式、多组色彩滤镜、字号 / 行距调节
- 桌面版 UA、页面内查找、长按菜单、分享
- **莫奈动态取色（Material You）**：Android 12+ 跟随壁纸生成主题，可开关
- 多搜索引擎、深色 / 浅色主题、自定义外观
- SVG 应用图标，内核与插件均可热插拔

---

## 快速开始

### 1. 初始化工程（生成 android / windows 目录）

```bash
# Windows
tool\init_project.bat

# Linux / macOS 主机
sh tool/init_project.sh
```

等价于：

```bash
flutter create --platforms=android,windows --org com.zipbrowser --project-name zip_browser .
flutter pub get
```

### 2. 运行

```bash
flutter run -d <android-device>   # Android
flutter run -d windows            # Windows（需 Windows 主机 + WebView2 Runtime）
```

### 3. 安装插件

- 菜单（右上角 ⋮）→ **插件管理** → **安装 .zip**
- 菜单 → **设置** → **浏览器内核** 可切换系统 / 插件内核（新标签页生效）

### 4. 打包示例插件

```bash
# JS 扩展示例（夜间模式）
python tool/pack_plugin.py example_plugins/dark_mode

# FFI 内核示例（需先按指南启用表面插件并编译 dll）
python tool/pack_plugin.py example_plugins/hello_ffi_kernel
```

# 独立内核包（.zbk）
python tool/pack_kernel.py build_kernel_pkg/zb_example_standalone zip_browser_kernel.zbk
```

插件内核（让 zip 里的内核显示画面）的完整步骤见
**[docs/PLUGIN_KERNEL_GUIDE.md](docs/PLUGIN_KERNEL_GUIDE.md)**。

### 5. 构建安装包 / 内核产物

Android 安装包：

```bash
flutter build apk --release   # 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 注意：`android/` 等平台目录由 `flutter create` 生成且不入库，
> 全新克隆后需先执行第 1 步初始化，再构建。

也可以在 GitHub Actions 中一键构建（推 `v*` tag 或手动触发）：

| 工作流 | 产物 |
|--------|------|
| [build-android-apk.yml](.github/workflows/build-android-apk.yml) | Android release APK |
| [build-kernel.yml](.github/workflows/build-kernel.yml) | 示例 FFI 内核：Windows `.dll` + Android（`arm64-v8a` / `armeabi-v7a` / `x86_64`）`.so`，并打包为 `hello_ffi_kernel.zip` |
| [build-windows.yml](.github/workflows/build-windows.yml) | Windows release 桌面版 |

---

## 插件能做什么

| 类型 | 说明 | 示例 |
|------|------|------|
| JS 扩展 | content script 注入页面，通过 `window.zipBrowser.call` 调用标签页/存储/下载等宿主 API | 夜间模式、去广告、翻译、脚本增强 |
| 原生内核 | zip 携带 `.dll/.so`，遵循统一 C ABI，可替换渲染内核 | 固定版本 Chromium、自研内核 |
| UI 扩展 | 工具栏按钮、菜单项、popup 页面 | 扩展入口、工具弹窗 |

插件权限（`tabs` / `storage` / `downloads` / `kernel` …）在 manifest 中声明，
宿主按权限做 bridge 白名单；安装包做 SHA-256 指纹与目录防篡改校验。

> 说明：Flutter release（AOT）模式不能运行时动态加载 Dart 代码，
> 因此插件采用 JS + 原生库 + 声明式 UI 的组合，详见架构文档。

---

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：分层架构、内核抽象、
  插件格式、bridge 与安全模型
- [docs/PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md)：功能插件开发（结构、
  `plugin.json`、`window.zipBrowser` JS API、用户脚本、打包）
- [docs/KERNEL_PACK.md](docs/KERNEL_PACK.md)：独立内核包 `.zbk` 制作
- [docs/KERNEL_ABI.md](docs/KERNEL_ABI.md)：原生内核 FFI C ABI（16 个导出符号）
- [docs/PLUGIN_KERNEL_GUIDE.md](docs/PLUGIN_KERNEL_GUIDE.md)：
  原生表面插件、FFI / Fixed Version 内核集成

## 目录

```text
lib/core/       内核抽象 / 插件系统 / JS bridge / 标签页
lib/platform/   Android / Windows / FFI / 占位 内核实现
lib/ui/         浏览器界面
native_plugins/ 插件内核所需的原生表面（纹理）
example_plugins/ 示例插件
tool/           初始化 / 打包 / 集成脚本
```
