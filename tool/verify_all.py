#!/usr/bin/env python3
"""本地一键验证：把 CI 里能离线跑的关键检查在本地复现一遍。

只依赖 Python 标准库；缺少某项工具链时该项标记 SKIP 而不是失败，
方便在没有 NDK / VS / Flutter 的机器上也能跑。

用法：
    python tool/verify_all.py            # 全部检查
    python tool/verify_all.py --list     # 只列出会执行哪些检查

Flutter 不在 PATH 时，可用环境变量指定：
    set FLUTTER_BIN=D:\\path\\to\\flutter\\bin\\flutter.bat
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LITE_DIR = os.path.join(ROOT, "native_kernels", "zb_lite_kernel")
INCLUDE_DIR = os.path.join(ROOT, "native_plugins", "zb_native_surface", "include")
LITE_PLUGIN = os.path.join(ROOT, "example_plugins", "lite_kernel")
LITE_ZBK = os.path.join(ROOT, "build_kernel_pkg", "zb_lite_kernel")

ABI_SYMBOLS = [
    "zb_abi_version", "zb_kernel_create", "zb_kernel_destroy",
    "zb_kernel_name", "zb_kernel_version", "zb_kernel_load_url",
    "zb_kernel_go_back", "zb_kernel_go_forward", "zb_kernel_reload",
    "zb_kernel_eval_js", "zb_kernel_current_url", "zb_kernel_title",
    "zb_kernel_attach_surface", "zb_kernel_tick",
    "zb_kernel_dispatch_from_host", "zb_free_ptr",
]

# 工作流里出现的这些路径是"构建产物"或"工具生成的模板文件"，本地不存在是正常的。
# 其中 lib/<abi>/… 是 Android APK 内部路径、lib/libflutter* 是 Linux/macOS
# bundle 内部路径 —— 它们是**包内**路径，不是仓库文件，工作流里的断言字符串
# 会被本检查的正则误当成仓库路径（build-android-apk / build-linux 就出现过）。
PATH_CHECK_SKIP = (
    "/kernels/",
    "/bin/",
    "test/widget_test.dart",
    "/lib/arm64-v8a/",
    "/lib/armeabi-v7a/",
    "/lib/x86_64/",
    "/lib/libflutter",
)

results = []


def record(name, status, detail=""):
    results.append((name, status, detail))
    print(f"[{status}] {name}" + (f" —— {detail}" if detail else ""))


def run(cmd, cwd=None):
    """统一用 UTF-8 解码并容忍乱码，避免中文输出触发平台编码异常。"""
    return subprocess.run(
        cmd, cwd=cwd or ROOT, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )


def find_gcc():
    for cand in ("gcc", "clang"):
        exe = shutil.which(cand)
        if exe:
            return exe
    # Windows 上常见但不在 PATH 里的 MinGW
    for cand in (r"C:\msys64\ucrt64\bin\gcc.exe", r"C:\msys64\mingw64\bin\gcc.exe"):
        if os.path.isfile(cand):
            return cand
    return None


def find_flutter():
    env = os.environ.get("FLUTTER_BIN")
    if env and os.path.isfile(env):
        return env
    exe = shutil.which("flutter")
    if exe:
        return exe
    # 仓库同级目录下的便携 SDK（本仓库开发时的常见布局）
    parent = os.path.dirname(ROOT)
    for rel in ("flutter/bin/flutter.bat", ".tooling/flutter/bin/flutter.bat",
                "flutter/bin/flutter", ".tooling/flutter/bin/flutter"):
        cand = os.path.join(parent, rel.replace("/", os.sep))
        if os.path.isfile(cand):
            return cand
    return None


def check_kernel_selftest():
    """编译内核 + 自检程序并运行（等价于 CI 的 selftest job）。"""
    cc = find_gcc()
    if not cc:
        record("内核编译 + 端到端自检", "SKIP", "未找到 C 编译器（gcc/clang）")
        return
    srcs = sorted(glob.glob(os.path.join(LITE_DIR, "src", "*.c")))
    test_src = os.path.join(LITE_DIR, "tests", "zb_lite_kernel_selftest.c")
    if not srcs or not os.path.isfile(test_src):
        record("内核编译 + 端到端自检", "FAIL", "缺少内核源码或自检程序")
        return

    out = os.path.join(tempfile.gettempdir(),
                       "zb_lite_selftest" + (".exe" if os.name == "nt" else ""))
    built = run([cc, "-std=c99", "-Wall", "-Wextra", "-O2",
                 "-I", INCLUDE_DIR, "-I", os.path.join(LITE_DIR, "include"),
                 *srcs, test_src, "-o", out])
    if built.returncode != 0:
        record("内核编译 + 端到端自检", "FAIL",
               ("编译失败：" + (built.stderr or built.stdout)).strip()[:400])
        return
    warnings = [l for l in (built.stderr or "").splitlines() if "warning:" in l]
    record("内核编译（-Wall -Wextra）", "PASS",
           f"{len(srcs)} 个源文件，{len(warnings)} 条警告")

    ran = run([out])
    stdout = ran.stdout or ""
    summary = next((l.strip() for l in reversed(stdout.splitlines())
                    if "检查" in l or "SELFTEST" in l), "")
    if ran.returncode == 0 and "SELFTEST OK" in stdout:
        record("内核端到端自检", "PASS", summary)
    else:
        record("内核端到端自检", "FAIL",
               f"退出码 {ran.returncode}；{summary or (ran.stderr or '')[:200]}")


def check_dll_symbols():
    """预编译 DLL 是否为真实 PE 且导出全部 16 个 ABI 符号。"""
    dll = os.path.join(LITE_PLUGIN, "kernels", "windows", "zb_lite_kernel.dll")
    if not os.path.isfile(dll):
        record("预编译 DLL 的 16 个 ABI 导出符号", "SKIP", "未找到预编译 Windows DLL")
        return
    with open(dll, "rb") as fh:
        data = fh.read()
    if data[:2] != b"MZ":
        record("预编译 DLL 的 16 个 ABI 导出符号", "FAIL", "不是有效的 PE 文件")
        return
    missing = [s for s in ABI_SYMBOLS if s.encode() not in data]
    if missing:
        record("预编译 DLL 的 16 个 ABI 导出符号", "FAIL",
               f"缺少：{', '.join(missing)}")
    else:
        record("预编译 DLL 的 16 个 ABI 导出符号", "PASS",
               f"16/16（{len(data) // 1024} KB）")


def _declared_artifacts(manifest):
    """兼容两种清单结构：独立内核包的顶层 libraries、插件包的 kernel.libraries。"""
    libs = manifest.get("libraries")
    if not isinstance(libs, dict):
        kernel = manifest.get("kernel")
        libs = kernel.get("libraries") if isinstance(kernel, dict) else None
    if not isinstance(libs, dict):
        return []
    out = []
    for platform, value in libs.items():
        if isinstance(value, str):
            out.append((platform, value))
        elif isinstance(value, dict):
            for abi, rel in value.items():
                out.append((f"{platform}/{abi}", rel))
    return out


def check_manifest_files():
    """manifest / kernel.json 声明的产物路径与磁盘一致（CI package job 的等价物）。"""
    for label, root, entry in (
        ("插件包 lite_kernel", LITE_PLUGIN, "manifest.json"),
        ("独立内核包 zb_lite_kernel", LITE_ZBK, "kernel.json"),
    ):
        path = os.path.join(root, entry)
        if not os.path.isfile(path):
            record(f"{label} 清单", "FAIL", f"缺少 {entry}")
            continue
        with open(path, encoding="utf-8") as fh:
            manifest = json.load(fh)
        declared = _declared_artifacts(manifest)
        if not declared:
            record(f"{label} 清单", "FAIL", "未声明任何平台产物")
            continue
        missing = [f"{p}:{rel}" for p, rel in declared
                   if not os.path.isfile(os.path.join(root, rel.replace("/", os.sep)))]
        record(f"{label} 清单", "PASS",
               f"声明 {len(declared)} 个产物，已随包提供 "
               f"{len(declared) - len(missing)} 个，待构建 {len(missing)} 个")


def check_workflow_yaml():
    try:
        import yaml  # noqa: PLC0415
    except ImportError:
        record("工作流 YAML 校验", "SKIP", "未安装 PyYAML")
        return
    files = sorted(glob.glob(os.path.join(ROOT, ".github", "workflows", "*.yml")))
    if not files:
        record("工作流 YAML 校验", "SKIP", "没有工作流文件")
        return
    problems, jobs_total = [], 0
    for path in files:
        try:
            with open(path, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except Exception as exc:  # noqa: BLE001
            problems.append(f"{os.path.basename(path)}: {exc}")
            continue
        jobs = doc.get("jobs") or {}
        jobs_total += len(jobs)
        for name, job in jobs.items():
            if not job.get("steps"):
                problems.append(f"{os.path.basename(path)}/{name}: 没有步骤")
    if problems:
        record("工作流 YAML 校验", "FAIL", "; ".join(problems[:3]))
    else:
        record("工作流 YAML 校验", "PASS", f"{len(files)} 个文件 / {jobs_total} 个 job")


def check_workflow_paths():
    """工作流引用的仓库内文件是否存在（防止改名后 CI 静默失效）。"""
    pattern = re.compile(
        r"\b((?:tool|lib|native_plugins|native_kernels|example_plugins|docs|"
        r"build_kernel_pkg|test)/[\w./\-]+\.(?:py|bat|sh|c|h|dart|json|yml|yaml|md|png|dll|so))"
    )
    missing, checked = [], set()
    for path in sorted(glob.glob(os.path.join(ROOT, ".github", "workflows", "*.yml"))):
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for match in pattern.finditer(text):
            rel = match.group(1)
            if rel in checked:
                continue
            checked.add(rel)
            if any(skip in "/" + rel for skip in PATH_CHECK_SKIP):
                continue
            if not os.path.exists(os.path.join(ROOT, rel.replace("/", os.sep))):
                missing.append(rel)
    if missing:
        record("工作流引用路径", "FAIL",
               f"引用了不存在的文件：{', '.join(sorted(missing))}")
    else:
        record("工作流引用路径", "PASS", f"检查了 {len(checked)} 个仓库内路径")


def check_flutter():
    exe = find_flutter()
    if not exe:
        record("Flutter 静态检查与单元测试", "SKIP",
               "未找到 flutter（可用 FLUTTER_BIN 指定）")
        return
    env_backup = {}
    for key, value in (("PUB_HOSTED_URL", "https://pub.flutter-io.cn"),
                       ("FLUTTER_STORAGE_BASE_URL", "https://storage.flutter-io.cn")):
        env_backup[key] = os.environ.get(key)
        os.environ.setdefault(key, value)

    analyze = run([exe, "analyze"])
    stdout = analyze.stdout or ""
    line = next((l.strip() for l in reversed(stdout.splitlines())
                 if "issues found" in l or "No issues" in l), "")
    bad = [l for l in stdout.splitlines()
           if re.match(r"^\s*(error|warning)\s+-", l)]
    if bad:
        record("flutter analyze", "FAIL", f"{len(bad)} 条 error/warning")
    else:
        record("flutter analyze", "PASS", line or "（未解析到汇总行）")

    tests = run([exe, "test"])
    tail = (tests.stdout or "").strip().splitlines()
    summary = next((l.strip() for l in reversed(tail)
                    if "All tests passed" in l or "Some tests failed" in l), "")
    record("flutter test", "PASS" if tests.returncode == 0 else "FAIL",
           summary or "（未解析到汇总行）")

    for key, value in env_backup.items():
        if value is None:
            os.environ.pop(key, None)


CHECKS = [
    ("内核编译 + 端到端自检", check_kernel_selftest),
    ("预编译 DLL 的 16 个 ABI 导出符号", check_dll_symbols),
    ("清单声明的产物路径", check_manifest_files),
    ("工作流 YAML 合法性", check_workflow_yaml),
    ("工作流引用的仓库内路径", check_workflow_paths),
    ("Flutter 静态检查与单元测试", check_flutter),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="只列出检查项")
    args = ap.parse_args()

    if args.list:
        for name, _ in CHECKS:
            print(name)
        return 0

    print(f"仓库根目录：{ROOT}\n")
    for _, fn in CHECKS:
        try:
            fn()
        except Exception as exc:  # noqa: BLE001
            record(getattr(fn, "__name__", "检查"), "FAIL", f"检查过程异常：{exc}")

    failed = [n for n, s, _ in results if s == "FAIL"]
    skipped = [n for n, s, _ in results if s == "SKIP"]
    print("\n" + "=" * 64)
    print(f"合计 {len(results)} 项：通过 {len(results) - len(failed) - len(skipped)} · "
          f"跳过 {len(skipped)} · 失败 {len(failed)}")
    if failed:
        print("失败项：" + "、".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
