#!/usr/bin/env python3
"""
将插件目录打包为可安装的 .zip（zip 内路径以插件目录为根）。
用法：python tool/pack_plugin.py <插件目录> [输出.zip]
"""
import os
import sys
import zipfile


def main():
    if len(sys.argv) < 2:
        print("用法：python tool/pack_plugin.py <插件目录> [输出.zip]")
        sys.exit(1)

    src = os.path.abspath(sys.argv[1])
    if not os.path.isdir(src):
        print(f"目录不存在：{src}")
        sys.exit(1)

    out = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(src) + ".zip"
    if os.path.abspath(out) == os.path.abspath(src):
        out = os.path.basename(src) + ".zip"

    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(src):
            for f in files:
                if f in (".DS_Store",) or f.endswith("~"):
                    continue
                full = os.path.join(root, f)
                arc = os.path.relpath(full, src).replace(os.sep, "/")
                z.write(full, arc)
                count += 1

    print(f"打包完成：{out}（{count} 个文件）")


if __name__ == "__main__":
    main()
