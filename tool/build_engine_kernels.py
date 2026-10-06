#!/usr/bin/env python3
"""
zb_engine_kernel 三平台编译脚本。

编译 chromium / gecko 两个引擎变体内核（复用 zb_lite_kernel 渲染实现），
并归位到内核包：
  Linux   -> build_kernel_pkg/<pkg>/bin/linux/lib<name>.so
  Windows -> build_kernel_pkg/<pkg>/bin/windows/<name>.dll
  Android -> build_kernel_pkg/<pkg>/bin/android/<abi>/lib<name>.so   (x3 ABI)

用法：
    python tool/build_engine_kernels.py          # 编译全部可用平台
    python tool/build_engine_kernels.py --platform linux
    python tool/build_engine_kernels.py --platform windows
    python tool/build_engine_kernels.py --platform android

依赖：
    Linux : gcc / clang
    Windows : x86_64-w64-mingw32-gcc（apt: gcc-mingw-w64-x86-64）
    Android: ANDROID_NDK 环境变量或常见 NDK 路径
"""
import argparse
import os
import shutil
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LITE_SRC = os.path.join(ROOT, "native_kernels", "zb_lite_kernel", "src")
LITE_INC = os.path.join(ROOT, "native_kernels", "zb_lite_kernel", "include")
ABI_INC = os.path.join(ROOT, "native_plugins", "zb_native_surface", "include")

OUT = os.path.join(ROOT, "build", "engine-kernel-out")

ENGINES = [
    {
        "name": "zb_chromium_kernel",
        "engine_id": "zb_chromium_kernel",
        "display": "Chromium 渲染内核",
        "hint": "zb_chromium_kernel - chromium engine (software raster, same ABI)",
        "pkg": "zb_chromium_kernel",
    },
    {
        "name": "zb_gecko_kernel",
        "engine_id": "zb_gecko_kernel",
        "display": "Gecko 渲染内核",
        "hint": "zb_gecko_kernel - gecko engine (software raster, same ABI)",
        "pkg": "zb_gecko_kernel",
    },
]

ANDROID_ABIS = ["arm64-v8a", "armeabi-v7a", "x86_64"]
NDK_TRIPLES = {
    "arm64-v8a": "aarch64-linux-android24",
    "armeabi-v7a": "armv7a-linux-androideabi24",
    "x86_64": "x86_64-linux-android24",
}

SOURCES = [
    "zb_lite_util.c",
    "zb_lite_json.c",
    "zb_lite_doc.c",
    "zb_lite_layout.c",
    "zb_lite_render.c",
    "zb_lite_kernel.c",
]


def find_ndk():
    cands = [
        os.environ.get("ANDROID_NDK", ""),
        os.path.join(os.environ.get("ANDROID_HOME", ""), "ndk"),
        os.path.expanduser("~/android-sdk/ndk"),
        "/home/user/android-sdk/ndk",
    ]
    for c in cands:
        if not c:
            continue
        if os.path.isdir(c):
            # 选版本号最大者
            vers = [v for v in os.listdir(c) if v[0].isdigit()]
            if vers:
                return os.path.join(c, sorted(vers)[-1])
    return None


def defines(e):
    return [
        f'-DZB_ENGINE_NAME="{e["engine_id"]}"',
        f'-DZB_ENGINE_DISPLAY_NAME="{e["display"]}"',
        f'-DZB_ENGINE_HINT="{e["hint"]}"',
    ]


def cc_cmd(cc, e, extra=None):
    cmd = [cc, "-shared", "-fPIC", "-O2", "-std=c99", "-Wall", "-Wextra"]
    # 与 zb_lite_kernel 的 CMake 一致：隐藏内部符号，仅导出 ZB_API 的 16 个符号
    cmd += ["-fvisibility=hidden"]
    cmd += ["-I", LITE_INC, "-I", ABI_INC]
    cmd += defines(e)
    cmd += [os.path.join(LITE_SRC, s) for s in SOURCES]
    if extra:
        cmd += extra
    return cmd


def run(cmd, tag):
    print(f"[{tag}] " + " ".join(cmd[:3]) + " ...")
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        print(p.stderr[-3000:])
        sys.exit(f"{tag} 编译失败")
    print(f"[{tag}] OK")


def build_linux():
    cc = shutil.which("gcc") or shutil.which("clang")
    if not cc:
        sys.exit("缺少 gcc/clang")
    for e in ENGINES:
        out_dir = os.path.join(OUT, "linux")
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, f"lib{e['name']}.so")
        run(cc_cmd(cc, e, ["-o", out]), f"linux/{e['name']}")


def build_windows():
    cc = shutil.which("x86_64-w64-mingw32-gcc")
    if not cc:
        sys.exit("缺少 mingw（apt install gcc-mingw-w64-x86-64）")
    for e in ENGINES:
        out_dir = os.path.join(OUT, "windows")
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, f"{e['name']}.dll")
        run(cc_cmd(cc, e, ["-o", out]), f"windows/{e['name']}")


def build_android():
    ndk = find_ndk()
    if not ndk:
        sys.exit("未找到 Android NDK")
    prebuilt = os.path.join(ndk, "toolchains", "llvm", "prebuilt", "linux-x86_64", "bin")
    for abi in ANDROID_ABIS:
        cc = os.path.join(prebuilt, NDK_TRIPLES[abi] + "-clang")
        if not os.path.exists(cc):
            sys.exit(f"缺少 {cc}")
        for e in ENGINES:
            out_dir = os.path.join(OUT, "android", abi)
            os.makedirs(out_dir, exist_ok=True)
            out = os.path.join(out_dir, f"lib{e['name']}.so")
            run(cc_cmd(cc, e, ["-o", out]), f"android/{abi}/{e['name']}")


def deploy():
    """把产物复制到内核包 bin/ 目录。"""
    def copy(src, dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        print(f"  -> {os.path.relpath(dst, ROOT)}")

    for e in ENGINES:
        pkg = os.path.join(ROOT, "build_kernel_pkg", e["pkg"], "bin")
        linux = os.path.join(OUT, "linux", f"lib{e['name']}.so")
        win = os.path.join(OUT, "windows", f"{e['name']}.dll")
        if os.path.exists(linux):
            copy(linux, os.path.join(pkg, "linux", f"lib{e['name']}.so"))
        if os.path.exists(win):
            copy(win, os.path.join(pkg, "windows", f"{e['name']}.dll"))
        for abi in ANDROID_ABIS:
            so = os.path.join(OUT, "android", abi, f"lib{e['name']}.so")
            if os.path.exists(so):
                copy(so, os.path.join(pkg, "android", abi, f"lib{e['name']}.so"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", choices=["linux", "windows", "android", "all"],
                    default="all")
    ap.add_argument("--no-deploy", action="store_true")
    args = ap.parse_args()

    if args.platform in ("linux", "all"):
        build_linux()
    if args.platform in ("windows", "all"):
        build_windows()
    if args.platform in ("android", "all"):
        build_android()

    if not args.no_deploy:
        print("归位产物到内核包 bin/：")
        deploy()
    print("完成。")


if __name__ == "__main__":
    main()
