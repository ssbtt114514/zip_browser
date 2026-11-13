# User Instruction Memory

This file records user instructions, preferences, and teachings for reference in future interactions.

## Format

### User Instruction Entry
User instruction entries should follow this format:

[User Instruction Summary]
- Date: [YYYY-MM-DD]
- Context: [Mentioned scenario or time]
- Instructions:
  - [Content of user teaching or instruction, described line by line]

### Project Knowledge Entry
Entries discovered by the Agent during task execution should follow this format:

[Project Knowledge Summary]
- Date: [YYYY-MM-DD]
- Context: Discovered by Agent while performing [specific task description]
- Category: [Operations & Deployment|Build Methods|Testing Methods|Troubleshooting & Debugging|Workflow & Collaboration|Environment Configuration]
- Instructions:
  - [Specific knowledge points, described line by line]

## Deduplication Strategy
- Before adding a new entry, check for similar or identical instructions.
- If a duplicate is found, skip the new entry or merge it with the existing one.
- When merging, update the context or date information.
- This helps avoid redundant entries and keeps the memory file tidy.

## Entries

[Project Knowledge Summary]
- Date: 2026-11-08
- Context: Agent 执行 v0.12.0 功能批次时摸清的验证与构建流程
- Category: Build Methods
- Instructions:
  - 本环境无 Flutter/Dart 工具链：`flutter analyze / test` 无法本地执行，只能靠 CI；本地验证用 `python3 tool/verify_all.py`（内核 gcc 编译 + 自检 + 清单 + YAML 校验；Flutter 项自动 SKIP，可用 FLUTTER_BIN 指定）。
  - android/、windows/ 等平台目录不入库（.gitignore），全新克隆后必须先跑 `tool/init_project.sh`（内部幂等执行 patch_android_gradle.py / patch_android_manifest.py / make_app_icon.py / enable_native_surface.py）。
  - patch_android_gradle.py 负责三项：compileSdk 36 钉定、app minSdk 21 钉定、ML Kit 中文识别原生库（text-recognition-chinese）注入 app gradle。

[Project Knowledge Summary]
- Date: 2026-11-08
- Context: 修复「Windows 三风味安装器全部按 full 打包」问题时发现的坑
- Category: Troubleshooting & Debugging
- Instructions:
  - Windows 安装器风味由 CI 传给 ISCC 的 `/DFlavor=` 控制，与 `.tooling/installer.iss` 的 `#ifndef Flavor` 必须同名；历史上因写成 `/DFavor=` 导致 single/none 安装器共用 full 的 AppId 与输出名、互相覆盖。改 installer.iss 或工作流时两端拼写要同步核对。
  - 安装器修复「安装后无法运行」的固定套路：安装时静默装 VC++ redist + WebView2 常青版引导器（tool/fetch_installer_prereqs.py 下载到 build/installer-prereqs，严禁放进 Release 目录）；Release 内 app-local 捆绑 vcruntime140 / msvcp140 / WebView2Loader.dll。
  - webview_windows 0.4.0 的 WebviewController 没有 captureScreenshot API（勿凭记忆使用）；改 Windows 内核能力前先查 pub.dev 文档。

[Project Knowledge Summary]
- Date: 2026-11-08
- Context: 版本发布与文档沉淀流程
- Category: Workflow & Collaboration
- Instructions:
  - Release 说明人工撰写在 `.tooling/release_notes_v*.md`（按版本号命名）；CI 的 gh-release 刻意不开 generate_release_notes，避免覆盖人工说明。
  - 版本号三处同步：pubspec.yaml `version: X.Y.Z+N`、lib/core/constants.dart `appVersion`、新增 `.tooling/release_notes_v*.md`。
  - 需求/设计规格沉淀在 `.monkeycode/specs/<日期-主题>/requirements.md + design.md`。

[Project Knowledge Summary]
- Date: 2026-11-11
- Context: v0.12.3 发布期间排查 aarch64 构建与内核包挂 Release 的坑
- Category: Troubleshooting & Debugging
- Instructions:
  - aarch64 Linux 运行器上 snap 源（api.snapcraft.io）频繁超时/重置，Flutter 在 aarch64 的安装方式已改为 git clone 对应版本 tag + 首次运行下载产物（官方 releases_linux.json 只有 x64 SDK 包，flutter-action 在 arm64 也解析不了固定版本）。
  - `rerun-failed-jobs` 复用触发运行时那次提交的工作流文件：如果失败原因是工作流本身的修改（如权限、步骤），必须重打 tag 或推新提交重新触发，重跑旧 run 无效。
  - 工作流挂 Release（softprops/action-gh-release）必须显式声明 `permissions: contents: write`，缺省会报 "Resource not accessible by integration"。
  - Flutter 3.32 / 3.47 均不产出 32 位 x86 APK：Android 应用包按三 ABI（arm64-v8a / armeabi-v7a / x86_64）收集与校验；内核 .zbk 仍含四 ABI 库。
  - Android 内核库统一按 NDK API 21（android21 三元组）编译，与 minSdk 21 对齐，保证 Gecko 风味在 Android 5.0+ 可加载；改 NDK_TRIPLES 时同步 docs/KERNEL_ABI.md 的示例。

[Project Knowledge Summary]
- Date: 2026-11-12
- Context: v0.13.0 发布前排查三平台构建同时失败
- Category: Troubleshooting & Debugging
- Instructions:
  - build-android-apk / build-linux / build-windows 的 analyze 与测试是各工作流前置 job：任一 `flutter test` 失败会让三个平台同时红，先看 analyze/test 日志再怀疑平台编译。
  - 本地无 Flutter 时可用 `/tmp/opencode/dart_lex.py` 做词法层自检，但类型提升（跨无继承关系接口，如 `BrowserKernel` → `DebugLogSource`）必须显式 `as`，词法检查发现不了，需在 CI analyze 才暴露。

[Project Knowledge Summary]
- Date: 2026-11-13
- Context: 用户反馈 Android 5 未真正适配，排查构建链与运行兼容性
- Category: Build Methods
- Instructions:
  - Android 包必须用 Flutter 3.32.8 构建（最后一个官方支持 API 21 的稳定版）；3.35 起官方最低 Android API 抬升，3.47 模板 minSdk 为 24，3.50 支持矩阵 24–37。仅写 minSdk=21 只能安装，引擎在 Android 5 上会崩溃/黑屏。
  - Android 构建链与 3.32.8 配套：AGP 8.9.2 + Gradle 8.12.1（Tencent 镜像）+ Kotlin 2.1.20 + JDK 17；Flutter 3.32 的 Gradle 插件不会自动应用 Kotlin 插件，app/build.gradle.kts 必须显式声明 `org.jetbrains.kotlin.android`。compileSdk 36 需 `android.suppressUnsupportedCompileSdk=36`。
  - `webview_flutter_android` 在 3.32 下解析 4.10.1；4.10.2 起要求 Flutter 3.35 并移除 SDK < 24 兼容代码，不能升。`google_mlkit_text_recognition` 约束写 `>=0.16.0 <0.18.0` 才能同时供 3.32（0.16.0）与 3.47（0.17.x）两条链解析。
  - 面向 Android 5 的注入脚本一律 ES5（var/function），禁用可选链、空值合并、allSettled 等新语法；Lollipop 系统 WebView 停在 Chrome 74 左右。
