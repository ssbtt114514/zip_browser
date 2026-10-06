#!/usr/bin/env python3
"""向 android/app/src/main/AndroidManifest.xml 注入浏览器必需配置（幂等）。

- android:usesCleartextTraffic="true"：Android 9+ 默认禁止明文 HTTP，
  浏览器需要能访问任意 http:// 站点（否则 net::ERR_CLEARTEXT_NOT_PERMITTED）。

注意：DOM 存储由 webview_flutter_android 默认开启；媒体自动播放与混合内容
在 Dart 侧（lib/platform/android_system_kernel.dart）设置，无需改 manifest。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "android", "app", "src", "main", "AndroidManifest.xml")


def main() -> int:
    if not os.path.exists(MANIFEST):
        print("跳过：未找到 AndroidManifest.xml，请先执行 flutter 初始化",
              file=sys.stderr)
        return 1

    text = open(MANIFEST, encoding="utf-8").read()

    if "usesCleartextTraffic" in text:
        print("OK   AndroidManifest 已包含 cleartext 配置")
    else:
        def _add(m):
            tag = m.group(0)
            return tag[:-1] + '\n        android:usesCleartextTraffic="true">'

        new, n = re.subn(r"<application\b[^>]*>", _add, text, count=1,
                         flags=re.DOTALL)
        if n == 0:
            print("未找到 <application> 标签", file=sys.stderr)
            return 1
        open(MANIFEST, "w", encoding="utf-8").write(new)
        print("PATCH AndroidManifest 已注入 usesCleartextTraffic")
    return 0


if __name__ == "__main__":
    sys.exit(main())
