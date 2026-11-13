# Android 平台兼容性

## 结论

| Android 版本 | API 级别 | 支持情况 |
|---|---|---|
| Android 5.0 – 5.1 | 21 – 22 | 支持（Android 包固定 Flutter 3.32.8 构建） |
| Android 6.0 – 16 | 23+ | 支持 |
| Android 4.0 – 4.4 | 14 – 19 | 不支持，且无法通过配置挽救 |

minSdk 已由 `tool/patch_android_gradle.py` 钉死为 21，防止模板默认值漂移；
三 ABI 安装包（arm64-v8a / armeabi-v7a / x86_64）任意一台 Android 5 设备都可安装。

## Android 包为什么固定 Flutter 3.32.8

Flutter 3.32.x 是最后一个官方支持 API 21 的稳定版。3.35 起官方最低 Android
API 抬升（3.47 的模板 minSdk 已是 24，3.50 的支持矩阵为 24–37，23 及以下
列为不支持）。用 3.35+ 的引擎构建时，即使把 minSdk 写成 21，安装后也属于
「未支持组合」：引擎/渲染器按新下限编译，在 Lollipop 上启动崩溃或黑屏。

因此 Android 工作流（`.github/workflows/build-android-apk.yml`）把
`flutter-version` 固定为 3.32.8，Windows / Linux 工作流继续用 3.47.6。
`pubspec.yaml` 的依赖约束同时覆盖两条链（例如
`google_mlkit_text_recognition: ">=0.16.0 <0.18.0"`，3.32 解析 0.16.0、
3.47 解析 0.17.x）。

## Android 5 的适配要点

1. **引擎与渲染器**：3.32 的 Android 默认渲染器是 Skia + OpenGL ES，
   不使用 Impeller Vulkan（后者需要更高的 API 级别）。
2. **Platform View**：`webview_flutter_android` 在 3.32 下解析到 4.10.1，
   其虚拟显示 / 混合合成路径在 API 21 可用；4.10.2 起删除 SDK < 24 的兼容
   代码并要求 Flutter 3.35，因此不能升。
3. **注入脚本**：内置的调试钩子、字体覆盖、预连接、标签休眠快照等脚本
   全部使用 ES5 语法（`var` / `function`），兼容 Lollipop 上停留在
   Chrome 74 左右的系统 WebView；不使用可选链、空值合并、`Promise.allSettled`
   等新语法，避免脚本整体解析失败。
4. **原生插件**：`zb_native_surface` 只用 API 21 已有的
   `SurfaceTexture` / `Surface` / `TextureRegistry`；文件选择用
   `FileProvider` + `startActivityForResult`，均无版本门槛。
5. **构建链**：AGP 8.9.2 + Gradle 8.12.1 + Kotlin 2.1.20 + JDK 17，
   compileSdk 36（AGP 8.9 只验证到 35，用
   `android.suppressUnsupportedCompileSdk=36` 屏蔽告警），targetSdk 36。
6. **网络**：Android 5 默认允许明文 HTTP（`usesCleartextTraffic` 在
   API 24 以上才参与判断），系统 WebView 支持 TLS 1.2。

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

- **Android 5.0 – 7.1**：Chromium 风味可用；系统 WebView 更新已停止
  （Lollipop 停在 Chrome 74 左右），复杂站点可能降级显示。
- **Gecko 风味（Android 5.0+）**：内核库按 NDK API 21 编译
  （`tool/build_engine_kernels.py` 的 `NDK_TRIPLES`），与 minSdk 对齐，
  随包内置的 `.zbk` 在 Android 5.0+ 首次启动即可安装使用，可绕开系统
  WebView 版本过旧的问题。
- **无内核版（ZIP_FLAVOR=none）**：同样受 Flutter 引擎 minSdk 21 约束，
  无法运行在 Android 4.x —— 该风味解决的是「分发体积 / 能力裁剪」，
  与系统版本下限无关。

## 文字识别（OCR）对系统版本的要求

- ML Kit Text Recognition v2（`google_mlkit_text_recognition`）要求
  Android API 21+，与本项目 minSdk 一致；中文脚本原生库
  `com.google.mlkit:text-recognition-chinese` 由
  `tool/patch_android_gradle.py` 注入 app gradle。
