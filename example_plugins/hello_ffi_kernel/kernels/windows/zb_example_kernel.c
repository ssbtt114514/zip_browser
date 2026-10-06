/*
 * Zip Browser —— 示例 FFI 内核（零依赖软件渲染）
 *
 * 实现 native_plugins/zb_native_surface/include/zb_plugin_kernel_abi.h
 * 中的全部导出符号。内核不做真正的 HTML 渲染，而是：
 *
 *   1. 接收宿主 load_url 传入的内容（普通 URL，或 data: URL 解码后的 HTML）
 *   2. 从 HTML 中提取可见文本（跳过 script/style 与标签）
 *   3. 用内置 5x7 点阵字库把标题与正文绘制到 RGBA 帧缓冲
 *   4. 每帧通过 frame_cb 提交给宿主的 surface 插件（Flutter 纹理上屏）
 *
 * 编译（任选其一）：
 *   Windows : tool/build_example_kernel.bat（VS 开发者命令行 / LLVM）
 *   Android : $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang \
 *               --target=aarch64-linux-android24 -shared -fPIC -O2 \
 *               -I native_plugins/zb_native_surface/include \
 *               -o libzb_example_kernel.so zb_example_kernel.c
 *   Linux   : gcc -shared -fPIC -O2 -I native_plugins/zb_native_surface/include \
 *               -o libzb_example_kernel.so zb_example_kernel.c
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zb_plugin_kernel_abi.h"

/* ============================================================
 *  内置 5x7 点阵字库（ASCII 32..126）
 *  每个字形 5 列，每列的 bit0..bit6 对应第 1..7 行
 * ============================================================ */
static const unsigned char ZB_FONT[95][5] = {
    {0x00, 0x00, 0x00, 0x00, 0x00}, /*   */
    {0x00, 0x00, 0x5F, 0x00, 0x00}, /* ! */
    {0x00, 0x07, 0x00, 0x07, 0x00}, /* " */
    {0x14, 0x7F, 0x14, 0x7F, 0x14}, /* # */
    {0x24, 0x2A, 0x7F, 0x2A, 0x12}, /* $ */
    {0x23, 0x13, 0x08, 0x64, 0x62}, /* % */
    {0x36, 0x49, 0x55, 0x22, 0x50}, /* & */
    {0x00, 0x05, 0x03, 0x00, 0x00}, /* ' */
    {0x00, 0x1C, 0x22, 0x41, 0x00}, /* ( */
    {0x00, 0x41, 0x22, 0x1C, 0x00}, /* ) */
    {0x08, 0x2A, 0x1C, 0x2A, 0x08}, /* * */
    {0x08, 0x08, 0x3E, 0x08, 0x08}, /* + */
    {0x00, 0x50, 0x30, 0x00, 0x00}, /* , */
    {0x08, 0x08, 0x08, 0x08, 0x08}, /* - */
    {0x00, 0x60, 0x60, 0x00, 0x00}, /* . */
    {0x20, 0x10, 0x08, 0x04, 0x02}, /* / */
    {0x3E, 0x51, 0x49, 0x45, 0x3E}, /* 0 */
    {0x00, 0x42, 0x7F, 0x40, 0x00}, /* 1 */
    {0x42, 0x61, 0x51, 0x49, 0x46}, /* 2 */
    {0x21, 0x41, 0x45, 0x4B, 0x31}, /* 3 */
    {0x18, 0x14, 0x12, 0x7F, 0x10}, /* 4 */
    {0x27, 0x45, 0x45, 0x45, 0x39}, /* 5 */
    {0x3C, 0x4A, 0x49, 0x49, 0x30}, /* 6 */
    {0x01, 0x71, 0x09, 0x05, 0x03}, /* 7 */
    {0x36, 0x49, 0x49, 0x49, 0x36}, /* 8 */
    {0x06, 0x49, 0x49, 0x29, 0x1E}, /* 9 */
    {0x00, 0x36, 0x36, 0x00, 0x00}, /* : */
    {0x00, 0x56, 0x36, 0x00, 0x00}, /* ; */
    {0x00, 0x08, 0x14, 0x22, 0x41}, /* < */
    {0x14, 0x14, 0x14, 0x14, 0x14}, /* = */
    {0x41, 0x22, 0x14, 0x08, 0x00}, /* > */
    {0x02, 0x01, 0x51, 0x09, 0x06}, /* ? */
    {0x32, 0x49, 0x79, 0x41, 0x3E}, /* @ */
    {0x7E, 0x11, 0x11, 0x11, 0x7E}, /* A */
    {0x7F, 0x49, 0x49, 0x49, 0x36}, /* B */
    {0x3E, 0x41, 0x41, 0x41, 0x22}, /* C */
    {0x7F, 0x41, 0x41, 0x22, 0x1C}, /* D */
    {0x7F, 0x49, 0x49, 0x49, 0x41}, /* E */
    {0x7F, 0x09, 0x09, 0x01, 0x01}, /* F */
    {0x3E, 0x41, 0x41, 0x51, 0x32}, /* G */
    {0x7F, 0x08, 0x08, 0x08, 0x7F}, /* H */
    {0x00, 0x41, 0x7F, 0x41, 0x00}, /* I */
    {0x20, 0x40, 0x41, 0x3F, 0x01}, /* J */
    {0x7F, 0x08, 0x14, 0x22, 0x41}, /* K */
    {0x7F, 0x40, 0x40, 0x40, 0x40}, /* L */
    {0x7F, 0x02, 0x04, 0x02, 0x7F}, /* M */
    {0x7F, 0x04, 0x08, 0x10, 0x7F}, /* N */
    {0x3E, 0x41, 0x41, 0x41, 0x3E}, /* O */
    {0x7F, 0x09, 0x09, 0x09, 0x06}, /* P */
    {0x3E, 0x41, 0x51, 0x21, 0x5E}, /* Q */
    {0x7F, 0x09, 0x19, 0x29, 0x46}, /* R */
    {0x46, 0x49, 0x49, 0x49, 0x31}, /* S */
    {0x01, 0x01, 0x7F, 0x01, 0x01}, /* T */
    {0x3F, 0x40, 0x40, 0x40, 0x3F}, /* U */
    {0x1F, 0x20, 0x40, 0x20, 0x1F}, /* V */
    {0x7F, 0x20, 0x18, 0x20, 0x7F}, /* W */
    {0x63, 0x14, 0x08, 0x14, 0x63}, /* X */
    {0x03, 0x04, 0x78, 0x04, 0x03}, /* Y */
    {0x61, 0x51, 0x49, 0x45, 0x43}, /* Z */
    {0x00, 0x00, 0x7F, 0x41, 0x41}, /* [ */
    {0x02, 0x04, 0x08, 0x10, 0x20}, /* \ */
    {0x41, 0x41, 0x7F, 0x00, 0x00}, /* ] */
    {0x04, 0x02, 0x01, 0x02, 0x04}, /* ^ */
    {0x40, 0x40, 0x40, 0x40, 0x40}, /* _ */
    {0x00, 0x01, 0x02, 0x04, 0x00}, /* ` */
    {0x20, 0x54, 0x54, 0x54, 0x78}, /* a */
    {0x7F, 0x48, 0x44, 0x44, 0x38}, /* b */
    {0x38, 0x44, 0x44, 0x44, 0x20}, /* c */
    {0x38, 0x44, 0x44, 0x48, 0x7F}, /* d */
    {0x38, 0x54, 0x54, 0x54, 0x18}, /* e */
    {0x08, 0x7E, 0x09, 0x01, 0x02}, /* f */
    {0x08, 0x14, 0x54, 0x54, 0x3C}, /* g */
    {0x7F, 0x08, 0x04, 0x04, 0x78}, /* h */
    {0x00, 0x44, 0x7D, 0x40, 0x00}, /* i */
    {0x20, 0x40, 0x44, 0x3D, 0x00}, /* j */
    {0x00, 0x7F, 0x10, 0x28, 0x44}, /* k */
    {0x00, 0x41, 0x7F, 0x40, 0x00}, /* l */
    {0x7C, 0x04, 0x18, 0x04, 0x78}, /* m */
    {0x7C, 0x08, 0x04, 0x04, 0x78}, /* n */
    {0x38, 0x44, 0x44, 0x44, 0x38}, /* o */
    {0x7C, 0x14, 0x14, 0x14, 0x08}, /* p */
    {0x08, 0x14, 0x14, 0x18, 0x7C}, /* q */
    {0x7C, 0x08, 0x04, 0x04, 0x08}, /* r */
    {0x48, 0x54, 0x54, 0x54, 0x20}, /* s */
    {0x04, 0x3F, 0x44, 0x40, 0x20}, /* t */
    {0x3C, 0x40, 0x40, 0x20, 0x7C}, /* u */
    {0x1C, 0x20, 0x40, 0x20, 0x1C}, /* v */
    {0x3C, 0x40, 0x30, 0x40, 0x3C}, /* w */
    {0x44, 0x28, 0x10, 0x28, 0x44}, /* x */
    {0x0C, 0x50, 0x50, 0x50, 0x3C}, /* y */
    {0x44, 0x64, 0x54, 0x4C, 0x44}, /* z */
    {0x00, 0x08, 0x36, 0x41, 0x00}, /* { */
    {0x00, 0x00, 0x7F, 0x00, 0x00}, /* | */
    {0x00, 0x41, 0x36, 0x08, 0x00}, /* } */
    {0x08, 0x08, 0x2A, 0x1C, 0x08}, /* ~ */
};

/* 提取文本缓冲上限 */
#define ZB_TEXT_MAX 2048
#define ZB_URL_MAX 512
#define ZB_TITLE_MAX 96

/* ============================================================
 *  内核实例
 * ============================================================ */
struct zb_kernel_s {
    char *url;   /* 当前地址（HTML 输入时记为其来源） */
    char *title; /* 由正文推断的标题 */
    char *text;  /* 提取出的可见文本 */

    int64_t texture_id;
    zb_frame_submit_fn frame_cb;
    int32_t width;
    int32_t height;
    uint8_t *fb; /* RGBA8888 帧缓冲 */

    int32_t frame;      /* 帧序号（驱动动画） */
    int32_t load_count; /* 导航次数 */

    zb_host_dispatch_fn dispatch;
    int64_t next_request_id;
};

/* ============================================================
 *  小工具
 * ============================================================ */
static char *zb_strdup(const char *s) {
    size_t n;
    char *p;
    if (s == NULL) return NULL;
    n = strlen(s) + 1;
    p = (char *)malloc(n);
    if (p != NULL) memcpy(p, s, n);
    return p;
}

static char *zb_strndup(const char *s, size_t n) {
    char *p;
    size_t i = 0;
    if (s == NULL) return NULL;
    p = (char *)malloc(n + 1);
    if (p == NULL) return NULL;
    while (i < n && s[i] != '\0') {
        p[i] = s[i];
        ++i;
    }
    p[i] = '\0';
    return p;
}

/* 把 s 转为一个 JSON 字符串字面量（堆分配，含两端引号） */
static char *zb_json_string(const char *s) {
    size_t cap, o = 0;
    char *out;
    if (s == NULL) s = "";
    cap = strlen(s) * 2 + 3;
    out = (char *)malloc(cap);
    if (out == NULL) return NULL;
    out[o++] = '"';
    for (; *s != '\0'; ++s) {
        unsigned char c = (unsigned char)*s;
        switch (c) {
            case '"': out[o++] = '\\'; out[o++] = '"'; break;
            case '\\': out[o++] = '\\'; out[o++] = '\\'; break;
            case '\n': out[o++] = '\\'; out[o++] = 'n'; break;
            case '\r': out[o++] = '\\'; out[o++] = 'r'; break;
            case '\t': out[o++] = '\\'; out[o++] = 't'; break;
            default:
                if (c < 0x20) {
                    out[o++] = '?';
                } else {
                    out[o++] = (char)c;
                }
                break;
        }
    }
    out[o++] = '"';
    out[o] = '\0';
    return out;
}

/* ============================================================
 *  绘制
 * ============================================================ */
static void zb_px(zb_kernel_t k, int x, int y, unsigned char r,
                  unsigned char g, unsigned char b) {
    uint8_t *p;
    if (k->fb == NULL) return;
    if (x < 0 || y < 0 || x >= k->width || y >= k->height) return;
    p = k->fb + ((size_t)y * (size_t)k->width + (size_t)x) * 4;
    /* Flutter 纹理为 RGBA8888：按 R,G,B,A 逐字节写入 */
    p[0] = r;
    p[1] = g;
    p[2] = b;
    p[3] = 0xFF;
}

static void zb_fill(zb_kernel_t k, int x0, int y0, int w, int h,
                    unsigned char r, unsigned char g, unsigned char b) {
    int x, y;
    for (y = y0; y < y0 + h; ++y) {
        for (x = x0; x < x0 + w; ++x) zb_px(k, x, y, r, g, b);
    }
}

/* 绘制一行文本；返回绘制时的行高 */
static int zb_draw_text(zb_kernel_t k, int x, int y, const char *s, int scale,
                        unsigned char r, unsigned char g, unsigned char b) {
    int cx = x;
    if (s == NULL) return 0;
    for (; *s != '\0'; ++s) {
        int ch = (unsigned char)*s;
        int col, row, dx, dy;
        const unsigned char *glyph;
        if (ch < 32 || ch > 126) ch = '?';
        glyph = ZB_FONT[ch - 32];
        for (col = 0; col < 5; ++col) {
            for (row = 0; row < 7; ++row) {
                if ((glyph[col] & (1 << row)) == 0) continue;
                for (dy = 0; dy < scale; ++dy) {
                    for (dx = 0; dx < scale; ++dx) {
                        zb_px(k, cx + col * scale + dx, y + row * scale + dy, r,
                              g, b);
                    }
                }
            }
        }
        cx += 6 * scale;
        if (cx > k->width) break;
    }
    return 7 * scale;
}

/*
 * 段落绘制（按字符宽度折行，优先在空格处断行）。
 * 返回下一个可用的 y。
 */
static int zb_draw_paragraph(zb_kernel_t k, int x, int y, const char *s,
                             int scale, int max_chars, int line_h,
                             unsigned char r, unsigned char g, unsigned char b,
                             int y_limit) {
    const char *p = s;
    char line[256];
    if (s == NULL) return y;
    if (max_chars < 1) max_chars = 1;
    if (max_chars > 255) max_chars = 255;
    while (*p != '\0' && y + line_h <= y_limit) {
        int n = 0;
        int last_space = -1;
        while (p[n] != '\0' && p[n] != '\n' && n < max_chars) {
            if (p[n] == ' ') last_space = n;
            ++n;
        }
        /* 若因为超宽被截断，则在最近的空格处断行 */
        if (last_space > 0 && n == max_chars && p[n] != '\0' && p[n] != '\n') {
            n = last_space;
        }
        memcpy(line, p, (size_t)n);
        line[n] = '\0';
        zb_draw_text(k, x, y, line, scale, r, g, b);
        y += line_h;
        p += n;
        while (*p == ' ') ++p;
        if (*p == '\n') ++p;
    }
    return y;
}

/* ============================================================
 *  内容解析
 * ============================================================ */

/* 判断输入是否像 HTML 文本 */
static int zb_looks_like_html(const char *s) {
    const char *p;
    if (s == NULL) return 0;
    p = strchr(s, '<');
    if (p == NULL) return 0;
    /* 只要出现常见标签字符即认为像 HTML */
    return strchr(s, '>') != NULL;
}

/*
 * 从 HTML 中提取可见文本：
 *   - 跳过 <script> / <style> 块
 *   - 跳过所有标签
 *   - 解码少量 HTML 实体
 *   - 折叠空白，块级标签处换行
 */
static void zb_html_to_text(const char *in, char *out, size_t outsz) {
    size_t i = 0, o = 0;
    int in_tag = 0;
    int skipping = 0;
    int last_space = 1;
    char tagname[16];
    size_t tn = 0;

    if (outsz == 0) return;
    for (; in[i] != '\0' && o + 2 < outsz; ++i) {
        char c = in[i];

        if (skipping) {
            if (c == '<' && in[i + 1] == '/') {
                if (strncmp(in + i, "</script", 8) == 0 ||
                    strncmp(in + i, "</style", 7) == 0) {
                    skipping = 0;
                }
            }
            continue;
        }

        if (c == '<') {
            in_tag = 1;
            tn = 0;
            /* 块级标签前插入换行 */
            if (o > 0 && out[o - 1] != '\n') {
                out[o++] = '\n';
                last_space = 1;
            }
            continue;
        }

        if (in_tag) {
            if (c == '>') {
                in_tag = 0;
                tagname[tn] = '\0';
                if (strcmp(tagname, "script") == 0 ||
                    strcmp(tagname, "style") == 0) {
                    skipping = 1;
                    /* 移除刚插入的换行占位 */
                    if (o > 0 && out[o - 1] == '\n') --o;
                } else if (strcmp(tagname, "br") == 0 ||
                           strcmp(tagname, "p") == 0 ||
                           strcmp(tagname, "div") == 0 ||
                           strcmp(tagname, "li") == 0) {
                    if (o > 0 && out[o - 1] != '\n') {
                        out[o++] = '\n';
                        last_space = 1;
                    }
                }
            } else if (tn < 15 && c != '/') {
                char lc = c;
                if (lc >= 'A' && lc <= 'Z') lc = (char)(lc - 'A' + 'a');
                tagname[tn++] = lc;
            }
            continue;
        }

        if (c == '&') {
            if (strncmp(in + i, "&amp;", 5) == 0) {
                c = '&';
                i += 4;
            } else if (strncmp(in + i, "&lt;", 4) == 0) {
                c = '<';
                i += 3;
            } else if (strncmp(in + i, "&gt;", 4) == 0) {
                c = '>';
                i += 3;
            } else if (strncmp(in + i, "&quot;", 6) == 0) {
                c = '"';
                i += 5;
            } else if (strncmp(in + i, "&#39;", 5) == 0) {
                c = '\'';
                i += 4;
            } else if (strncmp(in + i, "&nbsp;", 6) == 0) {
                c = ' ';
                i += 5;
            }
        }

        if (c == '\r' || c == '\t') c = ' ';
        if (c == '\n') {
            if (o > 0 && out[o - 1] != '\n') out[o++] = '\n';
            last_space = 1;
            continue;
        }
        if (c == ' ') {
            if (last_space) continue;
            last_space = 1;
        } else {
            last_space = 0;
        }
        out[o++] = c;
    }
    /* 去掉结尾换行 */
    while (o > 0 && (out[o - 1] == '\n' || out[o - 1] == ' ')) --o;
    out[o] = '\0';
}

/* 取正文首个非空行作为标题 */
static void zb_title_from_text(const char *text, char *out, size_t outsz) {
    size_t o = 0;
    if (outsz == 0) return;
    while (*text == '\n' || *text == ' ') ++text;
    while (*text != '\0' && *text != '\n' && o + 1 < outsz) {
        out[o++] = *text++;
    }
    out[o] = '\0';
}

/* ============================================================
 *  渲染一帧
 * ============================================================ */
static void zb_render(zb_kernel_t k) {
    int W, H, y, x;
    int phase;
    if (k == NULL || k->fb == NULL || k->frame_cb == NULL) return;
    W = k->width;
    H = k->height;
    if (W <= 0 || H <= 0) return;

    /* 1. 纵向渐变背景 */
    for (y = 0; y < H; ++y) {
        int t = (H > 1) ? (y * 255) / (H - 1) : 0;
        unsigned char r = (unsigned char)(10 + t * 10 / 255);
        unsigned char g = (unsigned char)(14 + t * 12 / 255);
        unsigned char b = (unsigned char)(26 + t * 30 / 255);
        for (x = 0; x < W; ++x) zb_px(k, x, y, r, g, b);
    }

    /* 2. 顶部工具栏 */
    zb_fill(k, 0, 0, W, 64, 22, 26, 40);
    zb_fill(k, 0, 64, W, 2, 58, 60, 84);
    /* 左侧强调色竖条 */
    zb_fill(k, 0, 0, 6, 64, 91, 141, 239);

    /* 3. 标题（竖条右侧，居中偏左） */
    {
        const char *title = (k->title != NULL && k->title[0] != '\0')
                                ? k->title
                                : "Zip Browser Demo Kernel";
        zb_draw_text(k, 24, 12, title, 2, 236, 240, 248);
        zb_draw_text(k, 24, 38, "SOFTWARE RENDERER / NO WEB ENGINE", 1, 130, 150,
                     190);
    }

    /* 4. 右上角旋转指示器（随帧变化） */
    {
        int i;
        int cxp = W - 40;
        int cyp = 32;
        phase = (k->frame / 2) % 12;
        for (i = 0; i < 12; ++i) {
            int ang = (i * 30 + phase * 30) % 360;
            int dist = 14;
            /* 简易定点正余弦（0.01 精度） */
            static const int cos_tab[13] = {100,  97,  87, 71, 50, 26,  0,
                                            -26, -50, -71, -87, -97, -100};
            static const int sin_tab[13] = {0,   26,  50, 71, 87, 97,  100,
                                            97,  87,  71, 50, 26,  0};
            int idx = (ang % 360) / 30;
            int sub = (ang % 30);
            int c0 = cos_tab[idx];
            int c1 = cos_tab[idx + 1];
            int s0 = sin_tab[idx];
            int s1 = sin_tab[idx + 1];
            int cv = c0 + (c1 - c0) * sub / 30;
            int sv = s0 + (s1 - s0) * sub / 30;
            int px = cxp + (cv * dist) / 100;
            int py = cyp + (sv * dist) / 100;
            int bright = (i == (phase % 12)) ? 255 : 70;
            zb_fill(k, px - 2, py - 2, 4, 4, (unsigned char)bright,
                    (unsigned char)(bright * 3 / 4),
                    (unsigned char)(bright / 2));
        }
    }

    /* 5. 正文（自动折行） */
    {
        int max_chars = (W - 48) / 6;
        int bottom = H - 56;
        y = 92;
        if (k->text != NULL && k->text[0] != '\0') {
            y = zb_draw_paragraph(k, 24, y, k->text, 1, max_chars, 12, 214, 220,
                                  236, bottom);
        } else {
            y = zb_draw_paragraph(k, 24, y,
                                  "No content loaded. Enter an address to see "
                                  "the demo kernel render the page text.",
                                  1, max_chars, 12, 214, 220, 236, bottom);
        }
    }

    /* 6. 底部状态栏 */
    zb_fill(k, 0, H - 40, W, 40, 18, 20, 32);
    zb_fill(k, 0, H - 40, W, 1, 48, 52, 74);
    {
        char status[160];
        const char *u = (k->url != NULL && k->url[0] != '\0') ? k->url
                                                              : "(blank)";
        size_t ulen = strlen(u);
        /* snprintf 在 MSVC 2015+ 可用 */
        snprintf(status, sizeof(status), "FRAME %06d   %dx%d   LOADS %d", (int)k->frame,
                 W, H, (int)k->load_count);
        zb_draw_text(k, 16, H - 28, status, 1, 150, 165, 200);
        if (ulen > 60) {
            char short_url[64];
            memcpy(short_url, u, 59);
            short_url[59] = '.';
            short_url[60] = '.';
            short_url[61] = '.';
            short_url[62] = '\0';
            zb_draw_text(k, 16, H - 14, short_url, 1, 96, 108, 140);
        } else {
            zb_draw_text(k, 16, H - 14, u, 1, 96, 108, 140);
        }
    }

    /* 7. 底部进度条（循环动画） */
    {
        int bar_y = H - 4;
        int pos = (k->frame * 12) % (W + 160) - 160;
        zb_fill(k, 0, bar_y, W, 4, 30, 34, 50);
        if (pos < 0) pos = 0;
        zb_fill(k, pos, bar_y, 160, 4, 91, 141, 239);
    }

    /* 8. 提交帧给宿主 surface 插件 */
    k->frame_cb(k->texture_id, k->fb, W, H, W * 4);
}

/* 重新分配帧缓冲（尺寸变化时） */
static void zb_ensure_fb(zb_kernel_t k) {
    size_t need;
    if (k->width <= 0 || k->height <= 0) return;
    need = (size_t)k->width * (size_t)k->height * 4;
    if (k->fb != NULL) {
        free(k->fb);
        k->fb = NULL;
    }
    k->fb = (uint8_t *)malloc(need);
}

/* ============================================================
 *  ABI 实现
 * ============================================================ */
ZB_API int32_t zb_abi_version(void) { return ZB_ABI_VERSION; }

ZB_API zb_kernel_t zb_kernel_create(const char *config_json,
                                    zb_host_dispatch_fn host_dispatch) {
    zb_kernel_t k = (zb_kernel_t)calloc(1, sizeof(struct zb_kernel_s));
    if (k == NULL) return NULL;

    k->url = zb_strdup("about:blank");
    k->title = zb_strdup("Zip Browser Demo Kernel");
    k->text = zb_strdup("");
    k->dispatch = host_dispatch;
    k->next_request_id = 1;
    k->frame = 0;
    k->load_count = 0;
    k->width = 0;
    k->height = 0;
    k->fb = NULL;
    k->frame_cb = NULL;
    k->texture_id = 0;

    (void)config_json; /* 示例内核不解析配置 */
    return k;
}

ZB_API void zb_kernel_destroy(zb_kernel_t k) {
    if (k == NULL) return;
    free(k->url);
    free(k->title);
    free(k->text);
    free(k->fb);
    free(k);
}

ZB_API const char *zb_kernel_name(zb_kernel_t k) {
    (void)k;
    return zb_strdup("zip-browser-demo-kernel");
}

ZB_API const char *zb_kernel_version(zb_kernel_t k) {
    (void)k;
    return zb_strdup("1.0.0");
}

ZB_API int32_t zb_kernel_load_url(zb_kernel_t k, const char *url) {
    if (k == NULL) return -1;

    free(k->text);
    k->text = NULL;

    if (zb_looks_like_html(url)) {
        char *buf = (char *)malloc(ZB_TEXT_MAX);
        if (buf != NULL) {
            zb_html_to_text(url, buf, ZB_TEXT_MAX);
            k->text = buf;
        } else {
            k->text = zb_strdup("");
        }
        free(k->url);
        k->url = zb_strdup("about:home");

        free(k->title);
        if (k->text != NULL && k->text[0] != '\0') {
            char t[ZB_TITLE_MAX];
            zb_title_from_text(k->text, t, sizeof(t));
            k->title = zb_strdup(t);
        } else {
            k->title = zb_strdup("Untitled");
        }
    } else {
        k->text = zb_strdup("");
        free(k->url);
        k->url = zb_strndup(url != NULL ? url : "", ZB_URL_MAX);
        free(k->title);
        if (url != NULL && url[0] != '\0') {
            k->title = zb_strndup(url, ZB_TITLE_MAX);
        } else {
            k->title = zb_strdup("Blank");
        }
    }

    k->load_count += 1;
    k->frame = 0;

    /* 通知宿主：已导航（演示 host_dispatch 通道） */
    if (k->dispatch != NULL) {
        char params[ZB_URL_MAX + 64];
        char *title_json = zb_json_string(k->title);
        snprintf(params, sizeof(params), "{\"title\":%s,\"loads\":%d}",
                 title_json != NULL ? title_json : "\"\"", (int)k->load_count);
        free(title_json);
        k->dispatch(k->next_request_id++, "kernel.navigated", params);
    }

    zb_render(k);
    return 0;
}

ZB_API int32_t zb_kernel_go_back(zb_kernel_t k) {
    if (k == NULL) return -1;
    /* 演示内核不做历史栈回退 */
    (void)k;
    return 0;
}

ZB_API int32_t zb_kernel_go_forward(zb_kernel_t k) {
    if (k == NULL) return -1;
    (void)k;
    return 0;
}

ZB_API int32_t zb_kernel_reload(zb_kernel_t k) {
    if (k == NULL) return -1;
    k->frame = 0;
    zb_render(k);
    return 0;
}

ZB_API const char *zb_kernel_eval_js(zb_kernel_t k, const char *script) {
    char buf[256];
    (void)k;
    snprintf(buf, sizeof(buf),
             "\"[demo kernel] no JS engine; received %d bytes\"",
             script != NULL ? (int)strlen(script) : 0);
    return zb_strdup(buf);
}

ZB_API const char *zb_kernel_current_url(zb_kernel_t k) {
    if (k == NULL) return zb_strdup("");
    return zb_strdup(k->url != NULL ? k->url : "");
}

ZB_API const char *zb_kernel_title(zb_kernel_t k) {
    if (k == NULL) return zb_strdup("");
    return zb_strdup(k->title != NULL ? k->title : "");
}

ZB_API int32_t zb_kernel_attach_surface(zb_kernel_t k, int64_t texture_id,
                                        zb_frame_submit_fn frame_cb,
                                        int32_t width, int32_t height) {
    if (k == NULL) return -1;
    if (frame_cb == NULL) return -2;
    if (width <= 0 || height <= 0) return -3;

    k->texture_id = texture_id;
    k->frame_cb = frame_cb;

    if (k->width != width || k->height != height || k->fb == NULL) {
        k->width = width;
        k->height = height;
        zb_ensure_fb(k);
        if (k->fb == NULL) {
            k->frame_cb = NULL;
            return -4;
        }
    }

    zb_render(k);
    return 0;
}

ZB_API int32_t zb_kernel_tick(zb_kernel_t k) {
    if (k == NULL) return -1;
    k->frame += 1;
    zb_render(k);
    return 0;
}

ZB_API int32_t zb_kernel_dispatch_from_host(zb_kernel_t k,
                                            const char *message_json) {
    (void)k;
    (void)message_json; /* 示例内核不区分具体响应 */
    return 0;
}

ZB_API void zb_free_ptr(void *ptr) { free(ptr); }
