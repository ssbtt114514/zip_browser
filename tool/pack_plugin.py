#!/usr/bin/env python3
"""
将插件目录打包为可安装的 .zip（zip 内路径以插件目录为根）。
用法：python tool/pack_plugin.py <插件目录> [输出.zip]

打包前会校验：目录根部必须有 manifest.json，且清单 kernel.libraries
里声明的每个平台库文件都真实存在于目录内 —— 不一致直接拒绝打包。
"""
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack_common  # noqa: E402  （与打包器同目录的共用校验）

MANIFEST_ENTRY = "manifest.json"


def main():
    if len(sys.argv) < 2:
        print("用法：python tool/pack_plugin.py <插件目录> [输出.zip]")
        sys.exit(1)

    src = os.path.abspath(sys.argv[1])
    if not os.path.isdir(src):
        print(f"目录不存在：{src}")
        sys.exit(1)

    manifest_path = os.path.join(src, MANIFEST_ENTRY)
    if not os.path.isfile(manifest_path):
        print(f"插件目录根部未找到 {MANIFEST_ENTRY}：{src}")
        sys.exit(1)
    try:
        with open(manifest_path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"{MANIFEST_ENTRY} 解析失败：{exc}")
        sys.exit(1)

    missing = pack_common.missing_libraries(src, manifest, "plugin")
    if missing:
        sys.exit(pack_common.report_missing(
            src, missing, MANIFEST_ENTRY,
            hint=("提示：插件缺的是某个平台的内核库；先构建对应平台的产物：\n"
                  "  · Linux / Android：sh tool/build_lite_kernel.sh all"
                  "（需 Linux/macOS 主机 + NDK）\n"
                  "  · Windows：tool\\build_lite_kernel.bat\n"
                  "  · 或直接使用 CI（build-kernel 工作流）装配好的插件 zip")))

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
