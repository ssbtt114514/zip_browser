#!/usr/bin/env python3
"""下载 Windows 安装器所需的运行时依赖（在 CI 中先于 ISCC 执行）。

下载的两份官方安装器会被放进构建输出目录，由 .tooling/installer.iss
在安装阶段静默执行：

  1. VC++ 2015-2022 x64 运行库（vc_redist.x64.exe）
     —— Flutter Windows Release 产物动态链接 VCRUNTIME140 / MSVCP140，
        未装 Redistributable 的干净系统上双击 exe 会直接报
        「无法启动此程序，因为计算机中丢失 VCRUNTIME140.dll」，即用户
        反馈的「安装后无法运行」。

  2. WebView2 Runtime 常青版引导器（MicrosoftEdgeWebview2Setup.exe）
     —— 系统内核依赖 WebView2（Edge Chromium）。Windows 11 / 打过补丁的
        Win10 自带，但 LTSC / Server / 精简系统可能没有，缺了浏览器
        就无法加载网页。

用法：
    python tool/fetch_installer_prereqs.py <输出目录>
    （CI 中用 build/installer-prereqs，勿放进 Release 目录，
      否则会被 installer.iss 的 recursesubdirs 一并装进 {app}）

两个链接都是微软官方永久分发链接（FWLink / aka.ms），指向的文件会随
微软重新发布而更新，因此只做「HTTPS + 最小体积」校验，不锁 SHA256。
"""
from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

# Windows 控制台默认 cp1252/gbk，打印中文会 UnicodeEncodeError，强制 UTF-8
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

PREREQS = [
    {
        "name": "VC_redist.x64.exe",
        "url": "https://aka.ms/vs/17/release/vc_redist.x64.exe",
        "min_bytes": 5_000_000,   # 历史版本 13~26 MB
    },
    {
        "name": "MicrosoftEdgeWebview2Setup.exe",
        "url": "https://go.microsoft.com/fwlink/p/?LinkId=2124703",
        "min_bytes": 1_000_000,   # 引导器约 1.8 MB
    },
]


def fetch(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    failed = False
    for item in PREREQS:
        dest = out_dir / item["name"]
        if dest.exists() and dest.stat().st_size >= item["min_bytes"]:
            print(f"  已存在，跳过下载：{dest}")
            continue
        print(f"  下载 {item['name']}  <-  {item['url']}")
        try:
            req = urllib.request.Request(
                item["url"], headers={"User-Agent": "zip-browser-installer/1.0"}
            )
            with urllib.request.urlopen(req, timeout=120) as resp, dest.open("wb") as fh:
                while True:
                    chunk = resp.read(1 << 16)
                    if not chunk:
                        break
                    fh.write(chunk)
        except Exception as exc:  # noqa: BLE001
            print(f"  !! 下载失败：{exc}")
            dest.unlink(missing_ok=True)
            failed = True
            continue
        size = dest.stat().st_size
        if size < item["min_bytes"]:
            print(f"  !! 文件过小（{size} 字节），疑似劫持/截断，已删除")
            dest.unlink()
            failed = True
            continue
        print(f"  OK  {dest}  ({size / 1e6:.1f} MB)")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    return fetch(Path(argv[1]))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
