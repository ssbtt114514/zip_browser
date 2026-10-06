# 独立内核包（.zbk）制作指南

`.zbk`（Zip Browser Kernel）是**独立浏览器内核包**，本质是 zip，通过
**设置 → 内核管理 → 安装内核包**载入。它只提供一个可替换的内核，
不包含网页内容脚本等功能扩展。

> 功能插件（content script / 后台 / UI）请看 [PLUGIN_GUIDE.md](PLUGIN_GUIDE.md)。
> 内核原生函数的 C ABI 请看 [KERNEL_ABI.md](KERNEL_ABI.md)。

## 与「插件携带内核」的区别

- **独立内核包 `.zbk`**：目的就是替换内核，由内核管理页安装切换。
- **功能插件中的 `kernel` 字段**：一个插件在加功能的同时附带内核，
  见 [PLUGIN_KERNEL_GUIDE.md](PLUGIN_KERNEL_GUIDE.md)。

两者原生库都遵循同一套 [KERNEL_ABI.md](KERNEL_ABI.md)，打包工具不同。

## 包结构

```
zip-browser-kernel-chromium-120.0.0.zbk
├── kernel.json                 必需：内核清单
├── bin/
│   ├── windows/kernel.dll      按平台 / ABI 存放的原生库
│   ├── linux/libkernel.so
│   └── android/arm64-v8a/libkernel.so
├── runtime/                    可选：WebView2 Fixed Version 类运行时目录
└── README.md                   可选
```

## kernel.json 字段

```json
{
  "manifest_version": 1,
  "id": "com.example.kernel.chromium",
  "name": "Chromium 独立内核",
  "display_name": "Chromium 120（独立内核包）",
  "version": "120.0.6099.1",
  "engine": "chromium",
  "type": "ffi",
  "abi_version": 1,
  "description": "自带 Chromium 120，不依赖系统 WebView",
  "engine_version": "120.0.6099.1",
  "capabilities": ["loadUrl", "evaluateJs", "userScripts", "multiTab", "download"],
  "libraries": {
    "windows": "bin/windows/kernel.dll",
    "linux": "bin/linux/libkernel.so",
    "android": {
      "arm64-v8a": "bin/android/arm64-v8a/libkernel.so",
      "armeabi-v7a": "bin/android/armeabi-v7a/libkernel.so",
      "x86_64": "bin/android/x86_64/libkernel.so"
    }
  },
  "runtime_dir": "runtime"
}
```

字段说明：

| 字段 | 必需 | 说明 |
|---|---|---|
| `manifest_version` | 是 | 当前固定 `1` |
| `id` | 是 | 反向域名格式 |
| `name` / `version` | 是 | 名称与版本 |
| `display_name` | 否 | 内核选择列表中显示的名字 |
| `description` / `engine_version` | 否 | 描述与底层引擎版本 |
| `engine` | 是 | 引擎谱系：`chromium` / `gecko` / `system` / `custom` |
| `type` | 是 | `ffi`（dart:ffi 加载）/ `webview2_fixed`（运行时目录） |
| `abi_version` | 否 | FFI ABI 版本，需与宿主一致（当前 `1`） |
| `capabilities` | 否 | 声明的能力位 |
| `libraries` | 是 | 平台 → 库相对路径；Android 为按 ABI 的 Map |
| `runtime_dir` | 否 | Fixed Version 类运行时目录（Windows） |

`libraries` 平台键：`windows` / `linux` / `android` / `macos`。
Android 的 ABI 键：`arm64-v8a` / `armeabi-v7a` / `x86_64`。

## 打包与校验

```bash
python tool/pack_kernel.py path/to/kernel_dir zip_browser_kernel.zbk
```

脚本会校验：

- `kernel.json` 是否存在且为合法 JSON；
- `id` / `name` / `version` / `engine` / `type` 是否齐全合法；
- `abi_version` 是否与宿主一致；
- `libraries` 中声明的每个库文件是否真实存在。

校验通过即输出 `.zbk`。在内核管理页安装后，可在内核列表中选中切换；
新开标签页使用选中内核，系统内核始终保留、可随时切回。

## 示例

`build_kernel_pkg/zb_example_standalone/` 是一个可直接打包的示例
（零依赖软件渲染内核，Windows dll + Android 三 ABI so）：

```bash
python tool/pack_kernel.py build_kernel_pkg/zb_example_standalone zip_browser_kernel.zbk
```
