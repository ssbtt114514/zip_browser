# zb_engine_kernel —— 同源多引擎内核（Chromium / Gecko 标识）

复用 `zb_lite_kernel` 的完整软件渲染实现，通过编译宏覆盖引擎标识，
一次构建产出两个 ABI 完全相同的内核库：

| 库 | 引擎标识 | 用途 |
|---|---|---|
| `zb_chromium_kernel` | `zb_chromium_kernel` | Chromium 内核包的跨平台 FFI 渲染库（Linux/Android 降级渲染） |
| `zb_gecko_kernel` | `zb_gecko_kernel` | Gecko 内核包的跨平台 FFI 渲染库（Windows/Linux/Android） |

## 原理

- 渲染引擎（HTML 解析 → 排版 → 内置 8x16 点阵字库光栅化 → RGBA8888 帧提交）
  与 `zb_lite_kernel` 完全同源，严格实现 `zb_plugin_kernel_abi.h` 的 16 个导出符号；
- 仅 `ZB_ENGINE_NAME` / `ZB_ENGINE_DISPLAY_NAME` / `ZB_ENGINE_HINT` 三个宏不同，
  控制内核 id、显示名与页面底部提示——因此两个内核在宿主中呈现为
  "Chromium 渲染内核"与"Gecko 渲染内核"，而帧路径完全一致；
- 内核 id 通过 C ABI 的 `zb_kernel_info` 暴露，宿主据此识别。

## 构建

桌面工具链（Linux so / Windows dll）：

```bash
cmake -S native_kernels/zb_engine_kernel -B build/engine-kernel
cmake --build build/engine-kernel --config Release
```

Android 三个 ABI 与三平台一次编译、产物归位，统一走：

```bash
python tool/build_engine_kernels.py
```

脚本输出到 `build/engine-kernel-out/<platform>/`，并自动把产物复制到
`build_kernel_pkg/zb_gecko_kernel/bin/` 与 `build_kernel_pkg/zb_chromium_kernel/bin/`。

## 为什么这样设计

真正的 Chromium（CEF）与 Gecko（GeckoView/xul）嵌入库体积巨大（数百 MB）、
三平台集成成本极高，不适合随 zip 插件分发。本项目采用"引擎标识化"策略：
内核包声明 `engine: chromium / gecko`，宿主可依平台路由：
- 有系统引擎时用系统内核（Android System WebView / Windows WebView2 即 Chromium）；
- 插件携带 FFI 渲染库作为跨平台降级渲染，保证内核包在任何平台都能安装、切换、显示画面；
- 文档记录真实 CEF / GeckoView 接入路径（见 `docs/KERNEL_CHROMIUM.md` 与
  `build_kernel_pkg/zb_gecko_kernel/README.md`）。
