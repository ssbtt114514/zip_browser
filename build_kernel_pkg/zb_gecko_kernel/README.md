# Gecko 渲染内核包（zb_gecko_kernel）

内核 id：`com.zipbrowser.kernel.gecko`　类型：`ffi`（跨平台软件渲染内核）
引擎：`gecko`　版本：`1.0.0`

## 这个包做什么

- 在应用内「内核管理」安装后，可作为 Gecko 引擎内核选用，**Windows / Linux /
  Android 三平台都能加载、切换、显示画面**。
- 渲染实现与 `zb_lite_kernel` 完全同源（HTML 解析 → 排版 → 内置 8x16 点阵字库
  光栅化 → RGBA8888 帧提交，经原生表面插件上屏），严格实现
  `zb_plugin_kernel_abi.h` 的 16 个导出符号；内核 id、显示名与页面底部提示
  标识为 Gecko（`zb_kernel_name -> zb_gecko_kernel`）。
- 能力声明完整：`loadUrl` / `evaluateJs` / `userScripts` / `multiTab` / `download`，
  与 lite / example 内核一致。

## 平台产物

| 平台 | 库 |
|---|---|
| Windows x64 | `bin/windows/zb_gecko_kernel.dll` |
| Linux x64 | `bin/linux/libzb_gecko_kernel.so` |
| Android arm64-v8a | `bin/android/arm64-v8a/libzb_gecko_kernel.so` |
| Android armeabi-v7a | `bin/android/armeabi-v7a/libzb_gecko_kernel.so` |
| Android x86_64 | `bin/android/x86_64/libzb_gecko_kernel.so` |

## 与"真 Gecko"的关系（如实说明）

Gecko 目前没有可供第三方离屏嵌入渲染的发行版：Mozilla 只发行 Firefox 应用与
GeckoView（Android 上编译进宿主 APK 的组件），都不提供"把渲染结果交给宿主
Flutter 视图"的接口。因此：

- 本包是 **Gecko 引擎标识**的 FFI 渲染内核：内核包链路（安装 → 探测 → 切换 →
  渲染 → 卸载）完全真实可用，渲染画面真实上屏，但底层是轻量软件光栅化，
  不是 Mozilla 的 Gecko 排版/JS 引擎；
- 想探测系统里是否已有真实 Gecko 运行时，可另装 `zb_gecko_adapter`（`engine_adapter`
  类型，见 `docs/KERNEL_ADAPTER.md`）；
- **Android 上真用 GeckoView**：需要宿主 APK 集成 GeckoView（AAR），由宿主内核实现
  渲染——这属于宿主侧工程，不是一个 `.zbk` 能提供的；**桌面端**需要 Mozilla
  提供可离屏渲染的 Gecko 发行版，目前不存在。

## 构建与打包

```bash
# 1) 编译三平台内核库并归位到 bin/
python tool/build_engine_kernels.py --platform all

# 2) 打包 .zbk
python tool/pack_kernel.py build_kernel_pkg/zb_gecko_kernel zb_gecko_kernel.zbk
```

产物为 `zb_gecko_kernel.zbk`，安装方式与其它内核包一致（「内核管理 → 安装」）。

## 相关

- 同源引擎变体工程：`native_kernels/zb_engine_kernel/README.md`
- 内核 ABI 约定：`docs/KERNEL_ABI.md`
