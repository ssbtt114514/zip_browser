#!/usr/bin/env python3
"""
获取 WebView2 Fixed Version 运行时（Chromium 固定版本内核的原料）。

用法：
    # 只发现，不下载（打印候选包 id / 版本 / 下载 URL / 体积）
    python tool/fetch_webview2_runtime.py --dry-run

    # 下载并解包到目录（目录里会出现 msedgewebview2.exe）
    python tool/fetch_webview2_runtime.py --out /tmp/wv2 --version 154.0.4258.62

    # 手工指定 .nupkg（内网/镜像/离线场景）
    python tool/fetch_webview2_runtime.py --out /tmp/wv2 --url https://.../x.nupkg

参数：
    --out DIR      运行时输出目录（默认 build/webview2_runtime，在仓库外/忽略目录）
    --version V    指定版本；缺省取该包索引里的最新稳定版
    --arch x64     目标架构：x64 / x86 / arm64（默认 x64）
    --url URL      直接指定 .nupkg 下载地址，跳过发现流程
    --dry-run      只发现并打印，不下载
    --timeout SEC  单次 HTTP 超时（默认 120）
    --keep-nupkg   保留下载的 .nupkg（默认删除，省 ~100MB）

为什么「先发现再下载」：
    WebView2 Fixed Version 运行时的 NuGet 包 id 并非 `microsoft.web.webview2.*`——
    flat-container 上这些 id 全部 404。真实 id 由 NuGet 搜索 API 才能发现
    （当前为 `WebView2.Runtime.X64` / `.X86` / `.ARM64`）。所以脚本先按候选表
    探测 flat-container 索引，全部 404 时回退到搜索 API 动态发现。

关于运行时本体与许可：
    包里的 msedgewebview2.exe 等文件是微软的 WebView2 运行时（PE 版本号即
    Chromium/Edge 版本）。WebView2 运行时按微软条款可随应用分发，详见
    build_kernel_pkg/zb_chromium_kernel/README.md 与 docs/KERNEL_CHROMIUM.md。

退出码：0 成功；非 0 失败（并打印可直接照做的下一步）。
"""
import argparse
import json
import os
import re
import shutil
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

# Windows 控制台默认可能是 GBK，中文诊断会 UnicodeEncodeError 崩掉；
# 这里统一按 UTF-8 输出（CI 与本地行为一致）。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

FLAT_CONTAINER = "https://api.nuget.org/v3-flatcontainer/{cid}/index.json"
FLAT_PACKAGE = "https://api.nuget.org/v3-flatcontainer/{cid}/{ver}/{cid}.{ver}.nupkg"
SEARCH_API = ("https://azuresearch-usnc.nuget.org/query"
              "?q=WebView2%20FixedVersionRuntime&prerelease=false&take=50")

UA = {"User-Agent": "zip-browser-fetch-webview2/1.0 (+https://github.com/ssbtt114514/zip_browser)"}

# 候选包 id（脚本会按顺序探测索引；全部 404 时回退搜索 API）。
CANDIDATE_IDS = [
    "webview2.runtime.x64",
    "webview2.runtime.x86",
    "webview2.runtime.arm64",
    "microsoft.web.webview2.fixedversionruntime.x64",
    "microsoft.web.webview2.fixedversionruntime.win-x64",
    "microsoft.web.webview2.fixedversionruntime",
    "microsoft.web.webview2.fixedversionruntime.x86",
    "microsoft.web.webview2.fixedversionruntime.arm64",
    "microsoft.web.webview2.fixedversionruntime.win-x86",
    "microsoft.web.webview2.fixedversionruntime.win-arm64",
]

# 运行时目录里必须有的关键文件（缺了宿主 WebviewController 起不来）。
RUNTIME_EXE = "msedgewebview2.exe"

# .nupkg 内运行时所在位置会随包版本变化，这里先试已知路径再全局搜索。
KNOWN_RUNTIME_PREFIXES = [
    "contentFiles/any/any/WebView2/",
    "content/WebView2/",
    "build/WebView2/",
    "runtimes/win-x64/native/WebView2/",
]

# 有意义的版本：Chromium/Edge 主版本号不会低于 100（首个固定版本是 8x 时代）。
MIN_SANE_MAJOR = 80

DEFAULT_OUT = os.path.join("build", "webview2_runtime")


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------
def http_get(url, timeout, binary=False):
    """GET 一个 URL；网络层失败重试一次（www.nuget.org 在部分网络下会超时）。"""
    last = None
    for attempt in range(2):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, resp.read() if binary else resp.read()
        except urllib.error.HTTPError as exc:
            raise  # HTTP 状态码是确定性结果，重试没意义
        except Exception as exc:  # noqa: BLE001  （URLError / timeout / ssl）
            last = exc
            if attempt == 0:
                time.sleep(1.5)
    raise last  # type: ignore[misc]


def flat_index(cid, timeout):
    """返回 (versions, error)。404 时 versions=[] 且 error=None。"""
    url = FLAT_CONTAINER.format(cid=cid)
    try:
        _, body = http_get(url, timeout)
        data = json.loads(body.decode("utf-8"))
        versions = [v for v in data.get("versions", []) if isinstance(v, str)]
        return versions, None
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return [], None
        return [], f"HTTP {exc.code}"
    except Exception as exc:  # noqa: BLE001
        return [], f"{type(exc).__name__}: {exc}"


def search_packages(timeout):
    """NuGet 搜索 API 动态发现 id。返回 [(id, version)]。"""
    _, body = http_get(SEARCH_API, timeout)
    data = json.loads(body.decode("utf-8"))
    print(f"搜索 API 命中 {data.get('totalHits')} 条，候选如下：")
    out = []
    for item in data.get("data", []):
        pid = str(item.get("id", ""))
        ver = str(item.get("version", ""))
        owners = ", ".join(item.get("owners") or []) or "(未给出 owners)"
        print(f"  - {pid} · {ver} · authors={owners}")
        if pid:
            out.append((pid, ver))
    return out


def stable_versions(versions):
    """过滤掉 -prerelease / -preview 之类的预览版。"""
    return [v for v in versions if "-" not in v]


def sane_version(v):
    m = re.match(r"^(\d+)\.", v or "")
    return bool(m) and int(m.group(1)) >= MIN_SANE_MAJOR


def pick_version(versions, wanted):
    stable = stable_versions(versions)
    pool = stable or versions
    if wanted:
        if wanted in versions:
            return wanted, None
        near = [v for v in versions if v.startswith(wanted)]
        if near:
            return near[-1], f"未找到精确版本 {wanted}，回退到 {near[-1]}"
        return None, f"包索引里没有版本 {wanted}；可用范围 {pool[0]} … {pool[-1]}"
    if not pool:
        return None, "包索引里没有任何版本"
    return pool[-1], None


# --------------------------------------------------------------------------
# 发现
# --------------------------------------------------------------------------
def discover(arch, wanted_version, timeout, forced_url):
    """返回 (cid, version, url, 说明)。失败时抛出带指引的 RuntimeError。"""
    if forced_url:
        ver = wanted_version or "(手工指定 URL，版本未知)"
        return "(manual)", ver, forced_url, "--url 手工指定，跳过发现"

    arch_key = f".{arch.lower()}" if not arch.lower().startswith("win-") else arch.lower()
    ordered = sorted(
        CANDIDATE_IDS,
        key=lambda c: (arch_key not in c, CANDIDATE_IDS.index(c)),
    )
    print(f"目标架构 {arch}；按以下优先级探测 flat-container 索引（{len(ordered)} 个候选）：")

    found = []
    for cid in ordered:
        versions, err = flat_index(cid, timeout)
        if err:
            print(f"  [跳过] {cid}: {err}")
            continue
        if not versions:
            print(f"  [404]  {cid}")
            continue
        stable = stable_versions(versions)
        print(f"  [OK]   {cid} · {len(versions)} 个版本 · 最新稳定 {stable[-1] if stable else '(无稳定版)'}")
        found.append((cid, versions))

    if not found:
        print("\n候选 id 在 flat-container 上全部不可用，回退 NuGet 搜索 API 动态发现……")
        try:
            hits = search_packages(timeout)
        except Exception as exc:  # noqa: BLE001
            raise RuntimeError(
                "flat-container 候选全部 404，搜索 API 也失败："
                f"{type(exc).__name__}: {exc}\n"
                "可手工下载后重试：\n"
                "  python tool/fetch_webview2_runtime.py --out DIR --url <你的 .nupkg 直链>"
            ) from exc
        for pid, ver in hits:
            versions, _ = flat_index(pid.lower(), timeout)
            if versions:
                found.append((pid.lower(), versions))

    if not found:
        raise RuntimeError(
            "没有发现任何可用的 WebView2 固定版本运行时包。\n"
            "手工路径（照做即可）：\n"
            "  1) 打开 https://www.nuget.org/packages/WebView2.Runtime.X64\n"
            "  2) 在「Download package」处拿到 .nupkg 直链，形如\n"
            "     https://api.nuget.org/v3-flatcontainer/webview2.runtime.x64/"
            "<版本>/webview2.runtime.x64.<版本>.nupkg\n"
            "  3) python tool/fetch_webview2_runtime.py --out DIR --url <该直链>\n"
            "  或从微软站点取 Evergreen 独立安装包后手工解出 msedgewebview2.exe 同目录，"
            "再用 tool/assemble_chromium_kernel.py --runtime <该目录> 装配。"
        )

    cid, versions = found[0]
    version, note = pick_version(versions, wanted_version)
    if version is None:
        raise RuntimeError(f"{cid}: {note}")
    if note:
        print(f"  ! {note}")
    # 版本列表里若同时有旧版 Chromium 版本号（如 8x），提示但不阻断：
    # 固定版本运行时是给宿主自己用的，允许钉住任意可用版本。
    if not sane_version(version):
        print(f"  ! 警告：{version} 的主版本号看起来不像 Chromium/Edge 版本，请确认")

    url = FLAT_PACKAGE.format(cid=cid, ver=version)
    return cid, version, url, f"flat-container 命中：{cid} @ {version}"


# --------------------------------------------------------------------------
# 下载 / 解包
# --------------------------------------------------------------------------
def human(n):
    return f"{n / 1048576:.1f} MiB"


def download(url, dest, timeout):
    tmp = dest + ".part"
    print(f"下载 {url}")
    t0 = time.time()
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as resp, open(tmp, "wb") as fh:
        total = int(resp.headers.get("Content-Length") or 0)
        got = 0
        mark = 0
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)
            got += len(chunk)
            pct = (got * 100 // total) if total else 0
            if pct >= mark + 20 or (total and got == total):
                mark = pct
                print(f"  已下载 {human(got)}"
                      f"{f' / {human(total)} ({pct}%)' if total else ''}")
    os.replace(tmp, dest)
    print(f"下载完成：{dest}（{human(os.path.getsize(dest))}，耗时 {time.time() - t0:.1f}s）")


def locate_runtime_prefix(names):
    """返回 .nupkg 内运行时目录前缀（以 '/' 结尾），找不到返回 None。"""
    for prefix in KNOWN_RUNTIME_PREFIXES:
        if any(n.startswith(prefix) for n in names):
            return prefix
    # 全局搜索：exe 所在目录就是运行时根。
    hits = [n for n in names if n.replace("\\", "/").lower().endswith("/" + RUNTIME_EXE)]
    if hits:
        best = min(hits, key=len)
        return best.replace("\\", "/")[: -len(RUNTIME_EXE)]
    return None


def top_level_listing(names, limit=40):
    tops = sorted({n.replace("\\", "/").split("/")[0] for n in names if n.strip("/")})
    head = tops[:limit]
    return head, len(tops)


def extract_runtime(nupkg, out_dir, do_extract=True):
    """把 .nupkg 里的运行时复制到 out_dir；返回 (文件数, 字节数, 版本目录名)。"""
    with zipfile.ZipFile(nupkg) as z:
        names = [i.filename for i in z.infolist() if not i.is_dir()]
        prefix = locate_runtime_prefix(names)
        if prefix is None:
            tops, total = top_level_listing(names)
            raise RuntimeError(
                f"在 {os.path.basename(nupkg)} 里找不到包含 {RUNTIME_EXE} 的目录，"
                "无法确定运行时根。\n"
                f"包内顶层条目（共 {total} 个，前 {len(tops)} 个）：\n"
                + "\n".join(f"  - {t}" for t in tops)
                + "\n请确认这是 WebView2 固定版本运行时包，或用 --url 换一个来源。"
            )
        print(f"包内运行时目录：{prefix}")

        if not do_extract:
            return 0, 0, prefix

        if os.path.isdir(out_dir):
            shutil.rmtree(out_dir)
        os.makedirs(out_dir, exist_ok=True)

        count = 0
        total = 0
        for info in z.infolist():
            if info.is_dir() or not info.filename.startswith(prefix):
                continue
            rel = info.filename[len(prefix):]
            if not rel:
                continue
            target = os.path.join(out_dir, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(target) or out_dir, exist_ok=True)
            with z.open(info) as src, open(target, "wb") as dst:
                shutil.copyfileobj(src, dst, 1 << 20)
            count += 1
            total += os.path.getsize(target)

    return count, total, prefix


# --------------------------------------------------------------------------
# PE 版本号（只用标准库：读 VS_VERSIONINFO 里的 FileVersion）
# --------------------------------------------------------------------------
def pe_value_after(block, key, search_from):
    """取 block 里 key 之后那个「以 NUL 结尾的 UTF-16LE 字符串」。

    真实 msedgewebview2.exe 的版本块里，FileVersion 的键结束（block 偏移 344）后还要
    跳过 4 字节才是值（值在 348），而 ProductVersion / OriginalFilename 只跳 2 字节；
    固定 4/6 字节对齐的写法总有一个会读错。这里改成「跳过所有 NUL 填充，再从第一个
    非 NUL 字符读到下一个 NUL」，两种排布都成立。
    """
    kb = key.encode("utf-16le")
    pos = search_from
    while True:
        idx = block.find(kb, pos)
        if idx < 0:
            return None
        pos = idx + len(kb)
        i = pos + 2  # 越过键自身的 NUL 终止符
        while i + 1 < len(block) and block[i] == 0 and block[i + 1] == 0:
            i += 2  # 越过对齐填充
            if i - pos > 8:
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
    """返回 {"FileVersion": ..., "ProductVersion": ...}；失败返回 {}。

    只接受全部字符可打印的值：宁可判"读不出"，也不返回错位产生的乱码。
    """
    try:
        with open(pe_path, "rb") as fh:
            data = fh.read()
    except OSError:
        return {}

    if len(data) < 0x40:
        return {}
    if data[:2] != b"MZ":
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

    # 只从 StringFileInfo 之后找键，避免撞上别处的同名字符串；偏移仍按 block 计算。
    sfi = block.find("StringFileInfo".encode("utf-16le"))
    search_from = sfi if sfi >= 0 else 0

    out = {}
    for key in ("FileVersion", "ProductVersion", "OriginalFilename"):
        val = pe_value_after(block, key, search_from)
        if val:
            out[key] = val
    return out


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def parse_args(argv):
    ap = argparse.ArgumentParser(
        description="发现并下载 WebView2 Fixed Version 运行时（.nupkg 解包）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--out", default=DEFAULT_OUT, help=f"运行时输出目录（默认 {DEFAULT_OUT}）")
    ap.add_argument("--version", default=None, help="指定版本（缺省取最新稳定版）")
    ap.add_argument("--arch", default="x64", choices=["x64", "x86", "arm64"],
                    help="目标架构（默认 x64）")
    ap.add_argument("--url", default=None, help="直接指定 .nupkg 下载地址，跳过发现")
    ap.add_argument("--dry-run", action="store_true", help="只发现并打印，不下载")
    ap.add_argument("--timeout", type=float, default=120.0, help="单次 HTTP 超时秒数")
    ap.add_argument("--keep-nupkg", action="store_true", help="保留下载的 .nupkg")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    out_dir = os.path.abspath(args.out)

    print("== 发现 WebView2 固定版本运行时包 ==")
    cid, version, url, note = discover(args.arch, args.version, args.timeout, args.url)
    print(note)

    # 体积：能用 HEAD 就用 HEAD（省一次百兆下载），拿不到就标未知。
    size_hint = "未知"
    try:
        req = urllib.request.Request(url, headers=UA, method="HEAD")
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            length = resp.headers.get("Content-Length")
            if length:
                size_hint = human(int(length))
    except Exception as exc:  # noqa: BLE001
        print(f"  (HEAD 拿体积失败，忽略：{type(exc).__name__}: {exc})")

    print("\n== 结论 ==")
    print(f"  包 id    ：{cid}")
    print(f"  版本     ：{version}")
    print(f"  架构     ：{args.arch}")
    print(f"  下载地址 ：{url}")
    print(f"  体积     ：{size_hint}")
    print(f"  输出目录 ：{out_dir}")

    if args.dry_run:
        print("\n--dry-run：只发现，不下载。去掉 --dry-run 即开始下载。")
        return 0

    os.makedirs(os.path.dirname(out_dir) or ".", exist_ok=True)
    nupkg = os.path.join(os.path.dirname(out_dir) or ".",
                         f"{cid.replace('/', '_')}.{version}.nupkg")
    print("\n== 下载 ==")
    download(url, nupkg, args.timeout)

    print("\n== 解包 ==")
    count, total, prefix = extract_runtime(nupkg, out_dir)

    exe = os.path.join(out_dir, RUNTIME_EXE)
    if not os.path.isfile(exe):
        print(f"解包后仍未找到 {exe}，请检查包内容（前缀 {prefix}）", file=sys.stderr)
        return 1

    info = pe_version_info(exe)
    ver = info.get("FileVersion") or info.get("ProductVersion") or "未知"
    print(f"解包完成：{count} 个文件，{human(total)}")
    print(f"关键文件：{exe}（{os.path.getsize(exe)} 字节）")
    print(f"运行时版本（{RUNTIME_EXE} FileVersion）：{ver}")
    print(f"原始文件名：{info.get('OriginalFilename', '未知')}")
    print("\n下一步：")
    print("  python tool/assemble_chromium_kernel.py "
          f"--runtime \"{out_dir}\"")

    if not args.keep_nupkg:
        try:
            os.remove(nupkg)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as exc:
        print(f"\n[失败] {exc}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n已中断", file=sys.stderr)
        sys.exit(130)
