#!/usr/bin/env python3
"""
把 Flutter Linux 构建产物（bundle/）打包成 Debian 软件包（.deb）。

用法：
    python tool/pack_deb.py <bundle目录> <输出.deb> --version 0.7.0 \
        --arch amd64|arm64

deb 布局：
    /usr/lib/zip-browser/     bundle 内容（可执行文件、lib、data）
    /usr/bin/zip-browser      → 符号链接
    /usr/share/applications/zip-browser.desktop
    /usr/share/icons/hicolor/1024x1024/apps/zip-browser.png

依赖 dpkg-deb（Ubuntu 预装）。
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

APP_BIN = "zip_browser"
LIB_DIR = "usr/lib/zip-browser"
ICON_SRC = "assets/icon/app_icon_1024.png"

CONTROL_TEMPLATE = """Package: zip-browser
Version: {version}
Architecture: {arch}
Maintainer: ssbtt114514 <ssbtt114514@users.noreply.github.com>
Installed-Size: {size}
Depends: libgtk-3-0, libx11-6, libxext6, libxi6, libxrender1, libglib2.0-0, libstdc++6
Section: web
Priority: optional
Homepage: https://github.com/ssbtt114514/zip_browser
Description: Zip plugin extensible multi-platform browser framework
 A browser framework that can be extended with zip plugins and browser
 kernels. Supports Android, Windows and Linux (macOS planned).
"""

DESKTOP_TEMPLATE = """[Desktop Entry]
Name=Zip Browser
Comment=Zip plugin extensible browser framework
Exec=/usr/lib/zip-browser/{bin} %U
Icon=zip-browser
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bundle")
    ap.add_argument("out")
    ap.add_argument("--version", required=True)
    ap.add_argument("--arch", required=True, choices=("amd64", "arm64"))
    args = ap.parse_args()

    bundle = os.path.abspath(args.bundle)
    if not os.path.isdir(bundle):
        print(f"错误：未找到 bundle 目录：{bundle}")
        return 1
    exe = os.path.join(bundle, APP_BIN)
    if not os.path.isfile(exe) or not os.access(exe, os.X_OK):
        print(f"错误：bundle 内缺少可执行文件 {APP_BIN}")
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        root = os.path.join(tmp, "zip-browser")
        lib = os.path.join(root, LIB_DIR)
        os.makedirs(os.path.join(root, "DEBIAN"), exist_ok=True)
        os.makedirs(os.path.join(root, "usr/bin"), exist_ok=True)
        os.makedirs(os.path.join(root, "usr/share/applications"), exist_ok=True)
        os.makedirs(os.path.join(root, "usr/share/icons/hicolor/1024x1024/apps"),
                    exist_ok=True)

        # bundle 内容 → /usr/lib/zip-browser/
        shutil.copytree(bundle, lib, dirs_exist_ok=True)

        # /usr/bin/zip-browser → 符号链接
        os.symlink(os.path.join("/usr", "lib", "zip-browser", APP_BIN),
                   os.path.join(root, "usr/bin", APP_BIN))

        # desktop 条目
        with open(os.path.join(root, "usr/share/applications",
                               "zip-browser.desktop"), "w") as fh:
            fh.write(DESKTOP_TEMPLATE.format(bin=APP_BIN))

        # 图标（优先仓库内置 SVG 渲染的 PNG；缺失时跳过，desktop 仍有效）
        if os.path.isfile(ICON_SRC):
            shutil.copy(ICON_SRC, os.path.join(
                root, "usr/share/icons/hicolor/1024x1024/apps/zip-browser.png"))

        # 体积（KB，向上取整）
        total = sum(
            os.path.getsize(os.path.join(dp, f))
            for dp, _, fs in os.walk(lib) for f in fs
        )
        with open(os.path.join(root, "DEBIAN/control"), "w") as fh:
            fh.write(CONTROL_TEMPLATE.format(
                version=args.version, arch=args.arch,
                size=(total + 1023) // 1024))

        out = os.path.abspath(args.out)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        res = subprocess.run(
            ["dpkg-deb", "--build", "--root-owner-group", root, out],
            capture_output=True, text=True)
        if res.returncode != 0:
            print("dpkg-deb 失败：")
            print(res.stderr)
            return 1

    print(f"deb 打包完成：{out}（{os.path.getsize(out) / 1024 / 1024:.1f} MB, "
          f"{args.arch}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
