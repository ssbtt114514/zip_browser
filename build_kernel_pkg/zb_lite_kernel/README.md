# 独立内核包：轻量文本内核（zb_lite_kernel）

本目录是一个可直接打包成 `.zbk` 的**独立内核包**：只提供一个可替换的浏览器
内核，不含任何页面脚本 / UI 扩展。安装与切换方式见
[设置 → 内核管理](../../docs/KERNEL_PACK.md)。

内核本体源码在 [native_kernels/zb_lite_kernel](../../native_kernels/zb_lite_kernel)，
设计说明与协议见 [docs/KERNEL_LITE.md](../../docs/KERNEL_LITE.md)。

## 内容

```text
build_kernel_pkg/zb_lite_kernel/
├── kernel.json                                   内核清单（id / 版本 / 能力 / 各平台库）
├── bin/windows/zb_lite_kernel.dll                Windows x64 产物（已包含）
├── bin/linux/x86_64/libzb_lite_kernel.so         需构建（见下）
└── bin/android/<abi>/libzb_lite_kernel.so        需构建（见下）
```

`kernel.json` 的 `libraries` 字段与 `lib/core/kernel/kernel_manifest.dart` 的
解析规则一致：`windows` / `linux` 为字符串路径，`android` 为按 ABI 的映射
（`arm64-v8a` / `armeabi-v7a` / `x86_64`）。宿主只加载当前平台且产物真实存在
的条目，其它平台会在内核列表里标注为"当前平台不可用"。

## 构建各平台产物

```bat
:: Windows
tool\build_lite_kernel.bat
```

```bash
# Linux / Android NDK
sh tool/build_lite_kernel.sh linux
sh tool/build_lite_kernel.sh android-arm64-v8a
sh tool/build_lite_kernel.sh android-armeabi-v7a
sh tool/build_lite_kernel.sh android-x86_64
```

构建产物默认落在插件目录 `example_plugins/lite_kernel/kernels/...`，
把它们复制到本目录对应的 `bin/...` 路径即可：

```bash
cp example_plugins/lite_kernel/kernels/windows/zb_lite_kernel.dll bin/windows/
mkdir -p bin/linux/x86_64 bin/android/arm64-v8a bin/android/armeabi-v7a bin/android/x86_64
cp example_plugins/lite_kernel/kernels/linux/x86_64/libzb_lite_kernel.so bin/linux/x86_64/
cp example_plugins/lite_kernel/kernels/android/arm64-v8a/libzb_lite_kernel.so bin/android/arm64-v8a/
cp example_plugins/lite_kernel/kernels/android/armeabi-v7a/libzb_lite_kernel.so bin/android/armeabi-v7a/
cp example_plugins/lite_kernel/kernels/android/x86_64/libzb_lite_kernel.so bin/android/x86_64/
```

在运行打包之前，建议先跑一次自检（走完整链路：create → load HTML → attach 假
surface → tick → 校验帧缓冲确有非背景像素）：

```bash
sh tool/build_lite_kernel.sh selftest
```

## 打包成 .zbk

```bash
python tool/pack_kernel.py build_kernel_pkg/zb_lite_kernel zip_browser_kernel_lite.zbk
```

安装：应用内 **设置 → 内核管理 → 安装内核包**，选择该 `.zbk`；
随后在内核列表中选中「轻量文本内核（.zbk）」，**新开标签页**即由它渲染。

## 能力边界

- ✅ http/https 真实加载（依赖宿主注册 `net.fetch` 桥接方法）
- ✅ HTML 文本解析、自动换行排版、点阵字库渲染、滚动 / 点击链接 / 历史导航
- ✅ `eval_js` 支持 `document.title`、`document.body.innerText`、`document.links`、
  `location.href`、`window.scrollTo/scrollBy`
- ❌ 无 JavaScript 引擎、无 CSS 布局、无图片解码（`img` 只画占位框 + alt 文本）、
  CJK 字符以"豆腐块"占位（宽度与换行位置正确）
