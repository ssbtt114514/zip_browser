#!/usr/bin/env python3
"""
生成 example_plugins/lite_kernel/icons/icon.png（256×256）。

风格：圆角深蓝底 + 白色 "Z" 字形 + 蓝色文本光标（I-beam）。
纯标准库实现（zlib + struct 手写 PNG），不依赖 Pillow，
这样在没有 Pillow 的机器 / CI 上也能重新生成图标。

用法：
    python tool/make_lite_kernel_icon.py [输出路径]
"""
import os
import struct
import sys
import zlib

SIZE = 256
SS = 3  # 超采样倍数（渲染 SIZE*SS 再降采样，得到平滑边缘）


def write_png(path, width, height, rgb_rows):
    """rgb_rows: 每行一个 bytes（RGB 顺序）"""
    raw = b"".join(b"\x00" + row for row in rgb_rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(png)


def in_rounded_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    dx = x - cx
    dy = y - cy
    return dx * dx + dy * dy <= r * r


def in_thick_segment(px, py, ax, ay, bx, by, half):
    """点到线段距离 <= half 的判定（用于画斜线）"""
    vx = bx - ax
    vy = by - ay
    wx = px - ax
    wy = py - ay
    L2 = vx * vx + vy * vy
    if L2 <= 0:
        t = 0.0
    else:
        t = (wx * vx + wy * vy) / L2
        t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    dx = px - (ax + t * vx)
    dy = py - (ay + t * vy)
    return dx * dx + dy * dy <= half * half


def render():
    """返回 SIZE×SIZE 的 RGB 行列表"""
    n = SIZE * SS
    # 背景：深蓝渐变（左上较亮 -> 右下更深）
    bg_a = (26, 46, 108)
    bg_b = (9, 18, 46)
    z_col = (255, 255, 255)
    caret_col = (108, 166, 255)
    r_outer = int(46 * SS)
    margin = int(12 * SS)
    z_thick = int(13 * SS)
    caret_thick = int(7 * SS)
    # Z 的三个笔画（相对 256 坐标）
    z_left = 62
    z_right = 168
    z_top = 68
    z_bottom = 188
    caret_x = 198
    caret_top = 78
    caret_bottom = 178

    # 超采样缓冲
    buf = [[(0, 0, 0)] * n for _ in range(n)]
    for y in range(n):
        for x in range(n):
            if not in_rounded_rect(x, y, margin, margin, n - 1 - margin,
                                   n - 1 - margin, r_outer):
                buf[y][x] = (0, 0, 0)  # 透明区域先记黑，最后按 alpha 处理
                continue
            t = (x + y) / float(2 * (n - 1))
            col = tuple(
                int(bg_a[i] + (bg_b[i] - bg_a[i]) * t) for i in range(3)
            )
            buf[y][x] = col

    def paint(pred, col):
        for y in range(n):
            for x in range(n):
                if pred(x, y):
                    buf[y][x] = col

    # Z 顶部横画
    paint(
        lambda x, y: (z_left * SS <= x <= z_right * SS and
                      z_top * SS <= y <= z_top * SS + z_thick),
        z_col,
    )
    # Z 底部横画
    paint(
        lambda x, y: (z_left * SS <= x <= z_right * SS and
                      z_bottom * SS - z_thick <= y <= z_bottom * SS),
        z_col,
    )
    # Z 斜画（右上 -> 左下）
    paint(
        lambda x, y: in_thick_segment(
            x, y,
            z_right * SS, z_top * SS + z_thick // 2,
            z_left * SS, z_bottom * SS - z_thick // 2,
            z_thick / 2.0,
        ),
        z_col,
    )
    # 文本光标（I-beam）：竖线 + 上下短横
    paint(
        lambda x, y: (abs(x - caret_x * SS) <= caret_thick // 2 and
                      caret_top * SS <= y <= caret_bottom * SS),
        caret_col,
    )
    paint(
        lambda x, y: (abs(y - caret_top * SS) <= caret_thick // 2 and
                      caret_x * SS - 7 * SS <= x <= caret_x * SS + 7 * SS),
        caret_col,
    )
    paint(
        lambda x, y: (abs(y - caret_bottom * SS) <= caret_thick // 2 and
                      caret_x * SS - 7 * SS <= x <= caret_x * SS + 7 * SS),
        caret_col,
    )

    # 降采样 + 圆角外透明（合成到白底之外：用浅灰底，PNG 无 alpha 通道）
    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            r = g = b = 0
            for dy in range(SS):
                for dx in range(SS):
                    px = buf[y * SS + dy][x * SS + dx]
                    r += px[0]
                    g += px[1]
                    b += px[2]
            k = SS * SS
            # 圆角外区域按"深蓝底"混合，避免出现黑角
            outside = not in_rounded_rect(
                x, y, margin // SS, margin // SS, SIZE - 1 - margin // SS,
                SIZE - 1 - margin // SS, r_outer // SS
            )
            if outside:
                row += bytes((bg_b[0], bg_b[1], bg_b[2]))
            else:
                row += bytes((r // k, g // k, b // k))
        rows.append(bytes(row))
    return rows


def main():
    default_out = os.path.normpath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                     "example_plugins", "lite_kernel", "icons", "icon.png")
    )
    out = sys.argv[1] if len(sys.argv) > 1 else default_out
    rows = render()
    write_png(out, SIZE, SIZE, rows)
    print("已生成图标：%s（%dx%d）" % (out, SIZE, SIZE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
