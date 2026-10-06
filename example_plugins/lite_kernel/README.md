# 插件：轻量文本内核（zb_lite_kernel）

一个**真正可用**的原生浏览器内核插件：零外部依赖、C99、软件渲染。
它不做"演示界面"，而是真的抓网页、解析 HTML、自动换行排版，并把文字画到
RGBA 帧缓冲上屏。

- 内核源码：[native_kernels/zb_lite_kernel](../../native_kernels/zb_lite_kernel)
- 设计说明与协议：[docs/KERNEL_LITE.md](../../docs/KERNEL_LITE.md)
- ABI 约定：[docs/KERNEL_ABI.md](../../docs/KERNEL_ABI.md)

## 能力一览

| 能力 | 说明 |
|---|---|
| 网络加载 | `zb_kernel_load_url("https://…")` 经 `host_dispatch("net.fetch")` 让宿主抓取，宿主用 `dispatch_from_host` 回传响应体；等待期间渲染「加载中」 |
| HTML 解析 | 剥离 `script/style/head/注释`、解码实体、识别块级/行内标签、记录 `<a href>` 链接区间与 `id` 锚点 |
| 排版 | 按表面宽度自动换行（英文按单词、CJK 按字符 2 格宽）、标题字号缩放、段落间距、列表前缀、引用缩进、`pre` 不折行、`hr` |
| 渲染 | 内置 8×16 点阵字库（ASCII 32..126），加粗/下划线/多色主题（含暗色），严格遵守 stride 写 RGBA8888 |
| 交互 | `pointer`（点击链接、`#fragment` 页内跳转）、`scroll`（带边界钳制）、`key`（Home/End/PageUp/PageDown/Up/Down） |
| 导航 | 前进 / 后退 / 刷新，`current_url` 与 `title` 正确更新（`<title>` → 首个 `<h1>` → URL 主机名） |
| 脚本 | `zb_kernel_eval_js` 提供 "document.title / document.body.innerText / document.links / location.href / window.scrollTo / window.scrollBy" 一组命令 |

**不是**完整浏览器：没有 JS 引擎、没有 CSS 布局、CJK 字符用"豆腐块"占位
（宽度与换行位置正确）。详见 [docs/KERNEL_LITE.md](../../docs/KERNEL_LITE.md)
的"能力边界"一节。

## 目录

```text
example_plugins/lite_kernel/
├── manifest.json                    插件清单（kernel.libraries 声明各平台产物）
├── icons/icon.png                   256×256 图标
├── kernels/windows/zb_lite_kernel.dll   Windows x64 产物（本目录已包含）
├── kernels/linux/x86_64/libzb_lite_kernel.so      需构建
└── kernels/android/<abi>/libzb_lite_kernel.so     需构建
```

## 构建

源码与构建脚本都在仓库里，产物直接落在本插件目录：

```bat
:: Windows（VS 开发者命令行；无 cl 时自动回退 clang）
tool\build_lite_kernel.bat
```

```bash
# Linux / Android（NDK）
sh tool/build_lite_kernel.sh linux
sh tool/build_lite_kernel.sh android-arm64-v8a
sh tool/build_lite_kernel.sh android-armeabi-v7a
sh tool/build_lite_kernel.sh android-x86_64
sh tool/build_lite_kernel.sh all        # 四个目标全建
sh tool/build_lite_kernel.sh selftest   # 编译并运行自检（推荐先跑）
```

也可以用 CMake：

```bash
cmake -S native_kernels/zb_lite_kernel -B build/lite-kernel -DZB_LITE_BUILD_SELFTEST=ON
cmake --build build/lite-kernel
```

> 本目录内的 `kernels/windows/zb_lite_kernel.dll` 是随仓库提供的预编译产物
> （x64，由 mingw-w64 gcc 构建；导出符号已核对为 16 个 ABI 符号齐全）。
> Linux / Android 产物需按上面的命令自行构建，或在 CI 中构建。

## 安装与使用

1. 确保宿主已集成原生表面插件：`python tool/enable_native_surface.py`
   （没有它内核能加载但画面无法上屏）。
2. 打包插件：

   ```bash
   python tool/pack_plugin.py example_plugins/lite_kernel
   ```

3. 浏览器中 **菜单 → 插件管理 → 安装 .zip**，选择生成的 zip；
4. **菜单 → 设置 → 浏览器内核** 选择「轻量文本内核」，**新开标签页**即由它渲染。

宿主侧还需注册两个桥接方法（不注册也能跑，只是会退化）：

- `net.fetch`：`params = {"url","method","max_bytes"}`，
  返回 `{"status","final_url","content_type","body"}`，
  内核通过 `dispatch_from_host({"request_id":N,"result":{…}})` 收包；
- `kernel.state`：内核主动上报状态（`url/title/can_back/can_forward/loading/scroll_y/doc_height/error`），
  未注册时内核会收到 `error` 回执并**容错忽略**。

精确的 JSON 格式见 [docs/KERNEL_LITE.md](../../docs/KERNEL_LITE.md) 的
「host_dispatch 协议」与「输入事件协议」两节。

## 自检

```bash
# Linux / macOS（本机有 gcc/clang 即可）
sh tool/build_lite_kernel.sh selftest
```

自检会走完整链路：`create → load HTML → attach 假 surface → tick → 校验帧缓冲确有
非背景像素`，另外覆盖 `net.fetch` 请求/回包、点击链接、相对地址解析、锚点跳转、
历史前进后退、滚动钳制、暗色主题、畸形 HTML 与超大输入等 100+ 项断言。
