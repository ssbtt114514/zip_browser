# Chromium 固定版本内核包（`zb_chromium_kernel`）

这是 Zip Browser 的**随包分发内核**：把微软 WebView2 的 **Fixed Version Runtime**
（固定版本 Chromium/Edge 运行时）装进 `.zbk`，用户在应用内「内核管理」安装后即可选用，
内核版本从此不再随系统 Evergreen WebView2 自动升级而漂移。

| | |
|---|---|
| 清单 `id` | `com.zipbrowser.kernel.chromium` |
| `type` | `webview2_fixed` |
| `engine` | `chromium` |
| `runtime_dir` | `runtime`（内含 `msedgewebview2.exe`，仅 Windows 使用） |
| 平台 | **Windows**：WebView2 Fixed Version 运行时（x64）；**Linux / Android**：回落包内 FFI 渲染库 `bin/`（Chromium 标识，跨平台软件渲染） |
| 产物大小 | 约 **150-200 MB**（`.zbk`）；解包后磁盘占用更大（约 180 MB 级） |
| 版本字段 | 由装配脚本按 `msedgewebview2.exe` 的真实 PE 版本号改写，不是手填 |

> 跨平台说明：`kernel.json` 的 `libraries` 声明了 `linux` 与 `android`（三个 ABI）
> 的 FFI 渲染库（与 `zb_lite_kernel` 同 ABI，经 `zb_engine_kernel` 构建，引擎标识为
> `zb_chromium_kernel`）。宿主内核注册逻辑：Windows 上 `runtimeDir` 存在 → 用
> `WindowsSystemKernel(fixedRuntimeDir:)`（WebView2 Fixed Version）；Linux / Android 上
> 无运行时 → 回落 `FfiBrowserKernel` 加载 `bin/` 渲染库。因此 Chromium 内核包在
> 三平台都可安装、切换、显示画面。

## 四步流程

### 1. 取运行时

```bash
python tool/fetch_webview2_runtime.py --out /tmp/wv2 --arch x64
```

脚本会先**发现**再下载：查 NuGet V3 flat-container 索引拿版本列表，
全部 404 时回退到 NuGet 搜索 API 动态发现包 id（并把响应打印出来供核对），
然后下载 `.nupkg`、就地解包，自动定位含 `msedgewebview2.exe` 的那一层目录
并整体复制到 `--out`。只想看会选到哪个包、多大，不下载：

```bash
python tool/fetch_webview2_runtime.py --out /tmp/wv2 --dry-run
```

### 2. 装配

```bash
python tool/assemble_chromium_kernel.py --runtime /tmp/wv2
```

把运行时整体复制到 `build_kernel_pkg/zb_chromium_kernel/runtime/`（复制前先整体删除旧
`runtime/`，所以**幂等**，重复执行不叠加），并用真实运行时版本改写 `kernel.json` 的
`version` / `engine_version`。版本来源优先级：
`msedgewebview2.exe` 的 PE `FileVersion` > `ProductVersion` > `--version` > 路径里的版本号。
同时打印文件数、体积和关键文件体检结果。只检查不落盘加 `--dry-run`。

### 3. 打包

```bash
python tool/pack_kernel.py build_kernel_pkg/zb_chromium_kernel zb_chromium_kernel.zbk
```

### 4. 校验 / 安装

```bash
# 用宿主自己的安装器校验（CI 上必须带 --strict-runtime，它会额外要求运行时 ≥ 20 MiB，
# 从而挡住"桩运行时"混进正式产物）
dart run tool/verify_packages.dart --strict-runtime zb_chromium_kernel.zbk
```

把 `.zbk` 交给应用：**设置 → 内核管理 → 从文件安装**，安装成功后出现
「Chromium 固定版本内核」，选中它即生效。宿主会以
`WindowsSystemKernel(fixedRuntimeDir: <安装目录>/runtime)` 启动，
`runtime/` 直接作为 `WebviewController.initializeEnvironment(browserExePath: …)` 的入参，
所以 `runtime/msedgewebview2.exe` 必须存在——校验脚本对 `webview2_fixed` 类型**始终**
强制检查这一条。

## 能力声明

`kernel.json` 的 `capabilities` 如实描述 `WindowsSystemKernel` 实际实现的能力：

`loadUrl`、`evaluateJs`、`userScripts`、`multiTab`、`download`、`devTools`

未声明 `schemeIntercept` 与 `privateSession`：这套固定版本运行时走的是 WebView2 宿主接口，
这两项能力在 `WindowsSystemKernel` 上没有实现，声明了会误导调用方。

## 体积与许可

- **体积**：`.zbk` 约 150-200 MB，来自 WebView2 Fixed Version 运行时本体
  （x64 约 58 个文件 / 173.6 MiB，含 `msedgewebview2.exe`、`resources.pak`、
  `icudtl.dat`、`Locales/`、`msedge_elf.dll`、`vk_swiftshader.dll` 等）。压缩后的
  `.zbk` 实测约 **98 MB**（运行时主要是已压缩的二进制与 `.pak`，所以再压收益有限）。
- **许可**：运行时本体版权归 Microsoft（`msedgewebview2.exe` 的 `LegalCopyright` 为
  `Copyright Microsoft Corporation. All rights reserved.`）。WebView2 Runtime 的可再分发
  条款允许**随应用一起分发**该运行时，这正是 Fixed Version 分发的设计用途（用于钉住版本、
  离线/内网环境）。分发本包时请同时保留运行时的许可文件，不要把它当作可单独再分发的产品。
- **来源注意**：本仓库脚本从 NuGet 拉取的固定版本运行时包是第三方账号对微软运行时的
  **再打包**（nuspec `<authors>` 非微软官方）；运行时文件本体是微软原版。若你的合规要求
  更严格，请改用微软官方 Evergreen Bootstrapper/Fixed Version 下载渠道获取运行时，再用
  `python tool/assemble_chromium_kernel.py --runtime <目录>` 装配——脚本不关心运行时从哪来，
  只要目录里有 `msedgewebview2.exe`。

## 本目录里的文件

```
build_kernel_pkg/zb_chromium_kernel/
├── kernel.json   内核清单（version / engine_version 由装配脚本改写）
├── README.md     本文件（随包分发）
└── runtime/      装配产物：WebView2 固定版本运行时（**不入库**）
```

`runtime/` 是本机/CI 的装配中间产物，仓库里只提交清单和说明这两份文本，
真实运行时每次由 `fetch` + `assemble` 现取现装。

**注意**：`runtime/` **不在 `.gitignore` 里**（`build_kernel_pkg/**` 整体没有被忽略），
所以本机跑完装配后它是最多 174 MiB 的 untracked 目录，提交前必须删掉，或确认它没被
`git add` 进去：

```bash
rm -rf build_kernel_pkg/zb_chromium_kernel/runtime   # 本机验证完就删，CI 上不需要提交
```
