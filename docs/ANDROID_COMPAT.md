# Android 平台兼容性

## 结论

| Android 版本 | API 级别 | 支持情况 |
|---|---|---|
| Android 5.0 – 16 | 21+ | 支持（minSdk = 21） |
| Android 4.0 – 4.4 | 14 – 19 | 不支持，且无法通过配置挽救 |

minSdk 已由 `tool/patch_android_gradle.py` 钉死为 21，防止模板默认值漂移。

## 为什么 Android 4 / 4.4 无法支持（尝试记录）

按「尝试支持 Android 4 / 4.4」的要求逐项排查过，三条硬边界叠加后结论是不可行：

1. **Flutter 引擎边界**：Flutter 3.22 起引擎二进制要求 minSdk 21（Android 5.0）。
   降到 19/20 可以通过 gradle 配置，但应用在 API < 21 的设备上启动即崩溃
   （引擎的 `libflutter.so` 使用了仅 5.0+ 提供的 NDK 符号）。回退到
   Flutter 2.x（支持 API 16）则整个依赖栈（webview_flutter 4.x、
   dynamic_color、file_picker 8.x、google_mlkit_text_recognition 等）
   全部不兼容，等于重写项目。
2. **系统 WebView 边界**：Android 4.4 的系统 WebView 停留在 Chromium 33/37
   时代（Google 自 2018 年起不再为 KitKat 更新 WebView），缺少 TLS 1.2+
   默认启用、ESNI/HTTP2、现代 ES 引擎。即使宿主跑起来，绝大多数现代网站
   也无法正常渲染，作为浏览器没有实用价值。
3. **插件生态边界**：本项目依赖的 AndroidX 系列要求 compileSdk 33+ 且
   minSdk 21 起步（部分如 ML Kit 中文识别为 21+），无 API 19 变体。

## 老设备可用的替代路线

- **Android 5.0 – 7.1**：Chromium 风味可用；系统 WebView 由 Chrome 更新到 2021 前后
  的版本，多数网站可正常浏览。
- **Gecko 风味（Android 5.0+）**：内核库按 NDK API 21 编译
  （`tool/build_engine_kernels.py` 的 `NDK_TRIPLES`），与 minSdk 对齐，
  随包内置的 `.zbk` 在 Android 5.0+ 首次启动即可安装使用。
- **无内核版（ZIP_FLAVOR=none）**：同样受 Flutter 引擎 minSdk 21 约束，
  无法运行在 Android 4.x —— 该风味解决的是「分发体积 / 能力裁剪」，
  与系统版本下限无关。

## 文字识别（OCR）对系统版本的要求

- ML Kit Text Recognition v2（`google_mlkit_text_recognition`）要求
  Android API 21+，与本项目 minSdk 一致；中文脚本原生库
  `com.google.mlkit:text-recognition-chinese` 由
  `tool/patch_android_gradle.py` 注入 app gradle。
