/*
 * Zip Browser —— zb_lite_kernel：光栅化
 *
 * 只用内置 8x16 点阵字库绘制文字（见 zb_lite_font.h）：
 *   - ASCII 32..126 逐像素绘制；
 *   - 非 ASCII（含 CJK）画"豆腐块"方框占位，宽字符占 2 个字符格；
 *   - 加粗 = 横向偏移重绘一次；下划线 = 文字下方条；颜色由样式与主题决定。
 *
 * 帧缓冲为 RGBA8888（内存顺序 R,G,B,A），严格遵守 stride。
 * 所有写入都逐像素做边界检查，绝不越界。
 */
#include <stdlib.h>
#include <string.h>

#include "zb_lite_internal.h"
#include "zb_lite_font.h"

/* ============================================================
 *  主题
 * ============================================================ */

static const zb_theme ZB_THEME_LIGHT = {
    {255, 255, 255}, /* bg */
    {32, 33, 36},    /* fg */
    {10, 16, 34},    /* heading */
    {24, 86, 210},   /* link */
    {240, 242, 247}, /* code_bg */
    {54, 60, 72},    /* code_fg */
    {206, 211, 220}, /* box */
    {214, 219, 228}, /* border */
    {222, 226, 233}, /* hr */
    {122, 130, 145}, /* dim */
    {24, 86, 210},   /* accent */
    0                /* dark */
};

static const zb_theme ZB_THEME_DARK = {
    {18, 20, 24},    /* bg */
    {226, 230, 236}, /* fg */
    {244, 247, 252}, /* heading */
    {108, 166, 255}, /* link */
    {30, 33, 40},    /* code_bg */
    {198, 208, 222}, /* code_fg */
    {62, 68, 80},    /* box */
    {52, 57, 68},    /* border */
    {46, 51, 61},    /* hr */
    {140, 148, 163}, /* dim */
    {108, 166, 255}, /* accent */
    1                /* dark */
};

const zb_theme *zb_theme_for(int dark) {
    return dark ? &ZB_THEME_DARK : &ZB_THEME_LIGHT;
}

/* ============================================================
 *  基本绘制
 * ============================================================ */

void zb_canvas_clear(zb_canvas *c, const uint8_t rgb[3]) {
    if (c == NULL || c->fb == NULL || c->w <= 0 || c->h <= 0) return;
    {
        int y;
        int x;
        for (y = 0; y < c->h; ++y) {
            uint8_t *row = c->fb + (size_t)y * (size_t)c->stride;
            for (x = 0; x < c->w; ++x) {
                row[x * 4 + 0] = rgb[0];
                row[x * 4 + 1] = rgb[1];
                row[x * 4 + 2] = rgb[2];
                row[x * 4 + 3] = 0xFF;
            }
        }
    }
}

void zb_canvas_px(zb_canvas *c, int x, int y, const uint8_t rgb[3]) {
    uint8_t *p;
    if (c == NULL || c->fb == NULL) return;
    if (x < 0 || y < 0 || x >= c->w || y >= c->h) return;
    p = c->fb + (size_t)y * (size_t)c->stride + (size_t)x * 4;
    p[0] = rgb[0];
    p[1] = rgb[1];
    p[2] = rgb[2];
    p[3] = 0xFF;
}

void zb_canvas_fill(zb_canvas *c, int x, int y, int w, int h, const uint8_t rgb[3]) {
    int j;
    if (c == NULL || c->fb == NULL) return;
    if (w <= 0 || h <= 0) return;
    if (x >= c->w || y >= c->h) return;
    for (j = 0; j < h; ++j) {
        int yy = y + j;
        int i;
        if (yy < 0 || yy >= c->h) continue;
        for (i = 0; i < w; ++i) {
            int xx = x + i;
            uint8_t *p;
            if (xx < 0 || xx >= c->w) continue;
            p = c->fb + (size_t)yy * (size_t)c->stride + (size_t)xx * 4;
            p[0] = rgb[0];
            p[1] = rgb[1];
            p[2] = rgb[2];
            p[3] = 0xFF;
        }
    }
}

static void zb_canvas_frame_rect(zb_canvas *c, int x, int y, int w, int h,
                                 const uint8_t rgb[3]) {
    if (w <= 0 || h <= 0) return;
    zb_canvas_fill(c, x, y, w, 1, rgb);
    zb_canvas_fill(c, x, y + h - 1, w, 1, rgb);
    zb_canvas_fill(c, x, y, 1, h, rgb);
    zb_canvas_fill(c, x + w - 1, y, 1, h, rgb);
}

static void zb_rgb_from_u32(uint32_t v, uint8_t out[3]) {
    out[0] = (uint8_t)((v >> 16) & 0xFFu);
    out[1] = (uint8_t)((v >> 8) & 0xFFu);
    out[2] = (uint8_t)(v & 0xFFu);
}

/* ============================================================
 *  文本度量与绘制
 * ============================================================ */

int zb_char_cells(uint32_t cp) {
    if (cp < 0x1100u) return 1;
    return zb_cp_is_wide(cp) ? 2 : 1;
}

int zb_line_height(int scale) {
    if (scale < 1) scale = 1;
    if (scale > 8) scale = 8;
    return ZB_FONT_CELL_H * scale + 4;
}

int zb_text_width(const char *s, int scale) {
    size_t len;
    size_t i = 0;
    int w = 0;
    if (s == NULL) return 0;
    if (scale < 1) scale = 1;
    if (scale > 8) scale = 8;
    len = strlen(s);
    while (i < len) {
        size_t before = i;
        uint32_t cp = zb_utf8_next(s, len, &i);
        if (i <= before) break;
        w += zb_char_cells(cp) * ZB_FONT_CELL_W * scale;
    }
    return w;
}

static void zb_px_clipped(zb_canvas *c, int x, int y, const uint8_t rgb[3],
                          int clip_x) {
    if (clip_x > 0 && x >= clip_x) return;
    zb_canvas_px(c, x, y, rgb);
}

/* 一个 ASCII 字形 */
static void zb_draw_glyph(zb_canvas *c, int x, int y, int ch, int scale,
                          const uint8_t rgb[3], int offset, int clip_x) {
    const uint8_t *glyph;
    int row;
    if (ch < ZB_FONT_FIRST_CHAR || ch > ZB_FONT_LAST_CHAR) return;
    glyph = ZB_FONT8X16[ch - ZB_FONT_FIRST_CHAR];
    for (row = 0; row < ZB_FONT_CELL_H; ++row) {
        uint8_t bits = glyph[row];
        int col;
        if (bits == 0) continue;
        for (col = 0; col < ZB_FONT_CELL_W; ++col) {
            int dx;
            int dy;
            if ((bits & (uint8_t)(0x80u >> col)) == 0) continue;
            for (dy = 0; dy < scale; ++dy) {
                for (dx = 0; dx < scale; ++dx) {
                    zb_px_clipped(c, x + col * scale + dx + offset,
                                  y + row * scale + dy, rgb, clip_x);
                }
            }
        }
    }
}

/* 非 ASCII：豆腐块占位方框 */
static void zb_draw_tofu(zb_canvas *c, int x, int y, int cells, int scale,
                         const uint8_t rgb[3], int clip_x) {
    int w = cells * ZB_FONT_CELL_W * scale;
    int h = ZB_FONT_CELL_H * scale;
    int s = scale;
    int i;
    if (w <= 2 * s || h <= 2 * s) return;
    for (i = 0; i < w - 2 * s; ++i) {
        int dx;
        for (dx = 0; dx < s; ++dx) {
            zb_px_clipped(c, x + s + i, y + s + dx, rgb, clip_x);
            zb_px_clipped(c, x + s + i, y + h - 2 * s + dx, rgb, clip_x);
        }
    }
    for (i = 0; i < h - 2 * s; ++i) {
        int dx;
        for (dx = 0; dx < s; ++dx) {
            zb_px_clipped(c, x + s + dx, y + s + i, rgb, clip_x);
            zb_px_clipped(c, x + w - 2 * s + dx, y + s + i, rgb, clip_x);
        }
    }
}

void zb_draw_text(zb_canvas *c, int x, int y, const char *s, int scale,
                  const uint8_t rgb[3], int bold, int underline, int clip_x) {
    size_t len;
    size_t i = 0;
    int cx = x;
    int start_x = x;
    int offset;
    if (c == NULL || s == NULL) return;
    if (scale < 1) scale = 1;
    if (scale > 8) scale = 8;
    offset = bold ? ((scale >= 2) ? scale : 1) : 0;
    len = strlen(s);
    while (i < len) {
        size_t before = i;
        uint32_t cp = zb_utf8_next(s, len, &i);
        int cells;
        int cw;
        if (i <= before) break;
        cells = zb_char_cells(cp);
        cw = cells * ZB_FONT_CELL_W * scale;
        if (clip_x > 0 && cx >= clip_x) break;
        if (cp >= (uint32_t)ZB_FONT_FIRST_CHAR && cp <= (uint32_t)ZB_FONT_LAST_CHAR) {
            if (cp != ' ') {
                zb_draw_glyph(c, cx, y, (int)cp, scale, rgb, 0, clip_x);
                if (offset > 0) {
                    zb_draw_glyph(c, cx, y, (int)cp, scale, rgb, offset, clip_x);
                }
            }
        } else if (cp != 0) {
            zb_draw_tofu(c, cx, y, cells, scale, rgb, clip_x);
            if (offset > 0) zb_draw_tofu(c, cx + offset, y, cells, scale, rgb, clip_x);
        }
        cx += cw;
    }
    if (underline && cx > start_x) {
        int ux = start_x;
        int uw = cx - start_x;
        int uy = y + ZB_FONT_CELL_H * scale + 1;
        int k;
        if (clip_x > 0 && ux + uw > clip_x) uw = clip_x - ux;
        for (k = 0; k < scale; ++k) zb_canvas_fill(c, ux, uy + k, uw, 1, rgb);
    }
}

/* ============================================================
 *  排版结果上屏
 * ============================================================ */

void zb_render_layout(zb_canvas *c, const zb_layout *L, const zb_theme *th,
                      int scroll_y) {
    size_t i;
    if (c == NULL || L == NULL || th == NULL) return;
    zb_canvas_clear(c, th->bg);

    /* 第一遍：底色 / 边框 / 水平线（保证文字压在底色之上） */
    for (i = 0; i < L->nops; ++i) {
        const zb_op *op = &L->ops[i];
        uint8_t rgb[3];
        int y;
        zb_rgb_from_u32(op->color, rgb);
        y = op->y - scroll_y;
        switch (op->kind) {
            case ZB_OP_RECT:
                zb_canvas_fill(c, op->x, y, op->w, op->h, rgb);
                break;
            case ZB_OP_FRAME:
                if (op->w > 0 && op->h > 0) {
                    uint8_t inner[3];
                    inner[0] = th->bg[0];
                    inner[1] = th->bg[1];
                    inner[2] = th->bg[2];
                    zb_canvas_fill(c, op->x, y, op->w, op->h, inner);
                    zb_canvas_frame_rect(c, op->x, y, op->w, op->h, rgb);
                }
                break;
            case ZB_OP_HR:
                zb_canvas_fill(c, op->x, y, op->w, op->h > 0 ? op->h : 1, rgb);
                break;
            case ZB_OP_TEXT:
            default:
                break;
        }
    }

    /* 第二遍：文字 */
    for (i = 0; i < L->nops; ++i) {
        const zb_op *op = &L->ops[i];
        uint8_t rgb[3];
        int y;
        int bold;
        int underline;
        if (op->kind != ZB_OP_TEXT || op->text == NULL || op->text[0] == '\0') {
            continue;
        }
        y = op->y - scroll_y;
        if (y + ZB_FONT_CELL_H * (op->scale > 0 ? op->scale : 1) < 0) continue;
        if (y > c->h) continue;
        zb_rgb_from_u32(op->color, rgb);
        bold = ((op->style & ZB_STYLE_BOLD) != 0);
        underline = ((op->style & (ZB_STYLE_UNDERLINE | ZB_STYLE_LINK)) != 0);
        zb_draw_text(c, op->x, y, op->text, op->scale > 0 ? op->scale : 1, rgb,
                     bold, underline, op->clip_x);
    }
}

/* ============================================================
 *  加载中 / 错误页
 * ============================================================ */

static void zb_draw_centered(zb_canvas *c, int y, const char *s, int scale,
                             const uint8_t rgb[3]) {
    int tw = zb_text_width(s, scale);
    int x = (c->w - tw) / 2;
    if (x < 2) x = 2;
    zb_draw_text(c, x, y, s, scale, rgb, 0, 0, 0);
}

void zb_render_loading(zb_canvas *c, const zb_theme *th, const char *url, int phase,
                       int is_error, const char *message) {
    int cxp;
    int cyp;
    int i;
    static const int cos_tab[13] = {100,  97,  87,  71,  50,  26,  0,
                                    -26, -50, -71, -87, -97, -100};
    static const int sin_tab[13] = {0,   26,  50,  71,  87,  97,  100,
                                    97,  87,  71,  50,  26,  0};
    char line[256];
    if (c == NULL || th == NULL) return;
    zb_canvas_clear(c, th->bg);
    phase = ((phase % 12) + 12) % 12;

    cxp = c->w / 2;
    cyp = c->h / 2 - 40;
    if (cyp < 20) cyp = 20;

    if (!is_error) {
        /* 旋转的 12 点指示器 */
        for (i = 0; i < 12; ++i) {
            int ang = (i * 30 + (phase * 30) % 360) % 360;
            int idx = ang / 30;
            int sub = ang % 30;
            int cv = cos_tab[idx] + (cos_tab[idx + 1] - cos_tab[idx]) * sub / 30;
            int sv = sin_tab[idx] + (sin_tab[idx + 1] - sin_tab[idx]) * sub / 30;
            int px = cxp + cv * 16 / 100;
            int py = cyp + sv * 16 / 100;
            int bright = (i == ((phase / 2) % 12)) ? 255 : 90;
            uint8_t rgb[3];
            rgb[0] = (uint8_t)((th->accent[0] * bright) / 255);
            rgb[1] = (uint8_t)((th->accent[1] * bright) / 255);
            rgb[2] = (uint8_t)((th->accent[2] * bright) / 255);
            zb_canvas_fill(c, px - 2, py - 2, 4, 4, rgb);
        }
        zb_draw_centered(c, cyp + 34, "Loading...", 1, th->fg);
    } else {
        uint8_t warn[3];
        warn[0] = 214;
        warn[1] = 92;
        warn[2] = 64;
        zb_canvas_frame_rect(c, cxp - 14, cyp - 12, 28, 24, warn);
        zb_canvas_fill(c, cxp - 1, cyp - 6, 3, 10, warn);
        zb_canvas_fill(c, cxp - 1, cyp + 6, 3, 3, warn);
        zb_draw_centered(c, cyp + 34, "Load failed", 1, th->fg);
        if (message != NULL && message[0] != '\0') {
            zb_draw_centered(c, cyp + 54, message, 1, th->dim);
        }
    }

    /* URL（截断到画布宽度内） */
    {
        const char *u = (url != NULL && url[0] != '\0') ? url : "(blank)";
        size_t cap = sizeof(line) - 1;
        size_t max_chars = (c->w > 24) ? (size_t)((c->w - 24) / ZB_FONT_CELL_W) : 0;
        size_t len = strlen(u);
        if (max_chars == 0) max_chars = 1;
        if (len > max_chars) len = max_chars;
        if (len > cap) len = cap;
        memcpy(line, u, len);
        line[len] = '\0';
        zb_draw_centered(c, cyp + 78, line, 1, th->dim);
    }

    /* 底部提示：本内核为轻量实现（引擎标识可由构建宏覆盖） */
    {
        const char *hint = ZB_ENGINE_HINT;
        int tw = zb_text_width(hint, 1);
        if (tw < c->w - 8) {
            zb_draw_text(c, (c->w - tw) / 2, c->h - 22, hint, 1, th->dim, 0, 0, 0);
        }
    }
}

/* ============================================================
 *  滚动条
 * ============================================================ */

void zb_render_scrollbar(zb_canvas *c, const zb_theme *th, int doc_height,
                         int scroll_y, int view_height) {
    int track_x;
    int track_y = 2;
    int track_h;
    int thumb_h;
    int thumb_y;
    int max_scroll;
    if (c == NULL || th == NULL) return;
    if (doc_height <= view_height) return;
    if (view_height <= 8) return;
    track_x = c->w - 6;
    if (track_x < 0) return;
    track_h = view_height - 4;
    thumb_h = (int)(((long long)track_h * (long long)view_height) /
                    (long long)doc_height);
    if (thumb_h < 24) thumb_h = 24;
    if (thumb_h > track_h) thumb_h = track_h;
    max_scroll = doc_height - view_height;
    if (max_scroll < 1) max_scroll = 1;
    if (scroll_y < 0) scroll_y = 0;
    if (scroll_y > max_scroll) scroll_y = max_scroll;
    thumb_y = track_y + (int)(((long long)(track_h - thumb_h) * (long long)scroll_y) /
                              (long long)max_scroll);
    {
        uint8_t track[3];
        track[0] = th->bg[0];
        track[1] = th->bg[1];
        track[2] = th->bg[2];
        zb_canvas_fill(c, track_x, track_y, 4, track_h, track);
        zb_canvas_fill(c, track_x, thumb_y, 4, thumb_h, th->box);
    }
}
