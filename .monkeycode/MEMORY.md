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
