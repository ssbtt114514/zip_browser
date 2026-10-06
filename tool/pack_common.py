#!/usr/bin/env python3
"""
打包器（pack_kernel.py / pack_plugin.py）共用的清单校验。

存在的理由：一个包里如果清单声明了某个平台的库，但该文件并不在包内，
那么宿主侧要么探测不到、要么加载失败，而打包过程本身却完全静默。
`build_kernel_pkg/zb_lite_kernel` 就曾出现这种情况 —— kernel.json 声明了
5 个平台，实际只装了 Windows 一个，打出来的 .zbk 里 linux / android
的库全部缺失。所以校验放在打包这一步：清单与实际不一致就直接拒绝打包。
"""
import os


def declared_libraries(manifest, kind):
    """收集清单声明的原生库。

    kind="kernel"：读 kernel.json 顶层的 libraries。
    kind="plugin"：读 manifest.json 里 kernel.libraries。

    返回 [(标签, 相对路径)]，标签形如 "windows"、"android/arm64-v8a"。
    """
    if not isinstance(manifest, dict):
        return []

    if kind == "kernel":
        libs = manifest.get("libraries")
    else:
        kernel = manifest.get("kernel")
        libs = kernel.get("libraries") if isinstance(kernel, dict) else None

    if not isinstance(libs, dict):
        return []

    out = []
    for platform, value in libs.items():
        if isinstance(value, str):
            out.append((str(platform), value))
        elif isinstance(value, dict):
            for abi, rel in value.items():
                if isinstance(rel, str):
                    out.append((f"{platform}/{abi}", rel))
    return out


def missing_libraries(src, manifest, kind):
    """返回清单声明但 [src] 目录内不存在的库：[(标签, 相对路径)]。"""
    missing = []
    for label, rel in declared_libraries(manifest, kind):
        path = os.path.join(src, rel.replace("/", os.sep))
        if not os.path.isfile(path):
            missing.append((label, rel))
    return missing


def report_missing(src, missing, name, hint=None):
    """打印统一的缺失报告，返回 1 供调用方直接当退出码使用。"""
    print(f"{name} 声明了以下原生库，但 {src} 内不存在：")
    for label, rel in missing:
        print(f"  - {label}: {rel}")
    print("拒绝打包：清单与实际内容不一致的包安装后必然不可用。")
    if hint:
        print(hint)
    return 1
