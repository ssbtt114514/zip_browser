# Zip Browser v0.7.1 —— 多平台发布版

插件化多平台浏览器框架：浏览器内核可以系统内置（Android System WebView / Windows WebView2），也可以用 **.zip / .zbk 内核插件**替换。支持插件化扩展（主题、广告拦截、内核、页面能力等）。

## 本次更新：多平台发布矩阵

- **Android**：按 CPU 架构拆分发布 —— `arm64-v8a` / `armeabi-v7a` / `x86_64` 三个小体积安装包 + `universal` 通用包（单包兼容所有设备）
- **Windows**：x64 免安装压缩包 + **Inno Setup 安装版**（`zip-browser-windows-x64-setup.exe`，桌面快捷方式/卸载入口齐全）
- **Linux**：`amd64(x64)` 与 **`arm64(aarch64)`** 双架构 —— 免安装 tar.gz + **`.deb` 安装包**（apt 可装，自动处理 GTK 依赖）
- **浏览器内核包按平台拆分**：`zb_lite_kernel` / `zb_gecko_kernel` 各拆出 windows / linux / android 单平台 `.zbk`；`zb_chromium_kernel` 拆出 linux / android（Windows 用含 WebView2 固定版本运行时的完整包）。按需下载，体积更小

## 功能（前几轮已落地）

- Firefox 风格 UI：底部导航、圆角地址栏、图标化工具栏
- 剪贴板链接识别：复制链接后自动提示打开
- 二维码扫描：工具栏入口，扫码后直接访问
- 莫奈（Monet）动态取色：跟随壁纸自动生成主题色
- 资源嗅探 + 资源预览（图片/视频/音频）
- 阅读模式、桌面模式（自定义 UA/视口/DPR）
- 双内核：`zb_lite_kernel`（软件渲染）与 `zb_gecko_kernel` / `zb_chromium_kernel`（FFI 渲染）
- Material / Cupertino 双风格一键切换
- 设置页：搜索引擎、新标签页、JavaScript 开关、白名单插件、内核管理等

## 安装

| 平台 | 包 | 说明 |
|---|---|---|
| Android | `zip-browser-android-*.apk` | 按芯片选架构包，或直接装 universal |
| Windows | `zip-browser-windows-x64-setup.exe` / `*.zip` | 推荐安装版 |
| Linux x64 | `zip-browser-linux-amd64.deb` / `*.tar.gz` | `sudo apt install ./zip-browser-linux-amd64.deb` |
| Linux arm64 | `zip-browser-linux-arm64.deb` / `*.tar.gz` | aarch64（如树莓派 64 位系统） |
| 内核包 | `*.zbk` | 设置 → 浏览器内核 → 内核管理 → 安装独立内核包 |

## 文档

- 使用手册：应用内「设置 → 使用手册」或仓库 `docs/`
- 插件开发：`docs/PLUGIN_KERNEL_GUIDE.md`（内核插件规范）、`docs/PLUGIN_GUIDE.md`（普通插件规范）
- 作者主页：https://ssbtt114514.github.io
