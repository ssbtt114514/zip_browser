# Zip Browser

一个使用 **Flutter** 开发、可通过**独立内核包（.zbk）**扩展浏览器内核的多平台浏览器框架。

- ✅ **Android**：调用系统 **Android System WebView**（不打包内核，随系统更新）；
  minSdk 21（Android 5.0，边界说明见
  [docs/ANDROID_COMPAT.md](docs/ANDROID_COMPAT.md)）
- ✅ **Windows**：使用 **WebView2**（Edge Chromium）
- ✅ **Linux**：使用 **WebKitGTK**
- 🚧 **macOS**：架构已预留，后续适配
- 📦 构建风味 **无内核版 / Chromium 版 / Gecko 版**（内核随安装包内置，
  应用内不再提供内核安装入口）
- 🔌 zip 功能插件接口已于 **v0.12.0 移除**（历史版本说明见 Release）

## 功能特性

### 界面（v0.6.0 重新设计）

- **统一设计令牌**：`lib/ui/design/zb_design.dart` 提供间距 / 圆角 / 动效时长与
  一套**语义色板**（`ZbColors`）。外壳、标签栏、地址栏、书签栏全部改为从主题
  取色，修复了旧版在深色主题下"标签栏发白、地址栏白底黑字"的问题，
  颜色随深色模式与莫奈动态取色实时联动。
- **标签栏**：卡片式标签、"浮起"的活动标签、悬停反馈；支持**拖拽排序**
  （拖入 / 拖出固定区自动固定 / 取消固定）、**固定标签**、标签组（命名 + 换色 +
  折叠）、标签搜索面板、右键 / 长按菜单（复制标签、在右侧新建、关闭其他、
  关闭右侧、复制链接）。
- **地址栏（Omnibox）**：胶囊输入框、可点击的安全状态胶囊（HTTPS / HTTP / 本地
  文件 / 内置页，弹出站点信息与站点级缩放）、**本地联想下拉**（聚焦先列出最近
  访问，输入后给出历史 + 书签 + 搜索 / 直达建议，支持 ↑ ↓ 选择、Enter 打开、
  Tab 补全、Esc 分两级收起、一键清空）、缩放倍率胶囊。链接识别统一收敛在
  `UrlInput`：大小写 scheme、协议相对地址、本机 IP 与端口、中文域名均可识别，
  粘贴内容会自动剥离「」<> 等包裹符号与句末标点。
- **书签栏**：地址栏下方一键开关（`Ctrl+Shift+B`），右键可"在新标签打开 /
  复制链接 / 删除"。
- **主菜单**：桌面端重构为二级菜单——「标签页 / 页面 / 数据 / 显示 / 工具 /
  系统」六组子菜单（MenuAnchor + SubmenuButton），开关项带勾选状态、
  快捷键提示保留；窄屏底部面板为扁平分组。
- **响应式**：宽度 < 720 时切换为紧凑布局（标签栏在工具栏下方、标签变窄），
  地址栏在窄屏按宽度渐进隐藏缩放胶囊与书签星标，优先保证输入区空间。
- **内置新标签页**：重新设计的 HTML 页面——图形标记 + 搜索卡片 + 常用站点宫格
  （字母头像按域名哈希取色）+ 最近访问列表，支持浅色 / 深色两套配色与
  渐入动画，暗色主题跟随宿主设置。搜索框与地址栏共用同一套链接判定，
  `localhost:端口`、`192.168.x.x`、带端口的域名都会直接打开而不是去搜索。

### 浏览器能力

- 多标签页、前进 / 后退 / 刷新 / 停止、隐私标签、恢复关闭的标签页
- **键盘快捷键**：见下表
- **网页缩放**：按站点记忆倍率（`ZoomService`），档位 25% – 500%，可在地址栏
  胶囊、工具箱、设置里调整与重置
- **会话恢复**：退出时保存打开的标签（隐私标签不保存），下次启动可"打开主页"
  或"恢复上次会话"，并记录是否异常退出
- 书签、历史记录、下载管理、清除浏览数据、页面内查找
- **资源嗅探**：自动嗅探页面视频 / 音频 / 图片，顶部浮动提示，可手动开关
- **资源预览**：图片全屏缩放预览，视频 / 音频直接播放，一键下载
- **二维码扫描**：扫一扫，识别 URL 直接打开
- **文字识别（OCR）**：选图取字、一键复制；Android 内置 ML Kit 离线识别
  （中文脚本，图片不上传），Windows / Linux 走 AI 解读配置的多模态接口
- **AI 解读 / 翻译**：读取网页正文交给 OpenAI 兼容接口总结，Google 翻译
  免费接口（失败回落 MyMemory）
- **阅读模式**、无图模式、多组色彩滤镜、字号 / 行距调节
- 桌面版 UA、长按菜单、分享、全屏
- **莫奈动态取色（Material You）**：Android 12+ 跟随壁纸生成主题，可开关；
  其余平台由**内置莫奈引擎**（material_color_utilities HCT 调色板）从
  主题种子色生成同款配色
- 多搜索引擎、深色 / 浅色主题、自定义外观
- SVG 应用图标，独立内核包可热插拔

### 键盘快捷键

| 快捷键 | 功能 | 快捷键 | 功能 |
|---|---|---|---|
| `Ctrl+T` | 新建标签页 | `Ctrl+W` | 关闭当前标签 |
| `Ctrl+Shift+N` | 新建隐私标签 | `Ctrl+Shift+T` | 恢复关闭的标签页 |
| `Ctrl+Tab` | 下一个标签 | `Ctrl+Shift+Tab` | 上一个标签 |
| `Ctrl+1` … `Ctrl+8` | 切换到第 N 个标签 | `Ctrl+9` | 切换到最后一个标签 |
| `Ctrl+L` | 聚焦地址栏 | `Ctrl+F` | 页面内查找 |
| `F5` / `Ctrl+R` | 刷新 | `Ctrl+Shift+R` | 强制刷新（清缓存） |
| `Alt+←` / `Alt+→` | 后退 / 前进 | `Alt+Home` | 打开主页 |
| `Ctrl++` / `Ctrl+-` | 放大 / 缩小 | `Ctrl+0` | 重置缩放 |
| `Ctrl+D` | 加入 / 移除书签 | `Ctrl+Shift+B` | 显示 / 隐藏书签栏 |
| `Ctrl+Shift+O` | 书签管理 | `Ctrl+H` / `Ctrl+J` | 历史 / 下载 |
| `F11` | 全屏 | `Esc` | 收起查找栏 / 嗅探面板 / 地址栏下拉 |

---

## 快速开始

### 1. 初始化工程（生成 android / windows 目录）

```bash
# Windows
tool\init_project.bat

# Linux / macOS 主机
sh tool/init_project.sh
```

等价于：

```bash
flutter create --platforms=android,windows --org com.zipbrowser --project-name zip_browser .
flutter pub get
```

### 2. 运行

```bash
flutter run -d <android-device>   # Android
flutter run -d windows            # Windows（需 Windows 主机 + WebView2 Runtime）
```

### 3. 构建风味与内核

内核随安装包内置，运行期不再安装：

- **无内核版**：不包含引擎内核，用于扩展开发与内核包调试
- **Chromium 版**（默认）：Android / Windows / Linux 调用系统 WebView，
  随系统更新
- **Gecko 版**：安装包内置 `kernel.zbk`，首次启动自动安装并选中

选择风味：

```bash
flutter build apk --release --dart-define=ZIP_FLAVOR=gecko
```

`.zbk` 内核包格式本身仍保留，用于 Gecko 风味以外的定制内核分发。

### 4. 打包独立内核包

```bash
# 轻量文本内核（C99 软件渲染）
sh tool/build_lite_kernel.sh android-arm64-v8a   # 先构建平台库
python tool/assemble_kernel_pkg.py
python tool/pack_kernel.py build_kernel_pkg/zb_lite_kernel zip_browser_kernel_lite.zbk
```

### 5. 轻量文本内核（可直接使用的软件渲染内核）

仓库自带一个**零外部依赖、C99 软件渲染**的原生内核「轻量文本内核」
（`zb_lite_kernel`）：经 `net.fetch` 真实抓取网页 → 解析 HTML → 按表面宽度
自动换行排版 → 用内置 8×16 点阵字库绘制 RGBA 帧上屏，并支持滚动、点击链接、
页内锚点与前进 / 后退 / 刷新。它没有 JS 引擎与 CSS 布局（诚实的能力边界见文档）。

```bash
# 自检：create → load HTML → attach 假 surface → tick → 校验帧缓冲确有像素
sh tool/build_lite_kernel.sh selftest

# 构建各平台产物（Windows 用 tool\build_lite_kernel.bat）
sh tool/build_lite_kernel.sh linux
sh tool/build_lite_kernel.sh android-arm64-v8a    # 另有 armeabi-v7a / x86_64

# 打包独立内核包
python tool/pack_plugin.py example_plugins/lite_kernel

# 独立内核包的 kernel.json 声明了 5 个平台，所以打包前要先把各平台产物
# 装配进它的 bin/ 目录（否则打包器会拒绝，避免打出「清单声明了、包里却没有」的包）
python tool/assemble_kernel_pkg.py
python tool/pack_kernel.py build_kernel_pkg/zb_lite_kernel zip_browser_kernel_lite.zbk
```

> 打包器会校验「清单里声明的每个平台库是否真的存在」，不一致就直接拒绝打包；
> 没在本地构建过的平台，也可以直接取 CI（`build-kernel` 工作流）产出的完整
> `lite_kernel.zip` 与 `zb_lite_kernel.zbk`。

> 主机要求：`selftest` 任意平台可用；`linux` / `android-*` 需要 **Linux 或 macOS**
> 主机（Android 还需 NDK）。脚本会主动拒绝在 Windows 上交叉编译 —— 因为那会把
> PE 动态库写成 `.so`，一旦提交，Linux 用户拿到的将是一个无法加载的库。
> Windows 版本请用 `tool\build_lite_kernel.bat`。

源码在 `native_kernels/zb_lite_kernel/`，设计与协议见
**[docs/KERNEL_LITE.md](docs/KERNEL_LITE.md)**。

内核包制作与宿主内核加载的契约见 **[docs/KERNEL_PACK.md](docs/KERNEL_PACK.md)**。

### 6. 本地一键验证

不需要 NDK / VS / GitHub Actions，一条命令复现 CI 里所有能离线跑的检查：

```bash
python tool/verify_all.py          # 全部检查
python tool/verify_all.py --list   # 只列出检查项
```

覆盖：内核编译（`-Wall -Wextra`）+ 端到端自检、预编译 DLL 的 16 个 ABI 导出符号、
两份清单声明的产物路径、工作流 YAML 合法性、工作流引用的仓库内路径是否存在、
`flutter analyze` 与 `flutter test`。缺少某项工具链时该项标记 `SKIP` 而非失败。

Flutter 不在 PATH 时用环境变量指定：

```bat
set FLUTTER_BIN=D:\flutter\bin\flutter.bat
```

测试套件里还有两个专门针对内核的回归文件：

- `test/ffi_kernel_integration_test.dart` —— 用 App **真实的 FFI 加载器**
  加载预编译 DLL，跑通「打开库（校验 ABI 版本）→ 绑定表面 → load_url →
  tick 出帧 → 读取帧缓冲确认真的画了东西 → eval_js / 输入事件 / 改尺寸重排版」。
  这是唯一能同时验证 C 内核实现与 Dart 侧 ABI 绑定是否彼此吻合的手段。
- `test/lite_kernel_package_test.dart` —— 覆盖「打包 → 安装」链路：
  插件包/独立内核包能被 `PluginPackage` / `KernelPackage` 安装，
  且随包的 Windows DLL 是真实 PE 并导出全部 16 个 ABI 符号。

### 7. 构建安装包 / 内核产物

Android 安装包：

```bash
flutter build apk --release   # 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 注意：`android/` 等平台目录由 `flutter create` 生成且不入库，
> 全新克隆后需先执行第 1 步初始化，再构建。

也可以在 GitHub Actions 中一键构建（推 `v*` tag 或手动触发）：

| 工作流 | 产物 |
|--------|------|
| [build-android-apk.yml](.github/workflows/build-android-apk.yml) | Android 三风味 release APK（none / chromium / gecko），含 arm64-v8a / armeabi-v7a / x86 / x86_64；gecko 风味用 NDK 编译四 ABI 并内置 `.zbk`；main 推送即构建并校验 APK 内容，推 `v*` tag 时挂到 Release |
| [build-linux.yml](.github/workflows/build-linux.yml) | Linux 三风味桌面版，x64 / arm64 两架构（`zip-browser-linux-<arch>-<flavor>.tar.gz`）；gecko 风味本机编译内核并内置；先跑单元测试 |
| [build-kernel.yml](.github/workflows/build-kernel.yml) | **先跑 gcc 端到端自检**（106 项断言），再构建 `zb_lite_kernel` / `zb_example_kernel` 的 Windows `.dll` + Linux `.so` + Android 三 ABI `.so`，校验 16 个导出符号；产出 `lite_kernel.zip` / `hello_ffi_kernel.zip` / `zb_lite_kernel.zbk`，另加 `zb_chromium_kernel.zbk`（自带固定版本 Chromium 运行时）与 `zb_gecko_kernel.zbk`（Gecko 引擎适配包）；推 `v*` tag 时把这 5 个包挂到 Release |
| [build-windows.yml](.github/workflows/build-windows.yml) | 静态检查 + 单元测试 → 构建三风味（none / chromium / gecko）的 Windows x64 release；gecko 用 MSVC 编译内核 DLL 并内置 → 各自打包 zip 与 **Inno Setup 安装器**（独立 AppId，安装时静默装 VC++ 运行库与 WebView2 常青版）；推 `v*` tag 时挂到 Release |

### 8. 引擎内核包：Chromium 固定版本 / Gecko 适配包

v0.7.0 起，Release 里除了轻量文本内核，还提供两个与"引擎"相关、但**能力边界完全不同**的内核包：

| 内核包 | 清单类型 | 真实能力 | 适用平台 |
|--------|----------|----------|----------|
| `zb_chromium_kernel.zbk` | `webview2_fixed` | **真嵌入**：包内自带固定版本 Chromium（WebView2 Fixed Version，约 174 MB），在定制内核包路径下可替代系统内核渲染页面，不依赖系统 Evergreen 运行时 | 仅 Windows |
| `zb_gecko_kernel.zbk` | `engine_adapter` | **只探测，不渲染**：检测本机是否存在 Gecko 运行时（`xul.dll` / `libxul.so` / GeckoView），如实报告命中的路径与版本（读不到就写"未读取到"，不编造），缺失时给出可照做的提示 | 全平台 |

```bash
# Chromium：取运行时 → 装配进包目录 → 打 .zbk
python tool/fetch_webview2_runtime.py --out runtime_wv2 --arch x64
python tool/assemble_chromium_kernel.py --runtime runtime_wv2
python tool/pack_kernel.py build_kernel_pkg/zb_chromium_kernel zb_chromium_kernel.zbk

# Gecko 适配包只有清单与说明，任何平台都能打
python tool/pack_kernel.py build_kernel_pkg/zb_gecko_kernel zb_gecko_kernel.zbk

# 两类包都用宿主自己的安装器校验（Chromium 包加 --strict-runtime 挡住桩运行时）
dart run tool/verify_packages.dart --strict-runtime zb_chromium_kernel.zbk
dart run tool/verify_packages.dart zb_gecko_kernel.zbk
```

> **Gecko 为什么不能真渲染**：Gecko 目前没有任何可供第三方**离屏嵌入**的发行版
> （libxul 不对外提供嵌入接口；GeckoView 只在 Android、且要求宿主用 Kotlin 承载
> 平台视图），所以这个包绝不谎称能加载网页 —— 它只做引擎探测与提示。
> 详见 [docs/KERNEL_ADAPTER.md](docs/KERNEL_ADAPTER.md)。
>
> **Chromium 运行时的来源与许可**：运行时文件本体是微软的 WebView2 运行时
> （`LegalCopyright: Microsoft Corporation`），通过 NuGet 包 `WebView2.Runtime.X64`
> 获取，而该 NuGet 包的发布者账号并非微软官方；若要走完全官方的渠道，自行准备一份
> 固定版本运行时目录再 `assemble_chromium_kernel.py --runtime <目录>` 装配即可。
> 详见 [docs/KERNEL_CHROMIUM.md](docs/KERNEL_CHROMIUM.md)。

---

## 内核包能做什么

| 类型 | 说明 | 示例 |
|------|------|------|
| 独立内核包 `.zbk` | 携带原生内核库（`.dll/.so`，遵循统一 C ABI），安装后可替换系统内核渲染页面 | 固定版本 Chromium、**轻量文本内核** |
| 引擎适配包 | 只探测本机引擎运行时并如实报告，不渲染 | Gecko 适配包 |

> 说明：v0.11 及之前的 zip 功能插件接口（JS 扩展 / UI 扩展 / 插件携带内核）
> 已在 v0.12.0 移除；历史版本的插件开发文档仍在仓库 docs/ 目录可查，
> 但新版本不再提供安装入口。

---

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：分层架构、内核抽象、
  内核包格式、bridge 与安全模型
- [docs/KERNEL_PACK.md](docs/KERNEL_PACK.md)：独立内核包 `.zbk` 制作
- [docs/KERNEL_ABI.md](docs/KERNEL_ABI.md)：原生内核 FFI C ABI（16 个导出符号）
- [docs/KERNEL_LITE.md](docs/KERNEL_LITE.md)：轻量文本内核（zb_lite_kernel）
  的设计、`net.fetch` / 输入事件 / `kernel.state` 协议、能力边界
- [docs/KERNEL_CHROMIUM.md](docs/KERNEL_CHROMIUM.md)：Chromium 固定版本内核包
  （`webview2_fixed`）的取料、装配、打包与宿主契约
- [docs/KERNEL_ADAPTER.md](docs/KERNEL_ADAPTER.md)：Gecko 引擎适配包
  （`engine_adapter`）的语义、探测规则与"不渲染"的边界
- [docs/ANDROID_COMPAT.md](docs/ANDROID_COMPAT.md)：Android 平台兼容性
  （minSdk 21 的边界与 Android 4.x 的尝试结论）

## 目录

```text
lib/core/       内核抽象 / 内核包机制 / JS bridge / 标签页 / 主题引擎
lib/platform/   Android / Windows / FFI / 占位 内核实现
lib/services/   配置 / 书签 / 历史 / 下载 / 缩放 / 会话 / OCR / AI / 翻译等
lib/ui/         浏览器界面
  ├─ design/    设计令牌与语义色板（zb_design.dart）
  ├─ widgets/   标签栏 / 地址栏 / 联想下拉 / 工具栏 / 书签栏
  ├─ shortcuts/ 键盘快捷键与根焦点作用域
  └─ pages/     设置、书签、历史、下载、开发者工具箱、使用手册等页面
native_plugins/ 内核渲染所需的原生表面（纹理）
native_kernels/ 原生内核源码（zb_lite_kernel：零依赖软件渲染内核）
example_plugins/ 内核示例（FFI 内核 DLL 构建与集成测试用）
build_kernel_pkg/ 独立内核包（.zbk）源目录
tool/           初始化 / 打包 / 构建 / 集成脚本
```
