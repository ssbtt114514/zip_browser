#!/usr/bin/env python3
"""
把 WebView2 固定版本运行时装配进独立内核包目录
`build_kernel_pkg/zb_chromium_kernel/`（供 tool/pack_kernel.py 打包成 .zbk）。

用法：
    # 常规：把 --runtime 目录整体装成 <包目录>/runtime
    python tool/assemble_chromium_kernel.py --runtime /tmp/wv2

    # 只检查，不落盘
    python tool/assemble_chromium_kernel.py --runtime /tmp/wv2 --dry-run

    # 手工钉住版本号（自动探测失败时）
    python tool/assemble_chromium_kernel.py --runtime /tmp/wv2 --version 154.0.4258.62

    # 生成目录骨架但清空 runtime（准备提交/查看清单模板）
    python tool/assemble_chromium_kernel.py --clean

装配内容：
    build_kernel_pkg/zb_chromium_kernel/
    ├── kernel.json          由本脚本按真实运行时版本改写 version / engine_version
    ├── README.md            说明与许可（随包分发）
    └── runtime/             ← --runtime 目录整体复制（内含 msedgewebview2.exe）

幂等性：每次装配先整体删除 runtime/ 再复制，重复执行不会叠加旧文件或残留文件。
版本来源优先级：msedgewebview2.exe 的 PE FileVersion > ProductVersion >
                --version > 目录/包名里的三段以上数字（如 .../154.0.4258.62/...）。

退出码：0 成功；1 runtime 缺失/不合法；2 参数错误。
"""
import argparse
import json
import os
import re
import shutil
import struct
import sys

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

RUNTIME_EXE = "msedgewebview2.exe"

# 宿主 WebviewController.initializeEnvironment(browserExePath: runtimeDir) 真正
# 依赖的是 msedgewebview2.exe；下面这些只是「缺了就明显是坏包」的体检项。
IMPORTANT_FILES = [
    "msedgewebview2.exe",   # 宿主启动固定版本内核的入口，必需
    "resources.pak",        # Blink 资源
    "icudtl.dat",           # ICU 数据（非 ASCII 页面必需）
    "Locales/en-US.pak",    # 本地化
    "msedge_elf.dll",       # Edge 主库
    "vk_swiftshader.dll",   # 无 GPU 环境的软件渲染回退
]

# 宿主支持的 manifest_version / abi_version（见 lib/core/kernel/kernel_manifest.dart
# 与 lib/core/kernel/kernel_package.dart 的 kSupportedKernelAbiVersion）。
MANIFEST_VERSION = 1
ABI_VERSION = 1

DEFAULT_PKG_DIR = os.path.join("build_kernel_pkg", "zb_chromium_kernel")
DEFAULT_MANIFEST = os.path.join(DEFAULT_PKG_DIR, "kernel.json")

# 仅这些字段由装配脚本按真实运行时改写；其余字段是人工维护的包身份，
# 不被脚本覆写（幂等：重复执行只会把同样的值写回去）。
VERSION_FIELDS = ("version", "engine_version")


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def human(n):
    return f"{n / 1048576:.1f} MiB"


# --------------------------------------------------------------------------
# 版本探测
# --------------------------------------------------------------------------
def pe_value_after(block, key, search_from):
    """取 block 里 key 之后那个「以 NUL 结尾的 UTF-16LE 字符串」。

    不能用固定的 4/6 字节对齐去找值：真实 msedgewebview2.exe 的版本块里，
    FileVersion 的键结束（block 偏移 344）后还要跳过 4 字节才是值（值在 348），
    而 ProductVersion / OriginalFilename 只跳 2 字节。硬编码任一规则都会读错其中一个。
    这里改成「跳过所有 NUL 填充，再从第一个非 NUL 字符读到下一个 NUL」，对两种排布
    都成立，而且读出来的值必须是全部可打印字符（否则视为读不出）。
    """
    kb = key.encode("utf-16le")
    pos = search_from
    while True:
        idx = block.find(kb, pos)
        if idx < 0:
            return None
        pos = idx + len(kb)
        # 先越过键自身的 NUL 终止符，再越过对齐填充的 NUL，值从第一个非 NUL 字符开始。
        i = pos + 2
        while i + 1 < len(block) and block[i] == 0 and block[i + 1] == 0:
            i += 2
            if i - pos > 8:  # 填充不可能这么长，说明这个键后面没有值
                break
        if i - pos > 8:
            continue
        end = i
        while end + 1 < len(block) and not (block[end] == 0 and block[end + 1] == 0):
            end += 2
        val = block[i:end].decode("utf-16le", "replace")
        if val and all(ch.isprintable() for ch in val):
            return val


def pe_version_info(pe_path):
    """从 PE 的 VS_VERSIONINFO 里读 FileVersion / ProductVersion（仅标准库）。

    做法：定位 UTF-16LE 的 "VS_VERSION_INFO" 键，用它前面的 wLength 圈出整个版本资源
    块，再在这个块里找 "FileVersion" 键——值与键同处一块，因此**必须**用「相对块起点」
    的偏移做 4 字节对齐（用相对文件的偏移算会整体错位，读出来的值会从第二个字符开始，
    例如 OriginalFilename 变成 riginalFilename）。本函数只接受全部字符可打印的值，
    错位产生的乱码会被丢掉，从而宁可判"读不出"也不写入错误版本号。
    """
    try:
        with open(pe_path, "rb") as fh:
            data = fh.read()
    except OSError:
        return {}
    if len(data) < 0x40 or data[:2] != b"MZ":
        return {}
    try:
        pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    except struct.error:
        return {}
    if data[pe_off:pe_off + 4] != b"PE\x00\x00":
        return {}

    marker = "VS_VERSION_INFO".encode("utf-16le")
    block = None
    for m in re.finditer(re.escape(marker), data):
        start = m.start() - 6  # wLength(2) + wValueLength(2) + wType(2)
        if start < 0:
            continue
        wlen = int.from_bytes(data[start:start + 2], "little")
        if 128 < wlen < 65536 and start + wlen <= len(data):
            block = data[start:start + wlen]
            break
    if block is None:
        return {}

    # 只在 StringFileInfo 之后找键，避免撞上别处同名字符串；但偏移一律相对 block 计算，
    # 所以搜索起点要换算回 block 坐标。
    sfi = block.find("StringFileInfo".encode("utf-16le"))
    search_from = sfi if sfi >= 0 else 0

    out = {}
    for key in ("FileVersion", "ProductVersion", "OriginalFilename",
                "FileDescription", "CompanyName"):
        val = pe_value_after(block, key, search_from)
        if val:
            out[key] = val
    return out


def version_from_path(path):
    """从路径里认出一个 ≥3 段的版本号（如 .../154.0.4258.62/...）。"""
    found = []
    for part in re.split(r"[\\/]", os.path.abspath(path)):
        m = re.search(r"(\d{2,5}\.\d+\.\d+(?:\.\d+)*)", part)
        if m:
            found.append(m.group(1))
    return found[-1] if found else None


def detect_version(runtime_dir, override=None):
    """返回 (版本字符串, 来源说明)。全部失败返回 (None, 原因)。"""
    if override:
        return override, "--version 手工指定"

    exe = os.path.join(runtime_dir, RUNTIME_EXE)
    info = pe_version_info(exe)
    if info.get("FileVersion"):
        return info["FileVersion"], f"{RUNTIME_EXE} 的 PE FileVersion"
    if info.get("ProductVersion"):
        return info["ProductVersion"], f"{RUNTIME_EXE} 的 PE ProductVersion"

    v = version_from_path(runtime_dir)
    if v:
        return v, "运行时的目录名/路径"

    return None, (f"既读不出 {RUNTIME_EXE} 的 PE 版本号，路径里也没有版本号；"
                  f"请用 --version 指定")


# --------------------------------------------------------------------------
# 体检 / 复制
# --------------------------------------------------------------------------
def survey(runtime_dir):
    """返回 (文件数, 总字节, [顶层条目...])。"""
    files = 0
    total = 0
    tops = set()
    for root, dirs, names in os.walk(runtime_dir):
        rel = os.path.relpath(root, runtime_dir)
        if rel == ".":
            tops.update(d for d in dirs)
            tops.update(names)
        for f in names:
            full = os.path.join(root, f)
            files += 1
            try:
                total += os.path.getsize(full)
            except OSError:
                pass
    return files, total, sorted(tops)


def validate_runtime(runtime_dir):
    """返回错误字符串列表（空表示可用）。"""
    errors = []
    if not os.path.isdir(runtime_dir):
        return [f"--runtime 目录不存在：{runtime_dir}"]

    exe = os.path.join(runtime_dir, RUNTIME_EXE)
    if not os.path.isfile(exe):
        tops = sorted(os.listdir(runtime_dir))[:30]
        errors.append(
            f"{runtime_dir} 内没有 {RUNTIME_EXE}。\n"
            "  宿主的 fixedRuntimeDir 是直接传给 "
            "WebviewController.initializeEnvironment(browserExePath: …) 的，\n"
            "  目录里必须是运行时的「根」（msedgewebview2.exe 与 resources.pak、"
            "Locales/ 等同级）。\n"
            f"  当前顶层条目（前 {len(tops)} 个）：{', '.join(tops) or '(空目录)'}\n"
            "  若你解包出来的是一层壳目录（如 contentFiles/any/any/WebView2/），"
            "请把 --runtime 指到最内层那个含 exe 的目录，"
            "或改用 python tool/fetch_webview2_runtime.py（它会自动定位）。"
        )
        return errors

    if os.path.getsize(exe) == 0:
        errors.append(f"{exe} 是 0 字节文件，不是可用的运行时")

    return errors


def copy_runtime(src, dst):
    """整体复制 src -> dst（先删 dst，保证幂等）。返回 (文件数, 字节数)。"""
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    elif os.path.exists(dst):
        os.remove(dst)

    files = 0
    total = 0
    for root, _dirs, names in os.walk(src):
        rel = os.path.relpath(root, src)
        target_root = dst if rel == "." else os.path.join(dst, rel)
        os.makedirs(target_root, exist_ok=True)
        for f in names:
            s = os.path.join(root, f)
            t = os.path.join(target_root, f)
            shutil.copy2(s, t)
            files += 1
            try:
                total += os.path.getsize(t)
            except OSError:
                pass
    return files, total


# --------------------------------------------------------------------------
# kernel.json
# --------------------------------------------------------------------------
def load_manifest(path):
    if not os.path.isfile(path):
        return None, f"清单文件不存在：{path}"
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        return None, f"{path} 解析失败：{exc}"
    if not isinstance(data, dict):
        return None, f"{path} 顶层必须是 JSON 对象"
    return data, None


def manifest_mismatches(m):
    """装配后自检：清单是否与「固定版本运行时」这个事实一致。"""
    bad = []
    if m.get("type") != "webview2_fixed":
        bad.append(f'"type" 应为 webview2_fixed，实际 {m.get("type")!r}')
    if not m.get("runtime_dir"):
        bad.append('"runtime_dir" 不能为空（webview2_fixed 靠它定位运行时）')
    if m.get("libraries"):
        bad.append('"libraries" 应为空对象（webview2_fixed 不用 FFI 库）')
    if m.get("manifest_version") != MANIFEST_VERSION:
        bad.append(f'"manifest_version" 应为 {MANIFEST_VERSION}')
    if m.get("abi_version") != ABI_VERSION:
        bad.append(f'"abi_version" 应为 {ABI_VERSION}')
    if m.get("engine") != "chromium":
        bad.append(f'"engine" 应为 chromium，实际 {m.get("engine")!r}')
    return bad


def write_manifest(path, manifest, version, engine_version, source):
    updated = dict(manifest)
    updated["version"] = version
    updated["engine_version"] = engine_version
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(updated, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    changes = [k for k in VERSION_FIELDS if manifest.get(k) != updated.get(k)]
    if changes:
        for k in changes:
            print(f"  改写 {k}: {manifest.get(k)!r} -> {updated.get(k)!r}（来源：{source}）")
    else:
        print(f"  version / engine_version 已是 {version}，无需改写（幂等）")


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def parse_args(argv):
    ap = argparse.ArgumentParser(
        description="把 WebView2 固定版本运行时装配进 zb_chromium_kernel 包目录",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--runtime", default=None,
                    help="WebView2 运行时目录（内含 msedgewebview2.exe）")
    ap.add_argument("--pkg-dir", default=None,
                    help=f"内核包目录（默认 {DEFAULT_PKG_DIR}）")
    ap.add_argument("--version", default=None, help="手工指定版本号（覆盖自动探测）")
    ap.add_argument("--dry-run", action="store_true", help="只检查并打印，不写盘")
    ap.add_argument("--clean", action="store_true",
                    help="清空包目录内的 runtime/（生成骨架，不装配运行时）")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)

    root = repo_root()
    pkg_dir = os.path.abspath(args.pkg_dir) if args.pkg_dir \
        else os.path.join(root, DEFAULT_PKG_DIR)
    manifest_path = os.path.join(pkg_dir, "kernel.json")
    runtime_dst = os.path.join(pkg_dir, "runtime")

    print("== 装配 Chromium 固定版本内核包 ==")
    print(f"  包目录  ：{pkg_dir}")
    print(f"  清单    ：{manifest_path}")
    print(f"  运行时落点：{runtime_dst}")

    if not os.path.isdir(pkg_dir):
        print(f"\n[失败] 包目录不存在：{pkg_dir}\n"
              "  该目录应随仓库提供（kernel.json / README.md）；"
              "若刚克隆仓库缺失，请先 git checkout 该目录。", file=sys.stderr)
        return 2

    manifest, err = load_manifest(manifest_path)
    if manifest is None:
        print(f"\n[失败] {err}", file=sys.stderr)
        return 2

    # ---- --clean：清空 runtime，生成骨架 ----
    if args.clean:
        if os.path.isdir(runtime_dst):
            if args.dry_run:
                print(f"\n--dry-run：将删除 {runtime_dst}")
            else:
                shutil.rmtree(runtime_dst)
                print(f"\n已清空 {runtime_dst}")
        else:
            print(f"\n{runtime_dst} 本来就不存在，无需清理")
        return 0

    if not args.runtime:
        print("\n[失败] 需要 --runtime <WebView2 运行时目录>（或用 --clean 只清空）",
              file=sys.stderr)
        return 2

    runtime_src = os.path.abspath(args.runtime)

    # ---- 体检 ----
    errors = validate_runtime(runtime_src)
    if errors:
        print("\n[失败] 运行时不可用：", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    files, total, tops = survey(runtime_src)
    print(f"\n== 源运行时体检（{runtime_src}）==")
    print(f"  文件数：{files}")
    print(f"  体积  ：{total} 字节（{human(total)}）")
    print(f"  顶层条目（{len(tops)}）：{', '.join(tops[:24])}"
          f"{' …' if len(tops) > 24 else ''}")
    for rel in IMPORTANT_FILES:
        p = os.path.join(runtime_src, rel)
        ok = os.path.isfile(p)
        size = os.path.getsize(p) if ok else 0
        flag = "OK " if ok else ("!! " if rel == RUNTIME_EXE else "-- ")
        print(f"  [{flag}] {rel}{f'（{size} 字节）' if ok else '（缺失）'}")

    version, source = detect_version(runtime_src, args.version)
    if version:
        print(f"\n  运行时版本：{version}（来源：{source}）")
    else:
        print(f"\n  ! 无法确定运行时版本：{source}", file=sys.stderr)
        print("  用 --version <版本号> 重跑即可。", file=sys.stderr)
        return 1

    mismatch = manifest_mismatches(manifest)
    if mismatch:
        print("\n[失败] kernel.json 与固定版本运行时的语义不一致：", file=sys.stderr)
        for m in mismatch:
            print(f"  - {m}", file=sys.stderr)
        return 1

    if args.dry_run:
        print("\n--dry-run：不写盘。将执行：")
        print(f"  1) 删除并重建 {runtime_dst}")
        print(f"  2) 复制 {files} 个文件 / {human(total)}")
        print(f"  3) 改写 {manifest_path} 的 version=engine_version={version}")
        return 0

    # ---- 复制（先删后建 = 幂等）----
    print(f"\n== 复制运行时 -> {runtime_dst} ==")
    if os.path.isdir(runtime_dst):
        print(f"  删除既有 {runtime_dst}（幂等：不叠加旧文件）")
    copied, copied_bytes = copy_runtime(runtime_src, runtime_dst)
    print(f"  已复制 {copied} 个文件，{copied_bytes} 字节（{human(copied_bytes)}）")

    # ---- 改写清单版本 ----
    print("\n== 改写 kernel.json 版本字段 ==")
    write_manifest(manifest_path, manifest, version, version, source)

    # ---- 装配结果 ----
    dst_files, dst_bytes, dst_tops = survey(runtime_dst)
    print("\n== 装配结果 ==")
    print(f"  包目录   ：{pkg_dir}")
    print(f"  runtime  ：{dst_files} 个文件，{dst_bytes} 字节（{human(dst_bytes)}）")
    print(f"  顶层条目 ：{', '.join(dst_tops[:20])}{' …' if len(dst_tops) > 20 else ''}")
    for rel in IMPORTANT_FILES:
        p = os.path.join(runtime_dst, rel)
        ok = os.path.isfile(p)
        size = os.path.getsize(p) if ok else 0
        flag = "OK " if ok else ("!! " if rel == RUNTIME_EXE else "-- ")
        print(f"  [{flag}] runtime/{rel}{f'（{size} 字节）' if ok else '（缺失）'}")

    if copied != dst_files or copied_bytes != dst_bytes:
        print(f"\n[失败] 复制结果与源不一致（源 {files}/{total}，目标 {dst_files}/{dst_bytes}），"
              "可能磁盘空间不足或被安全软件拦截", file=sys.stderr)
        return 1

    final, err = load_manifest(manifest_path)
    if final is None:
        print(f"\n[失败] 改写后清单无法读回：{err}", file=sys.stderr)
        return 1
    print(f"\n  清单版本：{final.get('version')} · "
          f"引擎版本：{final.get('engine_version')} · "
          f"type：{final.get('type')} · runtime_dir：{final.get('runtime_dir')}")

    print("\n下一步（打包 + 用宿主安装器校验）：")
    print(f"  python tool/pack_kernel.py {os.path.relpath(pkg_dir, root)} "
          "zb_chromium_kernel.zbk")
    print("  dart run tool/verify_packages.dart "
          "--strict-runtime zb_chromium_kernel.zbk")
    return 0


if __name__ == "__main__":
    sys.exit(main())
