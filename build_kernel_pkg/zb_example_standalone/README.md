# 示例独立内核包（.zbk）

本包演示 Zip Browser 的**独立内核包**机制。`.zbk` 本质是 zip，与「功能插件」
（`pack_plugin.py` 打包的扩展）的区别在于：独立内核包只提供一个可替换的
浏览器内核，由「设置 → 内核管理」安装与切换。

## 安装

1. 应用内打开 **设置 → 内核管理 → 安装内核包**；
2. 选择本 `.zbk` 文件；
3. 在列表中选中该内核，新开标签页即会使用它。

## 内容

- `kernel.json`：内核清单（id / 版本 / 能力 / 各平台库路径）；
- `bin/windows/zb_example_kernel.dll`：Windows x64 原生库；
- `bin/android/<abi>/libzb_example_kernel.so`：Android 三 ABI 原生库。

该内核为零依赖软件渲染：接收页面内容、提取文本、用内置点阵字库绘制帧，
经 native surface 上屏，用于验证内核加载链路（不做真实 HTML 排版）。

## 自行打包

```bash
python tool/pack_kernel.py build_kernel_pkg/zb_example_standalone zip_browser_kernel.zbk
```

校验规则见 `tool/pack_kernel.py` 与 `lib/core/kernel/kernel_manifest.dart`。
