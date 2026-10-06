# Chromium 固定版本内核（WebView2 Fixed Version）

本文说明 Zip Browser 的 **Chromium 固定版本内核包**（`.zbk`）是什么、怎么产出、怎么在应用里
启用，以及它的体积/许可边界。配套文件：

- `tool/fetch_webview2_runtime.py` —— 从 NuGet 发现并下载 WebView2 Fixed Version 运行时
- `tool/assemble_chromium_kernel.py` —— 把运行时装配进内核包目录并按真实版本改写清单
- `build_kernel_pkg/zb_chromium_kernel/kernel.json` + `README.md` —— 内核包清单与随包说明
- `.github/workflows/build-kernel.yml` 的 `chromium-kernel` 作业 —— CI 上的四次一链（发现 → 下载 → 装配 → 打包 → 校验）

## 为什么需要它

宿主默认用**系统自带的 Evergreen WebView2**。这有两个问题：

1. **版本漂移**：内核跟着系统自动升级，今天能跑的页面明天可能因为内核变更而表现不同，
   线上问题难以复现。
2. **可用性不可控**：干净系统/精简系统/内网机器上可能根本没有 WebView2 Runtime，浏览器
   起不来。

**固定版本（Fixed Version）运行时**把一份特定版本的 Chromium/Edge 运行时随应用一起分发，
装进「内核管理」后，宿主以
`WindowsSystemKernel(fixedRuntimeDir: <安装目录>/runtime)` 启动，内核 id 变为
`system.windows_webview2_fixed`，从此不再依赖系统 Evergreen 版本。

## 与宿主的契约（决定了包必须长什么样）

| 宿主行为 | 位置 | 对内核包的要求 |
|---|---|---|
| 清单解析与类型白名单 | `lib/core/kernel/kernel_manifest.dart` | `type` 必须是 `ffi` 或 `webview2_fixed`；`id` 匹配 `^[a-z0-9_]+(\.[a-z0-9_]+)+$` |
| 安装时的产物检查 | `lib/core/kernel/kernel_package.dart` | `webview2_fixed` 且 `libraries` 为空时，**必须**有非空 `runtime_dir`；ABI 版本必须是 1 |
| 平台可用性 | 同上 | `availableOn('windows')` 对 `webview2_fixed` = Windows 且 `runtime_dir` 目录存在 |
| 启动固定版本内核 | `lib/platform/windows_system_kernel.dart` | `runtime_dir` 目录被直接传给 `WebviewController.initializeEnvironment(browserExePath: …)`，所以目录里**必须**有 `msedgewebview2.exe` |
| 能力键名 | `lib/core/kernel/kernel_types.dart` | 只有宿主真的实现了的能力才能声明 |

因此本包的 `kernel.json`：`type: webview2_fixed`、`runtime_dir: runtime`、`libraries: {}`、
`capabilities` 只声明 `WindowsSystemKernel` 实际实现的 6 项
（`loadUrl` / `evaluateJs` / `userScripts` / `multiTab` / `download` / `devTools`），
不含 `schemeIntercept` 与 `privateSession`。

## 产出流程

```bash
# 1) 发现 + 下载 + 解包（自动定位含 msedgewebview2.exe 的那一层目录）
python tool/fetch_webview2_runtime.py --out "$TMPDIR/wv2" --arch x64

# 2) 装配进内核包目录（复制前先整体删除旧 runtime/，幂等）
python tool/assemble_chromium_kernel.py --runtime "$TMPDIR/wv2"

# 3) 打包
python tool/pack_kernel.py build_kernel_pkg/zb_chromium_kernel zb_chromium_kernel.zbk

# 4) 用宿主自己的安装器校验（--strict-runtime 会额外要求运行时 ≥ 20 MiB）
dart run tool/verify_packages.dart --strict-runtime zb_chromium_kernel.zbk
```

只想知道会拉到哪个包、多大，不下载：

```bash
python tool/fetch_webview2_runtime.py --out "$TMPDIR/wv2" --dry-run
```

### 包 id 的坑（脚本为什么要"先发现再下载"）

`microsoft.web.webview2.fixedversionruntime.*` 这一系列 id 在 NuGet 上**全部 404**；
`microsoft.web.webview2` 只是 SDK 包，**不含运行时**。真正的固定版本运行时由第三方账号发布
为 `WebView2.Runtime.X64` / `.X86` / `.ARM64`。脚本因此先按候选表探测 flat-container 索引，
全部 404 时回退 NuGet 搜索 API 动态发现，并把探测过程原样打印出来供核对。

## CI

`.github/workflows/build-kernel.yml` 的 `chromium-kernel` 作业（ubuntu-latest，不依赖其它作业）：

1. `--dry-run` 发现一遍（把候选 id / 命中包 / 版本 / 直链 / 体积打进日志）
2. 真下载 + 解包
3. 装配（按 `msedgewebview2.exe` 的真实 PE 版本号改写 `kernel.json` 的 `version` / `engine_version`）
4. 打包 `.zbk`
5. `dart run tool/verify_packages.dart --strict-runtime zb_chromium_kernel.zbk`
6. 上传 artifact；`package` 作业把它搬到工作区根目录，`v*` 标签推送时挂到 Release

`--strict-runtime` 是必须的：它要求包内运行时总体积 ≥ 20 MiB，能挡住本地联调用的
「几个 KB 的桩 `msedgewebview2.exe`」混进正式产物。本地用桩验证时**不要**加这个开关
（桩本来就不到 20 MiB）。

## 体积与许可

- **体积**：运行时 173.6 MiB（x64 共 58 个文件），打出的 `.zbk` 实测 103,121,495 字节
  （98.3 MiB）——运行时以已压缩的二进制与 `.pak` 为主，再压收益有限。仓库里**不提交**
  运行时：`build/` 已被 `.gitignore` 忽略，而 `build_kernel_pkg/zb_chromium_kernel/runtime/`
  **没有**被忽略，本机装配完必须自己删掉，否则会成为一个 174 MiB 的 untracked 目录。
  每次由脚本现取现装。CI 只上传最终的 `.zbk`（artifact 会自行压缩），不上传 `runtime/`。
- **许可**：运行时本体版权归 Microsoft，`msedgewebview2.exe` 的 `LegalCopyright` 为
  `Copyright Microsoft Corporation. All rights reserved.`。WebView2 Runtime 的可再分发条款
  允许随应用一起分发（固定版本分发正是它的设计用途之一：钉住版本、离线/内网可用）。
  分发时请保留运行时的许可文件。
- **来源**：脚本从 NuGet 取的固定版本运行时包是第三方账号对微软运行时的**再打包**
  （nuspec `authors` 不是微软官方），运行时文件本体是微软原版。若合规要求更严格，可自行
  通过微软官方渠道取得运行时目录，再执行第 2 步 `assemble_chromium_kernel.py --runtime <目录>`
  —— 装配脚本不关心运行时来自哪里，只要求目录里有 `msedgewebview2.exe`。
