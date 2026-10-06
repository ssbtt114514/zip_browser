/*
 * Zip Browser —— zb_lite_kernel：排版
 *
 * 把文档模型排成"绘制指令"（zb_op）列表：
 *   - 自动换行：英文按单词（空格处断行），CJK 按字符（每字 2 格），
 *     单个超长单词按字符硬断行；
 *   - 标题字号缩放：h1/h2 最大 -> h6 最小；
 *   - 段落 / 列表 / 引用的间距与缩进，列表带 • 或序号前缀；
 *   - pre 等宽不折行（渲染时按右边界裁切），带代码块底色；
 *   - hr 水平线、img 占位框 + alt 文本；
 *   - 记录每个块的 y 偏移（供 #fragment 锚点跳转）与链接区间（供点击命中）。
 *
 * 排版结果使用文档坐标（y=0 为文档顶部），渲染时统一减去 scroll_y。
 */
#include <stdlib.h>
#include <string.h>

#include "zb_lite_internal.h"

#define ZB_MARGIN_X 12
#define ZB_INDENT_STEP 16
#define ZB_PARA_GAP 9
#define ZB_HEAD_GAP 12
#define ZB_LIST_GAP 3
#define ZB_PRE_PAD 4
#define ZB_MAX_SEGS 16
#define ZB_MAX_DOC_Y 400000

/* ============================================================
 *  指令与链接表
 * ============================================================ */

static zb_op *zb_layout_push(zb_layout *L) {
    zb_op *op;
    if (L == NULL) return NULL;
    if (L->nops >= (size_t)ZB_MAX_OPS) return NULL;
    if (L->nops == L->cops) {
        size_t cap = (L->cops == 0) ? 64 : L->cops * 2;
        zb_op *p = (zb_op *)realloc(L->ops, cap * sizeof(zb_op));
        if (p == NULL) return NULL;
        L->ops = p;
        L->cops = cap;
    }
    op = &L->ops[L->nops++];
    memset(op, 0, sizeof(*op));
    op->link = -1;
    return op;
}

/* 链接表：按 href 去重；超出上限返回 -1（该段退化为普通文本） */
static int zb_layout_link(zb_layout *L, const char *href) {
    size_t i;
    char *copy;
    if (L == NULL || href == NULL || href[0] == '\0') return -1;
    for (i = 0; i < L->nlinks; ++i) {
        if (strcmp(L->links[i], href) == 0) return (int)i;
    }
    if (L->nlinks >= (size_t)ZB_MAX_LINKS) return -1;
    if (L->nlinks == L->clinks) {
        size_t cap = (L->clinks == 0) ? 16 : L->clinks * 2;
        char **np = (char **)realloc(L->links, cap * sizeof(char *));
        if (np == NULL) return -1;
        L->links = np;
        L->clinks = cap;
    }
    copy = zb_strdup(href);
    if (copy == NULL) return -1;
    L->links[L->nlinks] = copy;
    L->nlinks++;
    return (int)(L->nlinks - 1);
}

void zb_layout_init(zb_layout *L) {
    if (L == NULL) return;
    L->ops = NULL;
    L->nops = 0;
    L->cops = 0;
    L->links = NULL;
    L->nlinks = 0;
    L->clinks = 0;
    L->block_y = NULL;
    L->nblock_y = 0;
    L->doc_height = 1;
    L->width = 0;
}

void zb_layout_free(zb_layout *L) {
    size_t i;
    if (L == NULL) return;
    for (i = 0; i < L->nops; ++i) free(L->ops[i].text);
    free(L->ops);
    for (i = 0; i < L->nlinks; ++i) free(L->links[i]);
    free(L->links);
    free(L->block_y);
    zb_layout_init(L);
}

/* ============================================================
 *  行构造器
 * ============================================================ */

typedef struct {
    int x;
    int w;
    zb_buf buf;
    uint16_t style;
    int scale;
    uint32_t color;
    int link;
} zb_seg;

typedef struct {
    zb_layout *L;
    const zb_theme *th;
    int x0;     /* 本块内容左边界（折行后行首） */
    int max_x;  /* 右边界（pre 不折行时设得很大） */
    int clip_x; /* 渲染裁切右边界；<=0 表示不裁切 */
    int y;      /* 当前行顶部 */
    int line_h; /* 行高（含行距） */
    int cur_x;  /* 当前行下一个字符的 x */
    int has_content;
    int pending_space;
    int stop;
    /* 正在组装的"单词"（英文按单词、CJK 单字） */
    zb_buf word;
    int word_w;
    uint16_t w_style;
    uint32_t w_color;
    int w_scale;
    int w_link;
    int w_active;
    zb_seg seg[ZB_MAX_SEGS];
    int nsegs;
} zb_line;

static void zb_line_segs_free(zb_line *ln) {
    int i;
    for (i = 0; i < ln->nsegs; ++i) zb_buf_free(&ln->seg[i].buf);
    ln->nsegs = 0;
}

static void zb_line_init(zb_line *ln, zb_layout *L, const zb_theme *th, int x0,
                         int max_x, int line_h) {
    int i;
    memset(ln, 0, sizeof(*ln));
    ln->L = L;
    ln->th = th;
    ln->x0 = x0;
    ln->max_x = max_x;
    ln->clip_x = 0;
    ln->y = 0;
    ln->line_h = line_h;
    ln->cur_x = x0;
    for (i = 0; i < ZB_MAX_SEGS; ++i) zb_buf_init(&ln->seg[i].buf);
    zb_buf_init(&ln->word);
}

static void zb_line_done(zb_line *ln) {
    zb_line_segs_free(ln);
    zb_buf_free(&ln->word);
}

/* 追加文本到当前行（不换行，调用方保证放得下） */
static void zb_line_seg_put(zb_line *ln, uint16_t style, uint32_t color, int scale,
                            int link, const char *bytes, size_t n, int width) {
    zb_seg *s = NULL;
    if (ln->nsegs > 0) {
        zb_seg *last = &ln->seg[ln->nsegs - 1];
        if (last->style == style && last->color == color && last->scale == scale &&
            last->link == link) {
            s = last;
        }
    }
    if (s == NULL) {
        if (ln->nsegs < ZB_MAX_SEGS) {
            s = &ln->seg[ln->nsegs++];
            zb_buf_clear(&s->buf);
            s->x = ln->cur_x;
            s->w = 0;
            s->style = style;
            s->scale = scale;
            s->color = color;
            s->link = link;
        } else {
            s = &ln->seg[ln->nsegs - 1]; /* 样式切换过多：并入最后一段 */
        }
    }
    (void)zb_buf_put(&s->buf, bytes, n);
    s->w += width;
    ln->cur_x += width;
    ln->has_content = 1;
}

/* 输出当前行并推进 y */
static void zb_line_flush(zb_line *ln) {
    int i;
    if (ln->nsegs > 0) {
        /* 去掉行尾空白 */
        for (i = ln->nsegs - 1; i >= 0; --i) {
            zb_seg *s = &ln->seg[i];
            while (s->buf.len > 0) {
                char c = s->buf.data[s->buf.len - 1];
                if (c != ' ' && c != '\t') break;
                s->buf.data[--s->buf.len] = '\0';
                if (s->w > 0) s->w -= ZB_FONT_CELL_W * s->scale;
            }
            if (s->buf.len == 0 && s->w <= 0) {
                int k;
                zb_buf_free(&s->buf);
                for (k = i; k + 1 < ln->nsegs; ++k) ln->seg[k] = ln->seg[k + 1];
                ln->nsegs--;
                zb_buf_init(&ln->seg[ln->nsegs].buf); /* 防重复释放 */
            } else {
                break;
            }
        }
    }
    for (i = 0; i < ln->nsegs; ++i) {
        zb_seg *s = &ln->seg[i];
        zb_op *op;
        if (s->buf.len == 0) continue;
        op = zb_layout_push(ln->L);
        if (op == NULL) {
            ln->stop = 1;
            continue;
        }
        op->kind = ZB_OP_TEXT;
        op->x = s->x;
        op->y = ln->y;
        op->w = s->w;
        op->h = ln->line_h;
        op->text = zb_buf_detach(&s->buf);
        op->style = s->style;
        op->scale = s->scale;
        op->color = s->color;
        op->link = s->link;
        op->clip_x = ln->clip_x;
    }
    zb_line_segs_free(ln);
    ln->y += ln->line_h;
    ln->cur_x = ln->x0;
    ln->has_content = 0;
    ln->pending_space = 0;
    if (ln->y > ZB_MAX_DOC_Y) ln->stop = 1;
}

/* 把组装的单词落到当前行（必要时先断行；超长单词按字符硬断） */
static void zb_line_flush_word(zb_line *ln) {
    int avail;
    if (!ln->w_active || ln->word.len == 0) {
        ln->w_active = 0;
        zb_buf_clear(&ln->word);
        ln->word_w = 0;
        return;
    }
    if (ln->stop) {
        ln->w_active = 0;
        zb_buf_clear(&ln->word);
        return;
    }
    avail = ln->max_x - ln->x0;
    /* 先处理前导空格 */
    if (ln->pending_space && ln->has_content) {
        int sw = ZB_FONT_CELL_W * ln->w_scale;
        if (ln->cur_x + sw <= ln->max_x) {
            zb_line_seg_put(ln, ln->w_style, ln->w_color, ln->w_scale, ln->w_link,
                            " ", 1, sw);
        } else {
            zb_line_flush(ln);
        }
    }
    ln->pending_space = 0;
    if (ln->has_content && ln->cur_x + ln->word_w > ln->max_x) zb_line_flush(ln);
    if (ln->word_w <= avail) {
        zb_line_seg_put(ln, ln->w_style, ln->w_color, ln->w_scale, ln->w_link,
                        ln->word.data, ln->word.len, ln->word_w);
    } else {
        /* 单字比整行还长：逐字符硬断（stop 后立即收手，避免无界内存） */
        size_t i = 0;
        while (i < ln->word.len && !ln->stop) {
            size_t before = i;
            uint32_t cp = zb_utf8_next(ln->word.data, ln->word.len, &i);
            int cw;
            if (i <= before) break;
            cw = zb_char_cells(cp) * ZB_FONT_CELL_W * ln->w_scale;
            if (ln->has_content && ln->cur_x + cw > ln->max_x) zb_line_flush(ln);
            zb_line_seg_put(ln, ln->w_style, ln->w_color, ln->w_scale, ln->w_link,
                            ln->word.data + before, i - before, cw);
        }
    }
    zb_buf_clear(&ln->word);
    ln->word_w = 0;
    ln->w_active = 0;
}

/* 放一个字符：按单词断行、空格折叠、'\n' 硬换行 */
static void zb_line_put_cp(zb_line *ln, uint32_t cp, uint16_t style, uint32_t color,
                           int scale, int link) {
    char enc[4];
    size_t n;
    int width;
    if (ln->stop) return;
    if (cp == '\n' || cp == '\r') {
        zb_line_flush_word(ln);
        zb_line_flush(ln);
        return;
    }
    if (cp == '\t') cp = ' ';
    if (cp == ' ') {
        zb_line_flush_word(ln);
        if (ln->has_content) ln->pending_space = 1;
        return;
    }
    width = zb_char_cells(cp) * ZB_FONT_CELL_W * scale;
    if (ln->w_active && (ln->w_style != style || ln->w_color != color ||
                         ln->w_scale != scale || ln->w_link != link)) {
        zb_line_flush_word(ln); /* 样式切换：先落字，避免跨样式粘成一个词 */
    }
    n = zb_utf8_encode(cp, enc);
    if (!ln->w_active || ln->word.len == 0) {
        zb_buf_clear(&ln->word);
        ln->word_w = 0;
        ln->w_style = style;
        ln->w_color = color;
        ln->w_scale = scale;
        ln->w_link = link;
        ln->w_active = 1;
    }
    (void)zb_buf_put(&ln->word, enc, n);
    ln->word_w += width;
    /* CJK 等宽字符自成断点：立即落地，实现按字符换行 */
    if (zb_cp_is_wide(cp)) {
        zb_line_flush_word(ln);
    } else {
        int avail = ln->max_x - ln->x0;
        /* 单词已经远超一行：先落地，避免超长无空格文本把内存撑大 */
        if (avail > 0 && ln->word_w > 2 * avail) zb_line_flush_word(ln);
    }
}

/* 放一段文本 */
static void zb_line_put_text(zb_line *ln, const char *text, size_t len, uint16_t style,
                             uint32_t color, int scale, int link) {
    size_t i = 0;
    if (text == NULL || len == 0) return;
    while (i < len && !ln->stop) {
        size_t before = i;
        uint32_t cp = zb_utf8_next(text, len, &i);
        if (i <= before) break;
        zb_line_put_cp(ln, cp, style, color, scale, link);
    }
}

/* ============================================================
 *  颜色
 * ============================================================ */

static uint32_t zb_rgb(const uint8_t c[3]) {
    return ((uint32_t)c[0] << 16) | ((uint32_t)c[1] << 8) | (uint32_t)c[2];
}

static uint32_t zb_color_for(uint16_t style, int is_heading, int is_pre,
                             const zb_theme *th) {
    if ((style & ZB_STYLE_LINK) != 0) return zb_rgb(th->link);
    if (is_heading) return zb_rgb(th->heading);
    if (is_pre || (style & ZB_STYLE_CODE) != 0) return zb_rgb(th->code_fg);
    return zb_rgb(th->fg);
}

/* ============================================================
 *  块排版
 * ============================================================ */

static void zb_put_block_runs(zb_line *ln, const zb_block *b, const zb_theme *th,
                              int scale, int is_heading, int is_pre) {
    size_t k;
    for (k = 0; k < b->nruns && !ln->stop; ++k) {
        const zb_run *r = &b->runs[k];
        uint32_t color = zb_color_for(r->style, is_heading, is_pre, th);
        int link = -1;
        if (r->href != NULL && r->href[0] != '\0') {
            link = zb_layout_link(ln->L, r->href);
        }
        zb_line_put_text(ln, r->text, r->tlen, r->style, color, scale, link);
    }
}

static void zb_layout_hr(zb_layout *L, const zb_theme *th, int x0, int max_x,
                         int indent, int *y) {
    zb_op *op = zb_layout_push(L);
    int ix = x0 + indent * ZB_INDENT_STEP;
    if (op != NULL) {
        op->kind = ZB_OP_HR;
        op->x = ix;
        op->y = *y + 5;
        op->w = (max_x > ix) ? (max_x - ix) : 1;
        op->h = 2;
        op->color = zb_rgb(th->hr);
        op->link = -1;
    }
    *y += 14;
}

static void zb_layout_image(zb_layout *L, const zb_theme *th, const zb_block *b,
                            int x0, int max_x, int *y) {
    int ix = x0 + b->indent * ZB_INDENT_STEP;
    int box_w = max_x - ix;
    int box_h = 64;
    zb_op *frame;
    zb_line ln;
    const char *alt = (b->alt != NULL) ? b->alt : "image";
    size_t alt_len;
    int max_chars;
    if (box_w > 240) box_w = 240;
    if (box_w < 40) box_w = 40;
    frame = zb_layout_push(L);
    if (frame != NULL) {
        frame->kind = ZB_OP_FRAME;
        frame->x = ix;
        frame->y = *y;
        frame->w = box_w;
        frame->h = box_h;
        frame->color = zb_rgb(th->box);
        frame->link = -1;
    }
    /* alt 文本画在框内（限制字符数，避免溢出框外） */
    max_chars = (box_w / ZB_FONT_CELL_W) * ((box_h - 12) / ZB_FONT_CELL_H);
    if (max_chars < 1) max_chars = 1;
    alt_len = strlen(alt);
    if (alt_len > (size_t)max_chars) alt_len = (size_t)max_chars;
    zb_line_init(&ln, L, th, ix + 4, ix + box_w - 4, ZB_FONT_CELL_H);
    ln.y = *y + 6;
    ln.clip_x = ix + box_w - 2;
    zb_line_put_text(&ln, alt, alt_len, 0, zb_rgb(th->dim), 1, -1);
    zb_line_flush_word(&ln);
    zb_line_flush(&ln);
    zb_line_done(&ln);
    *y += box_h + 8;
}

static void zb_layout_text_block(zb_layout *L, const zb_block *b, const zb_theme *th,
                                 int x0, int max_x, int *y, int scale, int line_h,
                                 int gap_before, int gap_after, int is_pre) {
    int indent_px = b->indent * ZB_INDENT_STEP;
    int content_x = x0 + indent_px;
    int is_heading = (b->kind == ZB_NODE_HEADING);
    int prefix_w = 0;
    size_t bar_index = (size_t)-1;
    size_t bg_index = (size_t)-1;
    zb_line ln;

    *y += gap_before;
    if (*y > ZB_MAX_DOC_Y) return;

    /* 引用 / 列表的左侧竖条（高度排完后回填） */
    if (b->indent > 0) {
        zb_op *bar = zb_layout_push(L);
        if (bar != NULL) {
            bar_index = L->nops - 1;
            bar->kind = ZB_OP_RECT;
            bar->x = content_x - ZB_INDENT_STEP + 2;
            bar->y = *y;
            bar->w = 3;
            bar->h = 0;
            bar->color = zb_rgb(th->border);
            bar->link = -1;
        }
    }

    /* 列表前缀 */
    if (b->kind == ZB_NODE_LIST_ITEM) {
        if (b->ordered) {
            char num[16];
            int n = b->index;
            int len = 0;
            if (n < 0) n = 0;
            if (n > 999) n = 999;
            if (n >= 100) {
                num[len++] = (char)('0' + n / 100);
                n %= 100;
                num[len++] = (char)('0' + n / 10);
                num[len++] = (char)('0' + n % 10);
            } else if (n >= 10) {
                num[len++] = (char)('0' + n / 10);
                num[len++] = (char)('0' + n % 10);
            } else {
                num[len++] = (char)('0' + n);
            }
            num[len++] = '.';
            num[len] = '\0';
            {
                zb_op *op = zb_layout_push(L);
                if (op != NULL) {
                    op->kind = ZB_OP_TEXT;
                    op->x = content_x;
                    op->y = *y;
                    op->w = len * ZB_FONT_CELL_W;
                    op->h = line_h;
                    op->text = zb_strdup(num);
                    op->style = 0;
                    op->scale = scale;
                    op->color = zb_rgb(th->dim);
                    op->link = -1;
                }
            }
            prefix_w = (len + 1) * ZB_FONT_CELL_W;
        } else {
            zb_op *op = zb_layout_push(L);
            if (op != NULL) {
                op->kind = ZB_OP_RECT;
                op->x = content_x + 2;
                op->y = *y + 6;
                op->w = 4;
                op->h = 4;
                op->color = zb_rgb(th->fg);
                op->link = -1;
            }
            prefix_w = 12;
        }
    }

    /* pre 代码块底色（高度先占位，排完后回填） */
    if (is_pre) {
        zb_op *bg = zb_layout_push(L);
        if (bg != NULL) {
            bg_index = L->nops - 1;
            bg->kind = ZB_OP_RECT;
            bg->x = content_x - ZB_PRE_PAD;
            bg->y = *y - 2;
            bg->w = (max_x > content_x) ? (max_x - content_x + ZB_PRE_PAD) : 8;
            bg->h = 0;
            bg->color = zb_rgb(th->code_bg);
            bg->link = -1;
        }
    }

    if (prefix_w > 0) content_x += prefix_w;

    zb_line_init(&ln, L, th, content_x, is_pre ? (content_x + 1000000) : max_x,
                 line_h);
    ln.y = *y;
    ln.clip_x = is_pre ? max_x : 0;
    zb_put_block_runs(&ln, b, th, scale, is_heading, is_pre);
    zb_line_flush_word(&ln);
    zb_line_flush(&ln);
    zb_line_done(&ln);

    *y = ln.y;
    if (is_pre) *y += ZB_PRE_PAD;
    *y += gap_after;

    if (bar_index != (size_t)-1 && bar_index < L->nops) {
        int top = L->ops[bar_index].y;
        int h = *y - top - gap_after;
        if (h < 1) h = 1;
        L->ops[bar_index].h = h;
    }
    if (is_pre && bg_index != (size_t)-1 && bg_index < L->nops) {
        int top = L->ops[bg_index].y;
        int h = *y - top - gap_after;
        if (h < 1) h = 1;
        L->ops[bg_index].h = h;
    }
}

/* ============================================================
 *  对外入口
 * ============================================================ */

int zb_layout_build(zb_layout *L, const zb_doc *d, int width, const zb_theme *th) {
    int x0;
    int max_x;
    int y;
    size_t i;
    if (L == NULL) return 1;
    zb_layout_free(L);
    if (width < 64) width = 64;
    if (width > 16384) width = 16384;
    L->width = width;

    x0 = ZB_MARGIN_X;
    max_x = width - ZB_MARGIN_X;
    if (max_x <= x0 + 32) max_x = x0 + 32;
    y = ZB_MARGIN_X;

    if (d == NULL || d->nblocks == 0) {
        L->doc_height = y + ZB_MARGIN_X;
        return L->doc_height;
    }

    L->block_y = (int *)calloc(d->nblocks, sizeof(int));
    if (L->block_y != NULL) {
        L->nblock_y = d->nblocks;
    } else {
        L->nblock_y = 0;
    }

    for (i = 0; i < d->nblocks; ++i) {
        const zb_block *b = &d->blocks[i];
        if (L->nops >= (size_t)ZB_MAX_OPS) break;
        if (y > ZB_MAX_DOC_Y) break;
        if (i < L->nblock_y) L->block_y[i] = y;
        switch (b->kind) {
            case ZB_NODE_HR:
                y += 4;
                zb_layout_hr(L, th, x0, max_x, b->indent, &y);
                break;
            case ZB_NODE_IMAGE:
                y += 4;
                zb_layout_image(L, th, b, x0, max_x, &y);
                break;
            case ZB_NODE_HEADING: {
                int scale;
                int line_h;
                if (b->level <= 1) {
                    scale = 3; /* h1 最大 */
                } else if (b->level <= 3) {
                    scale = 2; /* h2 / h3 */
                } else {
                    scale = 1; /* h4..h6 与正文同号，仅靠间距区分 */
                }
                line_h = zb_line_height(scale);
                zb_layout_text_block(L, b, th, x0, max_x, &y, scale, line_h,
                                     (i == 0) ? 4 : ZB_HEAD_GAP, ZB_HEAD_GAP, 0);
                break;
            }
            case ZB_NODE_PRE:
                zb_layout_text_block(L, b, th, x0, max_x, &y, 1, zb_line_height(1),
                                     ZB_PARA_GAP, ZB_PARA_GAP, 1);
                break;
            case ZB_NODE_LIST_ITEM:
                zb_layout_text_block(L, b, th, x0, max_x, &y, 1, zb_line_height(1),
                                     (i == 0) ? 0 : ZB_LIST_GAP, ZB_LIST_GAP, 0);
                break;
            case ZB_NODE_QUOTE:
            case ZB_NODE_PARAGRAPH:
            default:
                zb_layout_text_block(L, b, th, x0, max_x, &y, 1, zb_line_height(1),
                                     (i == 0) ? 0 : ZB_PARA_GAP, ZB_PARA_GAP, 0);
                break;
        }
    }

    y += ZB_MARGIN_X;
    if (y < 1) y = 1;
    L->doc_height = y;
    return y;
}
