#!/usr/bin/env python3
"""生成 Zip Browser 应用图标。

图形概念：渐变圆角底 + 白色「地球」（浏览器）+ 正中一道拉链（zip）。
产出：
  assets/icon/app_icon.svg            矢量源文件
  assets/icon/app_icon_1024.png       高清位图
  android/app/src/main/res/mipmap-*/ic_launcher.png  各分辨率
"""
import os
import cairosvg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

INK = "#07304A"  # 拉链深色


def build_svg() -> str:
    # —— 拉链齿：一排横跨中缝的白色齿块 ——
    teeth = []
    top, bottom, pitch = 296, 728, 34
    y = top
    while y < bottom:
        teeth.append(
            f'<rect x="492" y="{y}" width="40" height="18" rx="4" fill="#FFFFFF"/>'
        )
        y += pitch
    teeth_svg = "\n  ".join(teeth)

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0A5FA8"/>
      <stop offset="0.55" stop-color="#0B84A5"/>
      <stop offset="1" stop-color="#14B8C4"/>
    </linearGradient>
    <clipPath id="globeClip"><circle cx="512" cy="512" r="252"/></clipPath>
  </defs>

  <!-- 背景 -->
  <rect x="0" y="0" width="1024" height="1024" rx="224" fill="url(#bg)"/>

  <!-- 地球（浏览器） -->
  <g stroke="#FFFFFF" fill="none">
    <circle cx="512" cy="512" r="252" stroke-width="26"/>
    <ellipse cx="512" cy="512" rx="118" ry="252" stroke-width="18" opacity="0.9"/>
    <ellipse cx="512" cy="512" rx="206" ry="252" stroke-width="12" opacity="0.45"/>
    <g clip-path="url(#globeClip)" stroke-width="16" opacity="0.8">
      <line x1="180" y1="398" x2="844" y2="398"/>
      <line x1="180" y1="626" x2="844" y2="626"/>
    </g>
  </g>

  <!-- 拉链（zip），裁剪在地球内 -->
  <g clip-path="url(#globeClip)">
    <!-- 布带 -->
    <line x1="486" y1="264" x2="486" y2="760" stroke="{INK}" stroke-width="12"/>
    <line x1="538" y1="264" x2="538" y2="760" stroke="{INK}" stroke-width="12"/>
    <!-- 齿 -->
    {teeth_svg}
    <!-- 中缝 -->
    <line x1="512" y1="264" x2="512" y2="760" stroke="{INK}" stroke-width="7"/>
    <!-- 拉链头滑块 -->
    <rect x="468" y="540" width="88" height="58" rx="16" fill="{INK}"/>
    <rect x="498" y="552" width="28" height="34" rx="6" fill="#0B84A5"/>
    <!-- 拉片 -->
    <line x1="512" y1="598" x2="512" y2="628" stroke="{INK}" stroke-width="14"/>
    <circle cx="512" cy="652" r="26" fill="none" stroke="{INK}" stroke-width="14"/>
  </g>
</svg>
"""


def main():
    icon_dir = os.path.join(ROOT, "assets", "icon")
    os.makedirs(icon_dir, exist_ok=True)
    svg = build_svg()
    svg_path = os.path.join(icon_dir, "app_icon.svg")
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg)

    cairosvg.svg2png(bytestring=svg.encode("utf-8"),
                     write_to=os.path.join(icon_dir, "app_icon_1024.png"),
                     output_width=1024, output_height=1024)

    sizes = {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
    }
    for qual, px in sizes.items():
        out_dir = os.path.join(
            ROOT, "android", "app", "src", "main", "res", f"mipmap-{qual}")
        os.makedirs(out_dir, exist_ok=True)
        cairosvg.svg2png(bytestring=svg.encode("utf-8"),
                         write_to=os.path.join(out_dir, "ic_launcher.png"),
                         output_width=px, output_height=px)
        print("生成", os.path.relpath(os.path.join(out_dir, "ic_launcher.png"), ROOT))
    print("SVG 源文件：", os.path.relpath(svg_path, ROOT))


if __name__ == "__main__":
    main()
