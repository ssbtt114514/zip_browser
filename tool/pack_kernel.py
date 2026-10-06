#!/usr/bin/env python3
"""
独立内核包（.zbk）打包 / 校验工具。

用法：
    # 打包一个已准备好的内核目录（目录内需含 kernel.json）
    python tool/pack_kernel.py <内核目录> [输出.zbk]

    # 生成一个可直接安装的示例内核包（用于联调安装流程）
    python tool/pack_kernel.py --demo [输出.zbk]

内核包目录结构（.zbk 本质是 zip，路径以本目录为根）：
    kernel.json                必需：内核清单
    bin/windows/kernel.dll     按平台/ABI 存放的原生库
    bin/linux/libkernel.so
    bin/android/arm64-v8a/libkernel.so
    runtime/                   可选：WebView2 Fixed Version 类运行时目录

内核类型（kernel.json 的 type 字段）：
    ffi             dart:ffi 原生库，必须声明 libraries
    webview2_fixed  WebView2 Fixed Version 运行时目录，必须声明 runtime_dir
                    且目录内需含 msedgewebview2.exe
    engine_adapter  引擎适配包：不携带任何平台产物（既无 libraries 也无
                    runtime_dir），只做本机引擎运行时探测，不提供网页渲染。
                    详见 docs/KERNEL_ADAPTER.md
"""
import json
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack_common  # noqa: E402  （与打包器同目录的共用校验）

# 与 Dart 侧 KernelManifest / KernelPackage 保持一致的校验规则
SUPPORTED_TYPES = ("ffi", "webview2_fixed", "engine_adapter")
SUPPORTED_ABI = 1
ID_RE = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)+$")
MANIFEST_ENTRY = "kernel.json"
# WebView2 Fixed Version 运行时里必须存在的宿主可执行文件：
# 宿主 WindowsSystemKernel 会把它交给
# WebviewController.initializeEnvironment(browserExePath: …)，缺了它内核起不来。
WEBVIEW2_RUNTIME_EXE = "msedgewebview2.exe"
SKIP_FILES = (".DS_Store",)
SKIP_SUFFIX = ("~",)
SKIP_DIRS = (".git", "__MACOSX")

DEMO_MANIFEST = {
    "manifest_version": 1,
    "id": "com.example.kernel.demo",
    "name": "示例独立内核包",
    "display_name": "示例内核（Demo）",
    "version": "1.0.0",
    "engine": "custom",
    "type": "ffi",
    "abi_version": 1,
    "description": "用于验证内核安装/切换流程的占位内核包，不含真实渲染实现。",
    "engine_version": "demo-1.0.0",
    "capabilities": ["loadUrl", "evaluateJs", "userScripts", "multiTab", "download"],
    "libraries": {
        "windows": "bin/windows/kernel.dll",
        "linux": "bin/linux/libkernel.so",
        "android": {
            "arm64-v8a": "bin/android/arm64-v8a/libkernel.so",
            "armeabi-v7a": "bin/android/armeabi-v7a/libkernel.so",
            "x86_64": "bin/android/x86_64/libkernel.so",
        },
    },
}


def validate(manifest):
    """返回错误字符串列表（空表示合法）。"""
    errors = []

    def req(key):
        v = manifest.get(key)
        if not isinstance(v, str) or not v.strip():
            errors.append(f'字段 "{key}" 缺失或不是非空字符串')
            return ""
        return v.strip()

    mid = req("id")
    req("name")
    req("version")

    if not isinstance(manifest.get("manifest_version"), int):
        errors.append('字段 "manifest_version" 必须是整数')
    if mid and not ID_RE.match(mid):
        errors.append('"id" 必须采用反向域名格式，如 com.example.kernel.chromium')

    mtype = str(manifest.get("type", "ffi")).strip()
    if mtype not in SUPPORTED_TYPES:
        errors.append(f'"type" 必须是 {"/".join(SUPPORTED_TYPES)} 之一，当前为 "{mtype}"')

    abi = manifest.get("abi_version", 1)
    if not isinstance(abi, int):
        errors.append('字段 "abi_version" 必须是整数')
    elif mtype == "ffi" and abi != SUPPORTED_ABI:
        errors.append(f'FFI 内核 ABI 版本需为 {SUPPORTED_ABI}，当前为 {abi}')

    libs = manifest.get("libraries")
    if libs is not None and not isinstance(libs, dict):
        errors.append('字段 "libraries" 必须是对象')
    runtime = manifest.get("runtime_dir")
    # engine_adapter 是适配器：不携带 libraries / runtime_dir 属正常情况，
    # 其余类型仍必须声明至少一项平台产物。
    if (
        mtype != "engine_adapter"
        and not libs
        and not (mtype == "webview2_fixed" and runtime)
    ):
        errors.append("清单未声明任何平台产物（libraries / runtime_dir 均为空）")

    caps = manifest.get("capabilities")
    if caps is not None and not isinstance(caps, list):
        errors.append('字段 "capabilities" 必须是数组')

    return errors


def check_webview2_runtime(src, manifest):
    """webview2_fixed 的打包前置守卫。

    清单声明了 runtime_dir 还不够：宿主 WindowsSystemKernel 会把该目录下的
    msedgewebview2.exe 交给 WebviewController.initializeEnvironment(browserExePath:)，
    目录不存在或缺少这个可执行文件时，打出来的 .zbk 装到用户机器上必然起不来。

    返回错误字符串列表（空表示通过）。仅用于 webview2_fixed。
    """
    runtime = manifest.get("runtime_dir")
    if not isinstance(runtime, str) or not runtime.strip():
        return []  # 缺 runtime_dir 已由 validate() 报错

    rel = runtime.strip().replace("\\", "/").strip("/")
    runtime_dir = os.path.join(src, rel.replace("/", os.sep))
    if not os.path.isdir(runtime_dir):
        return [
            f'清单声明 runtime_dir="{runtime}"，但包目录内不存在该目录：'
            f"{os.path.relpath(runtime_dir, src).replace(os.sep, '/')}"
        ]

    # 允许可执行文件位于 runtime_dir 的任意子目录（Fixed Version 目录结构
    # 可能带版本号层，如 runtime/120.0.2210.91/msedgewebview2.exe）
    for root, dirs, files in os.walk(runtime_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        if any(f.lower() == WEBVIEW2_RUNTIME_EXE for f in files):
            return []

    return [
        f'清单声明的 runtime_dir="{runtime}" 内未找到 {WEBVIEW2_RUNTIME_EXE}'
    ]


def report_webview2_runtime_errors(src, runtime_errors):
    print("WebView2 固定版本运行时校验失败：")
    for e in runtime_errors:
        print(f"  - {e}")
    print(
        "提示：固定版本运行时需要先下载并装配，可执行\n"
        "  python tool/fetch_webview2_runtime.py --out build_kernel_pkg/zb_chromium_kernel/runtime\n"
        "  python tool/assemble_chromium_kernel.py\n"
        "若运行时目录在别处，请把 runtime_dir 指向实际位置，或调整 --out 参数。"
    )
    return 1


def iter_files(src):
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if f in SKIP_FILES or f.endswith(SKIP_SUFFIX):
                continue
            full = os.path.join(root, f)
            arc = os.path.relpath(full, src).replace(os.sep, "/")
            yield full, arc


def write_zip(src, out):
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for full, arc in iter_files(src):
            z.write(full, arc)
            count += 1
    return count


def pack_dir(src, out):
    manifest_path = os.path.join(src, MANIFEST_ENTRY)
    if not os.path.isfile(manifest_path):
        print(f"目录内未找到 {MANIFEST_ENTRY}：{src}")
        return 1

    try:
        with open(manifest_path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"{MANIFEST_ENTRY} 解析失败：{exc}")
        return 1

    errors = validate(manifest)
    if errors:
        print("内核清单校验失败：")
        for e in errors:
            print(f"  - {e}")
        return 1

    # webview2_fixed：清单声明 runtime_dir 后，还必须真的有运行时目录与
    # msedgewebview2.exe，否则安装后必然不可用。
    if str(manifest.get("type", "ffi")).strip() == "webview2_fixed":
        runtime_errors = check_webview2_runtime(src, manifest)
        if runtime_errors:
            return report_webview2_runtime_errors(src, runtime_errors)

    # 清单声明了某个平台的库，包里就必须真的有这个文件；否则打出来的
    # .zbk 会「声明得比实际多」，安装后该平台必然不可用。
    missing = pack_common.missing_libraries(src, manifest, "kernel")
    if missing:
        return pack_common.report_missing(
            src, missing, MANIFEST_ENTRY,
            hint=("提示：独立内核包的库由插件内核目录装配而来，可先执行\n"
                  "  python tool/assemble_kernel_pkg.py\n"
                  "（它会从 example_plugins/lite_kernel/kernels 装配各平台产物；"
                  "缺少的平台需先用 tool/build_lite_kernel.sh 或 "
                  "tool\\build_lite_kernel.bat 构建，或直接取 CI 产物）"))

    count = write_zip(src, out)
    print(f"打包完成：{out}（{count} 个文件）")
    print(f"内核 id：{manifest['id']} · 类型：{manifest.get('type', 'ffi')}")
    return 0


def pack_demo(out):
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, MANIFEST_ENTRY), "w", encoding="utf-8") as fh:
            json.dump(DEMO_MANIFEST, fh, ensure_ascii=False, indent=2)

        # 占位原生库（内容为说明文本，仅用于验证安装与探测流程）
        placeholder = (
            "This is a placeholder native library generated by pack_kernel.py --demo.\n"
            "Replace it with a real kernel implementation before production use.\n"
        )
        for platform, rel in (
            ("windows", "bin/windows/kernel.dll"),
            ("linux", "bin/linux/libkernel.so"),
            ("android/arm64-v8a", "bin/android/arm64-v8a/libkernel.so"),
            ("android/armeabi-v7a", "bin/android/armeabi-v7a/libkernel.so"),
            ("android/x86_64", "bin/android/x86_64/libkernel.so"),
        ):
            path = os.path.join(tmp, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(f"# {platform}\n{placeholder}")

        with open(os.path.join(tmp, "README.md"), "w", encoding="utf-8") as fh:
            fh.write(
                "# 示例独立内核包\n\n"
                "本包由 `tool/pack_kernel.py --demo` 生成，仅用于验证「内核管理」页的\n"
                "安装 / 探测 / 切换 / 卸载流程，不包含真实的渲染实现。\n"
            )

        count = write_zip(tmp, out)

    print(f"示例内核包已生成：{out}（{count} 个文件）")
    print("可在应用内「设置 → 内核管理 → 安装」选择该文件进行验证。")
    return 0


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__.strip())
        return 1

    if args[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0

    if args[0] == "--demo":
        out = args[1] if len(args) > 1 else "zip-browser-kernel-demo.zbk"
        return pack_demo(out)

    src = os.path.abspath(args[0])
    if not os.path.isdir(src):
        print(f"目录不存在：{src}")
        return 1

    out = args[1] if len(args) > 1 else os.path.basename(src.rstrip(os.sep)) + ".zbk"
    return pack_dir(src, out)


if __name__ == "__main__":
    sys.exit(main())
