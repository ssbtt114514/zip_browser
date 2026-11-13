# v0.13.1

> 真正适配 Android 5.0（API 21）：Android 包改用最后一个官方支持 API 21 的
> Flutter 3.32.8 构建，并同步降级 Android 构建链；其余平台不受影响。

## 修复

- **Android 5 启动问题**：此前用 Flutter 3.47.6 构建。3.35 起 Flutter
  官方最低 Android API 已抬升（3.47 模板 minSdk 为 24，3.50 支持矩阵为
  24–37），minSdk 写成 21 只是「能安装」，引擎与渲染器在 Lollipop 上属于
  未支持组合，会出现启动崩溃 / 黑屏。
  - Android 工作流固定 `flutter-version: 3.32.8`（3.32.x 是最后一个官方
    支持 API 21 的稳定版），Windows / Linux 仍用 3.47.6。
  - Android 构建链同步降级为 AGP 8.9.2 + Gradle 8.12.1 + Kotlin 2.1.20
    （保留 JDK 17 与 compileSdk 36，targetSdk 显式固定 36）。
  - `google_mlkit_text_recognition` 约束放宽为 `>=0.16.0 <0.18.0`：
    Android 链解析 0.16.0，桌面链解析 0.17.x。
- **依赖版本随构建链回落**：Android 包解析到 `webview_flutter` 4.13.1 /
  `webview_flutter_android` 4.10.1（4.10.2 起要求 Flutter 3.35 并删除
  SDK < 24 的兼容代码），其虚拟显示 / 混合合成路径在 API 21 可用。

## 兼容性核对

- 注入脚本（调试钩子、网页字体、预连接、标签休眠快照）均为 ES5 语法，
  兼容 Lollipop 停留在 Chrome 74 左右的系统 WebView。
- 原生插件只用 API 21 已有的 `SurfaceTexture` / `Surface` /
  `FileProvider` 接口，无新增版本门槛。
- 三 ABI（arm64-v8a / armeabi-v7a / x86_64）保持可用，结论与细节见
  `docs/ANDROID_COMPAT.md`。

## 说明

- 版本号 0.13.1+22。
- Windows / Linux 包的内容与 0.13.0 一致，仅随版本号重新发布。
