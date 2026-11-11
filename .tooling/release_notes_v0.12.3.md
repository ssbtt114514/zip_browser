# v0.12.3

> Gecko 内核库改按 NDK API 21（Android 5.0）编译，Android 5/6 设备可以
> 正常加载随包内置的 Gecko 内核；同时修正 Android APK 架构口径。

## 修复

- **Gecko 内核在 Android 5/6 上无法加载**：内核库此前按 `android24`
  （Android 7.0）的 NDK 三元组编译，Android 5/6 设备的 bionic 缺少新版
  符号，加载随包内置的 Gecko 内核可能失败。现在统一按
  `android21`（Android 5.0，与 app minSdk 对齐）编译全部四个 ABI 的内核库，
  Gecko 风味在 Android 5.0+ 完整可用。
- **Android APK 架构口径**：Flutter 3.47 已不再产出 32 位 x86 APK，
  v0.12.2 收集步骤因缺少该文件失败；现按实际支持的三 ABI
  （arm64-v8a / armeabi-v7a / x86_64）产出与校验，universal 包断言同步修正。

## 变更

- 内核包 `.zbk` 仍包含四 ABI 库（含 x86），应用包按三 ABI 分发；内核文档
  （KERNEL_ABI）的交叉编译示例同步改为 API 21。
- build-kernel 工作流在打 `v*` tag 时把 `.zbk` 内核包挂到 Release，
  供需要单独下载 / 替换内核的场景使用。

> v0.12.0 起的完整变更列表见 v0.12.2 的 Release 说明。
