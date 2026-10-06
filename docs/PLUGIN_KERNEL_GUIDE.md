# 插件内核集成指南

本指南说明如何让“zip 插件携带的浏览器内核”在宿主中显示画面。

系统内核（Android System WebView / Windows WebView2 Evergreen）**不需要**
本指南的任何步骤，直接运行即可。本指南仅针对：

- Windows：WebView2 **Fixed Version** 固定内核
- Windows / 其他平台：遵循 C ABI 的 **FFI 原生内核**（示例为软件渲染）

---

## 一、前置：生成平台目录

```bash
# 在工程根目录
flutter create --platforms=android,windows --org com.zipbrowser --project-name zip_browser .
flutter pub get
```

---

## 二、Windows：启用原生表面插件

FFI 内核需要一个 Flutter 纹理来显示画面。原生表面插件
（`native_plugins/zb_native_surface`）负责：

1. 注册 Flutter 像素缓冲纹理
2. 导出 `zb_surface_submit_frame`，让内核把帧直接提交到纹理

一键集成（自动修改 `windows/CMakeLists.txt` 与
`windows/runner/flutter_window.cpp`，幂等）：

```bash
python tool/enable_native_surface.py
```

脚本会：

- 把 `zb_native_surface_plugin.cpp` 加入 runner 构建并配置 include
- 在 runner 中调用 `ZipBrowserNativeSurfacePluginRegisterWithRegistrar(...)`

> 手动集成等价于脚本内容：CMake 追加 `target_sources(... plugin.cpp)`
> 与 include 目录；`flutter_window.cpp` 在插件注册区调用注册函数。

---

## 三、编译示例 FFI 内核

示例内核 `zb_example_kernel.c` 是零依赖的软件渲染内核：

1. 打开 **x64 Native Tools Command Prompt for VS**
2. 运行：

```bat
tool\build_example_kernel.bat
```

得到：

```text
example_plugins/hello_ffi_kernel/kernels/windows/zb_example_kernel.dll
```

（也可用 LLVM：脚本会自动探测 clang。）

Android 平台（arm64-v8a / armeabi-v7a / x86_64）的 NDK clang 编译命令与产物打包，
见 `example_plugins/hello_ffi_kernel/README.md`；三平台自动构建由 GitHub Actions
工作流 `.github/workflows/build-kernel.yml` 完成。

---

## 四、打包并安装插件

```bat
:: 打包 FFI 内核插件
tool\pack_plugin.bat example_plugins\hello_ffi_kernel

:: 打包 JS 扩展示例
tool\pack_plugin.bat example_plugins\dark_mode
```

在浏览器中：**菜单 → 插件管理 → 安装 .zip**，选择生成的 zip；
然后 **菜单 → 设置 → 浏览器内核**，选择“示例软件渲染内核”，
**新开标签页**即由插件内核渲染（画面为内核软件绘制的演示界面）。

---

## 五、Windows：WebView2 Fixed Version（固定版本内核）

适合需要“内核版本完全随插件走、不依赖系统运行时”的场景。

1. 从微软下载 **Fixed Version** WebView2 运行时（cab），解压得到
   `msedgewebview2.exe` 所在目录
2. 放入插件目录，例如 `kernels/edge_fixed/...`
3. manifest 声明：

```json
"permissions": ["kernel"],
"kernel": {
  "type": "webview2_fixed",
  "runtime_dir": "kernels/edge_fixed",
  "display_name": "Edge 固定内核 120.x"
}
```

宿主会以该目录作为 `browserExecutableFolder` 创建 WebView2 环境。

> WebView2 环境在进程内只能初始化一次。若先运行过其他内核，
> 切换 Fixed Version 后 UI 会提示“重启浏览器后生效”。

---

## 六、自研 FFI 内核

内核动态库需实现 `zb_plugin_kernel_abi.h`（见
`native_plugins/zb_native_surface/include/`）导出的全部符号：

| 分类 | 符号 |
|------|------|
| 生命周期 | `zb_abi_version` `zb_kernel_create` `zb_kernel_destroy` |
| 导航 | `zb_kernel_load_url` `go_back` `go_forward` `reload` |
| 脚本 | `zb_kernel_eval_js` |
| 状态 | `zb_kernel_current_url` `zb_kernel_title` `name` `version` |
| 渲染 | `zb_kernel_attach_surface` `zb_kernel_tick` |
| 通信 | `zb_kernel_dispatch_from_host` `zb_free_ptr` |

渲染约定：

- `attach_surface` 收到 `texture_id` 与帧回调函数指针
- 每次产生新帧，调用 `frame_cb(texture_id, rgba, width, height, stride)`
  （RGBA8888，`stride` = 每行字节数）
- 宿主 surface 插件负责拷贝并刷新纹理
- 返回的 `const char*` 必须是堆内存，宿主用 `zb_free_ptr` 释放

内核请求宿主能力时，调用 create 时传入的 `host_dispatch(request_id,
method, params_json)`；宿主处理后通过 `zb_kernel_dispatch_from_host`
发回 `{request_id, result|error}`。

---

## 七、进阶：轻量文本内核（zb_lite_kernel）

`example_plugins/hello_ffi_kernel` 只是链路演示。仓库里还有一个**可直接使用**
的软件渲染内核「轻量文本内核」：它经 `net.fetch` 真实抓取网页、解析 HTML、
按表面宽度自动换行排版，并支持滚动 / 点击链接 / 页内锚点 / 前进后退。

### 1. 构建

```bat
:: Windows（VS 开发者命令行；无 cl 时脚本自动回退 clang）
tool\build_lite_kernel.bat
```

```bash
# Linux / Android（NDK，参数即目标平台）
sh tool/build_lite_kernel.sh linux
sh tool/build_lite_kernel.sh android-arm64-v8a
sh tool/build_lite_kernel.sh android-armeabi-v7a
sh tool/build_lite_kernel.sh android-x86_64
```

产物直接落在插件包内，与 `manifest.json` 的声明一一对应：

```text
example_plugins/lite_kernel/kernels/
├── windows/zb_lite_kernel.dll
├── linux/x86_64/libzb_lite_kernel.so
└── android/{arm64-v8a,armeabi-v7a,x86_64}/libzb_lite_kernel.so
```

> 打包前建议先跑自检（编译并运行 `tests/zb_lite_kernel_selftest.c`，
> 走一遍 `create → load HTML → attach 假 surface → tick → 校验帧缓冲`）：
> `sh tool/build_lite_kernel.sh selftest`。

### 2. 安装

```bat
tool\pack_plugin.bat example_plugins\lite_kernel
```

浏览器中 **插件管理 → 安装 .zip**，然后 **设置 → 浏览器内核** 选
「轻量文本内核」，**新开标签页**生效。

### 3. 宿主需要提供的桥接方法

内核的画面与交互依赖两个通过 `host_dispatch` 发起的方法（可以不实现，
但那样就只能看内置首页，且状态回报会被宿主以 `error` 回执）：

| method | 方向 | 作用 |
|---|---|---|
| `net.fetch` | 内核请求 → 宿主回包 | 抓取 http(s) 页面。参数 `{"url","method","max_bytes"}`，回包 `{"status","final_url","content_type","body"}` |
| `kernel.state` | 内核主动上报 | 通知宿主 `url/title/can_back/can_forward/loading/scroll_y/doc_height` 变化 |

输入事件（`pointer` / `scroll` / `key` / `resize`）由宿主通过
`zb_kernel_dispatch_from_host` 送入内核。三组协议的精确 JSON 格式见
[KERNEL_LITE.md](KERNEL_LITE.md)。

### 4. 能力边界

无 JavaScript 引擎、无 CSS 布局、不解码图片（`img` 画占位框 + alt 文本）、
CJK 字符以等宽"豆腐块"占位（宽度与换行位置正确）。`eval_js` 只支持
`document.title` / `document.body.innerText` / `document.links` / `location.href` /
`window.scrollTo` / `window.scrollBy`，其余脚本诚实返回
`{"ok":false,"error":"unsupported script"}`。

完整说明：[docs/KERNEL_LITE.md](KERNEL_LITE.md)。

---

## 八、Android 插件内核（实验性）

Android 默认使用系统 WebView，通常无需插件内核。若确需：

1. 将 `NativeSurfacePlugin.kt` 放入 android 工程并在
   `MainActivity.configureFlutterEngine` 注册
2. `createSurface` 注册 `SurfaceTexture` 并构造 `Surface`
3. 通过 JNI 把 `Surface`（ANativeWindow）交给 `.so` 内核，
   内核用 EGL 直接绘制
4. 帧上屏由 SurfaceTexture 机制完成

该路径需要额外的 JNI/EGL 胶水代码，属于高级用法。
