#!/usr/bin/env python3
"""
把插件目录里已构建好的各平台内核库，装配进独立内核包（.zbk）源目录。

为什么需要这一步：独立内核包的 kernel.json 声明的是
`bin/<平台>/[<abi>/]<文件名>`，而插件（`tool/build_lite_kernel.*` 的产物）
是按 `kernels/<同样的平台/abi 结构>/<文件名>` 存放的，两者只差一个前缀。
CI 的 build-kernel 工作流在 package job 里做的就是这件事；本脚本让本地
也能一键装配，避免手工拷贝漏掉平台 —— 漏掉的结果就是打出一个
「清单声明了、包里却没有」的 .zbk（宿主侧该平台必然不可用）。

用法：
    # 默认：example_plugins/lite_kernel/kernels -> build_kernel_pkg/zb_lite_kernel/bin
    python tool/assemble_kernel_pkg.py

    # 只看会做什么、缺哪些产物，不写文件
    python tool/assemble_kernel_pkg.py --check

    python tool/assemble_kernel_pkg.py \\
        --from example_plugins/lite_kernel/kernels \\
        --pkg build_kernel_pkg/zb_lite_kernel
"""
import argparse
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack_common  # noqa: E402  （与打包器同目录的共用校验）

MANIFEST_ENTRY = "kernel.json"
BIN_PREFIX = "bin/"


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--pkg", default="build_kernel_pkg/zb_lite_kernel",
                        help="独立内核包源目录（含 kernel.json）")
    parser.add_argument("--from", dest="src",
                        default="example_plugins/lite_kernel/kernels",
                        help="已构建好的插件内核库目录")
    parser.add_argument("--check", action="store_true",
                        help="只报告装配计划与缺失产物，不写文件")
    args = parser.parse_args()

    manifest_path = os.path.join(args.pkg, MANIFEST_ENTRY)
    if not os.path.isfile(manifest_path):
        print(f"未找到内核清单：{manifest_path}")
        return 1
    with open(manifest_path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)

    libs = pack_common.declared_libraries(manifest, "kernel")
    if not libs:
        print(f"{MANIFEST_ENTRY} 未声明任何 libraries，无需装配")
        return 1

    print(f"装配源：{args.src}")
    print(f"装配目标：{args.pkg}"
          f"{'（--check 只报告，不写文件）' if args.check else ''}")

    copied, absent = [], []
    for label, rel in libs:
        # 清单里的 bin/<平台>/... 去掉 bin/ 前缀，就是插件目录里的相对结构
        sub = rel[len(BIN_PREFIX):] if rel.startswith(BIN_PREFIX) else rel
        src_file = os.path.join(args.src, sub.replace("/", os.sep))
        dst_file = os.path.join(args.pkg, rel.replace("/", os.sep))
        if not os.path.isfile(src_file):
            absent.append((label, src_file))
            continue
        if not args.check:
            os.makedirs(os.path.dirname(dst_file), exist_ok=True)
            shutil.copy2(src_file, dst_file)
        copied.append((label, rel, os.path.getsize(src_file)))

    for label, rel, size in copied:
        print(f"  [{'将装配' if args.check else '已装配'}] {label}: "
              f"{rel}（{size} 字节）")

    if absent:
        print("")
        print(f"以下平台在 {args.src} 内没有产物，无法装配：")
        for label, src_file in absent:
            print(f"  - {label}: 期望 {src_file}")
        print("先在对应平台构建，或用 CI（.github/workflows/build-kernel.yml）的产物：")
        print("  · Linux / Android：sh tool/build_lite_kernel.sh all（需 Linux/macOS 主机）")
        print("  · Windows：tool\\build_lite_kernel.bat")
        return 1

    print("")
    print(f"装配完成：{len(copied)}/{len(libs)} 个平台")
    print(f"下一步：python tool/pack_kernel.py {args.pkg} zip_browser_kernel_lite.zbk")
    return 0


if __name__ == "__main__":
    sys.exit(main())
