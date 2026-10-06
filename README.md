# Zip Browser

一个使用 **Flutter** 开发、可通过 **zip 插件**扩展功能与浏览器内核的多平台浏览器框架。

- ✅ **Android**：调用系统 **Android System WebView**（不打包内核，随系统更新）
- ✅ **Windows**：使用 **WebView2**（Edge Chromium），支持系统 Evergreen 内核
  与插件携带的 Fixed Version 固定内核
- 🚧 **Linux / macOS**：架构已预留（占位内核），后续适配
- 🔌 插件为标准 **zip**：JS 扩展（DOM/脚本）、原生内核（`.dll/.so`，C ABI）、
  声明式 UI（按钮/菜单）；独立内核包为 **`.zbk`**

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
  文件 / 内置页，弹出站点信息与站点级缩放）、**本地联想下拉**（历史 + 书签 +
  搜索 / 直达建议，支持 ↑ ↓ 选择、Enter 打开、Tab 补全、Esc 收起）、缩放倍率
  胶囊。
- **书签栏**：地址栏下方一键开关（`Ctrl+Shift+B`），右键可"在新标签打开 /
  复制链接 / 删除"。
- **主菜单**：按浏览器习惯重排为「标签 → 导航 → 数据 → 缩放 → 站点开关 →
  工具 → 关于」，并标注对应快捷键。
- **响应式**：宽度 < 720 时切换为紧凑布局（标签栏在工具栏下方、标签变窄）。
- **内置新标签页**：重新设计的 HTML 页面——图形标记 + 搜索卡片 + 常用站点宫格
  （字母头像按域名哈希取色）+ 最近访问列表，支持浅色 / 深色两套配色与
  渐入动画，暗色主题跟随宿主设置。

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
- **阅读模式**、无图模式、多组色彩滤镜、字号 / 行距调节
- 桌面版 UA、长按菜单、分享、全屏
- **莫奈动态取色（Material You）**：Android 12+ 跟随壁纸生成主题，可开关
- 多搜索引擎、深色 / 浅色主题、自定义外观
- SVG 应用图标，内核与插件均可热插拔

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

### 3. 安装插件

- 菜单（右上角 ⋮）→ **插件管理** → **安装 .zip**
- 菜单 → **设置** → **浏览器内核** 可切换系统 / 插件内核（新标签页生效）

### 4. 打包示例插件

```bash
# JS 扩展示例（夜间模式）
python tool/pack_plugin.py example_plugins/dark_mode

# FFI 内核示例（需先按指南启用表面插件并编译 dll）
python tool/pack_plugin.py example_plugins/hello_ffi_kernel

# 独立内核包（.zbk）
python tool/pack_kernel.py build_kernel_pkg/zb_example_standalone zip_browser_kernel.zbk
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

# 打包插件 / 独立内核包
python tool/pack_plugin.py example_plugins/lite_kernel
python tool/pack_kernel.py build_kernel_pkg/zb_lite_kernel zip_browser_kernel_lite.zbk
```

> 主机要求：`selftest` 任意平台可用；`linux` / `android-*` 需要 **Linux 或 macOS**
> 主机（Android 还需 NDK）。脚本会主动拒绝在 Windows 上交叉编译 —— 因为那会把
> PE 动态库写成 `.so`，一旦提交，Linux 用户拿到的将是一个无法加载的库。
> Windows 版本请用 `tool\build_lite_kernel.bat`。

源码在 `native_kernels/zb_lite_kernel/`，设计与协议见
**[docs/KERNEL_LITE.md](docs/KERNEL_LITE.md)**。

插件内核（让 zip 里的内核显示画面）的完整步骤见
**[docs/PLUGIN_KERNEL_GUIDE.md](docs/PLUGIN_KERNEL_GUIDE.md)**。

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
| [build-android-apk.yml](.github/workflows/build-android-apk.yml) | Android release APK |
| [build-kernel.yml](.github/workflows/build-kernel.yml) | **先跑 gcc 端到端自检**（106 项断言），再构建 `zb_lite_kernel` / `zb_example_kernel` 的 Windows `.dll` + Linux `.so` + Android 三 ABI `.so`，校验 16 个导出符号，打包为 `lite_kernel.zip` / `hello_ffi_kernel.zip` 与 `.zbk` |
| [build-windows.yml](.github/workflows/build-windows.yml) | 静态检查 + 单元测试 → 编译内核 DLL → 构建 Windows release → 打包 `zip-browser-windows-x64.zip` 与插件 zip；推 `v*` tag 时自动创建 Release |

---

## 插件能做什么

| 类型 | 说明 | 示例 |
|------|------|------|
| JS 扩展 | content script 注入页面，通过 `window.zipBrowser.call` 调用标签页/存储/下载等宿主 API | 夜间模式、去广告、翻译、脚本增强 |
| 原生内核 | zip 携带 `.dll/.so`，遵循统一 C ABI，可替换渲染内核 | 固定版本 Chromium、自研内核、**轻量文本内核** |
| UI 扩展 | 工具栏按钮、菜单项、popup 页面 | 扩展入口、工具弹窗 |

插件权限（`tabs` / `storage` / `downloads` / `kernel` …）在 manifest 中声明，
宿主按权限做 bridge 白名单；安装包做 SHA-256 指纹与目录防篡改校验。

> 说明：Flutter release（AOT）模式不能运行时动态加载 Dart 代码，
> 因此插件采用 JS + 原生库 + 声明式 UI 的组合，详见架构文档。

---

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：分层架构、内核抽象、
  插件格式、bridge 与安全模型
- [docs/PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md)：功能插件开发（结构、
  `plugin.json`、`window.zipBrowser` JS API、用户脚本、打包）
- [docs/KERNEL_PACK.md](docs/KERNEL_PACK.md)：独立内核包 `.zbk` 制作
- [docs/KERNEL_ABI.md](docs/KERNEL_ABI.md)：原生内核 FFI C ABI（16 个导出符号）
- [docs/KERNEL_LITE.md](docs/KERNEL_LITE.md)：轻量文本内核（zb_lite_kernel）
  的设计、`net.fetch` / 输入事件 / `kernel.state` 协议、能力边界
- [docs/PLUGIN_KERNEL_GUIDE.md](docs/PLUGIN_KERNEL_GUIDE.md)：
  原生表面插件、FFI / Fixed Version 内核集成

## 目录

```text
lib/core/       内核抽象 / 插件系统 / JS bridge / 标签页 / 主题引擎
lib/platform/   Android / Windows / FFI / 占位 内核实现
lib/services/   配置 / 书签 / 历史 / 下载 / 缩放 / 会话 / 地址栏补全等
lib/ui/         浏览器界面
  ├─ design/    设计令牌与语义色板（zb_design.dart）
  ├─ widgets/   标签栏 / 地址栏 / 联想下拉 / 工具栏 / 书签栏
  ├─ shortcuts/ 键盘快捷键与根焦点作用域
  └─ pages/     设置、书签、历史、下载、内核与插件管理等页面
native_plugins/ 插件内核所需的原生表面（纹理）
native_kernels/ 原生内核源码（zb_lite_kernel：零依赖软件渲染内核）
example_plugins/ 示例插件
build_kernel_pkg/ 独立内核包（.zbk）源目录
tool/           初始化 / 打包 / 构建 / 集成脚本
```
