/*
 * Zip Browser —— zb_lite_kernel：HTML -> 文档模型
 *
 * 这是一个刻意保守的解析器：不做 DOM 树，而是把 HTML 线性化成
 * "块（段落/标题/列表项/引用/pre/水平线/图片占位）+ 行内样式片段"，
 * 供 layout 直接排版。
 *
 * 处理内容：
 *   - 跳过 <!-- 注释 --> / <!DOCTYPE> / <?...?>；
 *   - 跳过 <script> <style> <noscript> <svg> <template> <iframe> ... 的内容；
 *   - <head> 内的文本不进正文，但会抓 <title>；
 *   - 实体：&amp; &lt; &gt; &quot; &#39; &nbsp; &#NNN; &#xHH; 及常用命名实体；
 *   - 块级标签：p div h1..h6 li ul ol br hr blockquote pre table tr td th ...
 *   - 行内标签：a b strong i em u code span ...
 *   - <a href>：记录链接区间（块内 run 带 href），供点击命中；
 *   - <img>：转成"占位框 + alt 文本"的图片块；
 *   - id / <a name>：记录锚点，供 #fragment 页内跳转。
 *
 * 不做 CSS、不做脚本、不做表格布局（表格退化为普通块）。
 */
#include <stdlib.h>
#include <string.h>

#include "zb_lite_internal.h"

#define ZB_TAG_STACK 32
#define ZB_LIST_STACK 16
#define ZB_TAG_NAME_MAX 32

/* ============================================================
 *  块 / run 的构造
 * ============================================================ */

static zb_block *zb_doc_new_block(zb_doc *d, zb_node_kind kind) {
    zb_block *b;
    if (d == NULL) return NULL;
    if (d->nblocks >= (size_t)ZB_MAX_BLOCKS) return NULL;
    if (d->nblocks == d->cblocks) {
        size_t cap = (d->cblocks == 0) ? 16 : d->cblocks * 2;
        zb_block *p = (zb_block *)realloc(d->blocks, cap * sizeof(zb_block));
        if (p == NULL) return NULL;
        d->blocks = p;
        d->cblocks = cap;
    }
    b = &d->blocks[d->nblocks++];
    memset(b, 0, sizeof(*b));
    b->kind = kind;
    b->level = 0;
    b->ordered = 0;
    b->index = 0;
    b->indent = 0;
    b->alt = NULL;
    b->runs = NULL;
    b->nruns = 0;
    b->cruns = 0;
    return b;
}

static void zb_block_drop_last(zb_doc *d) {
    zb_block *b;
    if (d == NULL || d->nblocks == 0) return;
    b = &d->blocks[d->nblocks - 1];
    if (b->nruns > 0 || b->alt != NULL) return;
    d->nblocks--;
}

static zb_run *zb_block_add_run(zb_block *b, uint16_t style, const char *href) {
    zb_run *r;
    if (b == NULL) return NULL;
    if (b->nruns == b->cruns) {
        size_t cap = (b->cruns == 0) ? 4 : b->cruns * 2;
        zb_run *p = (zb_run *)realloc(b->runs, cap * sizeof(zb_run));
        if (p == NULL) return NULL;
        b->runs = p;
        b->cruns = cap;
    }
    r = &b->runs[b->nruns++];
    memset(r, 0, sizeof(*r));
    r->style = style;
    r->href = (href != NULL) ? zb_strdup(href) : NULL;
    return r;
}

static int zb_run_append(zb_run *r, const char *s, size_t n) {
    size_t need;
    char *p;
    if (r == NULL || s == NULL || n == 0) return 0;
    if (n > (size_t)-1 - r->tlen - 1) return -1;
    need = r->tlen + n + 1;
    if (need > r->tcap) {
        size_t cap = (r->tcap == 0) ? 32 : r->tcap;
        while (cap < need) {
            if (cap > ((size_t)-1) / 2) {
                cap = need;
                break;
            }
            cap *= 2;
        }
        p = (char *)realloc(r->text, cap);
        if (p == NULL) return -1;
        r->text = p;
        r->tcap = cap;
    }
    memcpy(r->text + r->tlen, s, n);
    r->tlen += n;
    r->text[r->tlen] = '\0';
    return 0;
}

static void zb_run_append_cp(zb_run *r, uint32_t cp) {
    char enc[4];
    size_t n = zb_utf8_encode(cp, enc);
    (void)zb_run_append(r, enc, n);
}

/* ============================================================
 *  字符实体
 * ============================================================ */

typedef struct {
    const char *name;
    uint32_t cp;
} zb_entity;

static const zb_entity ZB_ENTITIES[] = {
    {"amp", 0x26u},     {"lt", 0x3Cu},      {"gt", 0x3Eu},     {"quot", 0x22u},
    {"apos", 0x27u},    {"nbsp", 0xA0u},    {"iexcl", 0xA1u},  {"cent", 0xA2u},
    {"pound", 0xA3u},   {"curren", 0xA4u},  {"yen", 0xA5u},    {"sect", 0xA7u},
    {"copy", 0xA9u},    {"laquo", 0xABu},   {"reg", 0xAEu},    {"deg", 0xB0u},
    {"plusmn", 0xB1u},  {"para", 0xB6u},    {"middot", 0xB7u}, {"frac14", 0xBCu},
    {"frac12", 0xBDu},  {"iquest", 0xBFu},  {"times", 0xD7u},  {"divide", 0xF7u},
    {"szlig", 0xDFu},   {"ndash", 0x2013u}, {"mdash", 0x2014u}, {"lsquo", 0x2018u},
    {"rsquo", 0x2019u}, {"ldquo", 0x201Cu}, {"rdquo", 0x201Du}, {"bull", 0x2022u},
    {"hellip", 0x2026u}, {"trade", 0x2122u}, {"larr", 0x2190u}, {"uarr", 0x2191u},
    {"rarr", 0x2192u},  {"darr", 0x2193u}, {"harr", 0x2194u}, {"minus", 0x2212u},
    {"infin", 0x221Eu}, {"ne", 0x2260u},    {"le", 0x2264u},   {"ge", 0x2265u},
    {"ensp", 0x2002u},  {"emsp", 0x2003u},  {"thinsp", 0x2009u}, {"zwj", 0x200Du},
    {NULL, 0u}};

/* 解析 "&...;"；成功返回 1（*consumed 为包含 & 与 ; 的字节数） */
static int zb_decode_entity(const char *s, size_t len, size_t *consumed,
                            uint32_t *cp) {
    size_t i;
    if (s == NULL || len < 3 || s[0] != '&') return 0;
    if (s[1] == '#') {
        uint32_t v = 0;
        int any = 0;
        i = 2;
        if (i < len && (s[i] == 'x' || s[i] == 'X')) {
            ++i;
            while (i < len && s[i] != ';' && i < 12) {
                char c = s[i];
                v <<= 4;
                if (c >= '0' && c <= '9') {
                    v |= (uint32_t)(c - '0');
                } else if (c >= 'a' && c <= 'f') {
                    v |= (uint32_t)(c - 'a' + 10);
                } else if (c >= 'A' && c <= 'F') {
                    v |= (uint32_t)(c - 'A' + 10);
                } else {
                    return 0;
                }
                any = 1;
                ++i;
            }
        } else {
            while (i < len && s[i] != ';' && i < 12) {
                if (s[i] < '0' || s[i] > '9') return 0;
                v = v * 10u + (uint32_t)(s[i] - '0');
                any = 1;
                ++i;
            }
        }
        if (!any || i >= len || s[i] != ';') return 0;
        if (v == 0u) v = 0xFFFDu;
        *cp = v;
        *consumed = i + 1;
        return 1;
    }
    i = 1;
    while (i < len && s[i] != ';' && s[i] != '&' && i <= 12) ++i;
    if (i >= len || s[i] != ';') return 0;
    {
        size_t n = i - 1;
        size_t k;
        for (k = 0; ZB_ENTITIES[k].name != NULL; ++k) {
            if (strlen(ZB_ENTITIES[k].name) == n &&
                strncmp(ZB_ENTITIES[k].name, s + 1, n) == 0) {
                *cp = ZB_ENTITIES[k].cp;
                *consumed = i + 1;
                return 1;
            }
        }
    }
    return 0;
}

/* ============================================================
 *  解析器状态
 * ============================================================ */

typedef struct {
    uint16_t style;
    const char *href;
} zb_frame;

typedef struct {
    zb_doc *doc;
    const char *html;
    size_t len;
    size_t i;

    uint16_t style;
    const char *href;
    int in_pre;
    int in_head;
    int in_title;
    int quote_depth;
    int pending_space;

    int list_kind[ZB_LIST_STACK];  /* 0 = ul，1 = ol */
    int list_count[ZB_LIST_STACK]; /* 有序列表当前序号 */
    int list_depth;

    zb_frame frame[ZB_TAG_STACK];
    int frame_depth;

    /* 待生成块的属性 */
    zb_node_kind pend_kind;
    int pend_level;
    int pend_ordered;
    int pend_index;
    int pend_indent;

    zb_block *cur; /* 当前块（惰性创建） */

    zb_buf title;
    char **owned_hrefs;
    size_t nowned;
    size_t cowned;
} zb_parser;

static void zb_p_reset_pending(zb_parser *p) {
    p->pend_kind = ZB_NODE_PARAGRAPH;
    p->pend_level = 0;
    p->pend_ordered = 0;
    p->pend_index = 0;
    p->pend_indent = p->quote_depth;
    p->pending_space = 0;
}

static void zb_p_flush(zb_parser *p) {
    if (p->cur != NULL) {
        zb_block_drop_last(p->doc);
        p->cur = NULL;
    }
    zb_p_reset_pending(p);
}

static zb_block *zb_p_current(zb_parser *p) {
    if (p->cur != NULL) return p->cur;
    p->cur = zb_doc_new_block(p->doc, p->pend_kind);
    if (p->cur == NULL) return NULL;
    p->cur->level = p->pend_level;
    p->cur->ordered = p->pend_ordered;
    p->cur->index = p->pend_index;
    p->cur->indent = p->pend_indent;
    return p->cur;
}

/* 当前块的最后一个 run 是否与给定样式/链接一致 */
static zb_run *zb_p_cur_run(zb_parser *p) {
    zb_block *b = zb_p_current(p);
    zb_run *r;
    if (b == NULL) return NULL;
    if (b->nruns > 0) {
        r = &b->runs[b->nruns - 1];
        if (r->style == p->style) {
            if (p->href == NULL && r->href == NULL) return r;
            if (p->href != NULL && r->href != NULL &&
                strcmp(p->href, r->href) == 0) {
                return r;
            }
        }
    }
    return zb_block_add_run(b, p->style, p->href);
}

static void zb_p_put_cp(zb_parser *p, uint32_t cp) {
    zb_run *r;
    if (p->in_title) {
        char enc[4];
        size_t n = zb_utf8_encode(cp, enc);
        (void)zb_buf_put(&p->title, enc, n);
        return;
    }
    if (p->in_head) return;
    r = zb_p_cur_run(p);
    if (r == NULL) return;
    zb_run_append_cp(r, cp);
}

static void zb_p_put_bytes(zb_parser *p, const char *s, size_t n) {
    zb_run *r;
    if (p->in_title) {
        (void)zb_buf_put(&p->title, s, n);
        return;
    }
    if (p->in_head) return;
    r = zb_p_cur_run(p);
    if (r == NULL) return;
    (void)zb_run_append(r, s, n);
}

/* 标题里的空白原样转成空格（标题内容不做"块首去空格"处理） */
static void zb_p_text_title(zb_parser *p, const char *s, size_t n) {
    size_t i;
    for (i = 0; i < n; ++i) {
        char c = s[i];
        if (c == '\r' || c == '\n' || c == '\t' || c == '\f' || c == '\v') c = ' ';
        (void)zb_buf_putc(&p->title, c);
    }
}

/* 把"待补的空格"落到当前样式/链接上（在样式切换前调用，避免空格串到新链接里） */
static void zb_p_flush_pending_space(zb_parser *p) {
    if (!p->pending_space) return;
    p->pending_space = 0;
    if (p->in_head || p->in_title) return;
    if (p->cur != NULL && p->cur->nruns > 0) zb_p_put_cp(p, ' ');
}

/* 正文文本（普通模式：折叠空白） */
static void zb_p_text(zb_parser *p, const char *s, size_t n) {
    size_t i = 0;
    if (p->in_title) {
        zb_p_text_title(p, s, n);
        return;
    }
    while (i < n) {
        char c = s[i];
        if (c == '&') {
            uint32_t cp = 0;
            size_t used = 0;
            if (zb_decode_entity(s + i, n - i, &used, &cp)) {
                zb_p_flush_pending_space(p);
                zb_p_put_cp(p, cp);
                i += used;
                continue;
            }
            zb_p_flush_pending_space(p);
            zb_p_put_cp(p, '&');
            ++i;
            continue;
        }
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' ||
            c == '\v') {
            p->pending_space = 1;
            ++i;
            continue;
        }
        zb_p_flush_pending_space(p);
        {
            size_t before = i;
            uint32_t cp = zb_utf8_next(s, n, &i);
            if (i <= before) i = before + 1; /* 防死循环 */
            zb_p_put_cp(p, cp);
        }
    }
}

/* 预格式化文本（pre：原样保留空白） */
static void zb_p_text_pre(zb_parser *p, const char *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        if (s[i] == '&') {
            uint32_t cp = 0;
            size_t used = 0;
            if (zb_decode_entity(s + i, n - i, &used, &cp)) {
                zb_p_put_cp(p, cp);
                i += used;
                continue;
            }
            zb_p_put_cp(p, '&');
            ++i;
            continue;
        }
        if (s[i] == '\r') {
            /* \r\n / \r 归一为 \n */
            if (i + 1 < n && s[i + 1] == '\n') {
                ++i;
                continue;
            }
            zb_p_put_cp(p, '\n');
            ++i;
            continue;
        }
        zb_p_put_cp(p, (unsigned char)s[i]);
        ++i;
    }
}

/* ============================================================
 *  标签名 / 属性
 * ============================================================ */

static int zb_is_name_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '-' || c == '_' || c == ':' || c == '.';
}

/* 读取标签名（小写化）；返回下一个位置 */
static size_t zb_read_name(const char *s, size_t len, size_t i, char *out,
                           size_t outsz) {
    size_t o = 0;
    while (i < len && zb_is_name_char(s[i])) {
        if (o + 1 < outsz) out[o++] = zb_ascii_lower(s[i]);
        ++i;
    }
    if (outsz > 0) out[o] = '\0';
    return i;
}

/* 找到标签结束位置（考虑引号内的 '>'）；返回 '>' 的下标，找不到返回 len */
static size_t zb_tag_end(const char *s, size_t len, size_t i) {
    char quote = 0;
    while (i < len) {
        char c = s[i];
        if (quote != 0) {
            if (c == quote) quote = 0;
        } else if (c == '"' || c == '\'') {
            quote = c;
        } else if (c == '>') {
            return i;
        }
        ++i;
    }
    return len;
}

/* 在 [i, end) 中查找属性 wanted 的值；找到返回 1 并写入 out */
static int zb_find_attr(const char *s, size_t i, size_t end, const char *wanted,
                        zb_buf *out) {
    size_t wn = strlen(wanted);
    zb_buf_clear(out);
    while (i < end) {
        size_t nstart;
        size_t nend;
        while (i < end && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' ||
                           s[i] == '\r' || s[i] == '/')) {
            ++i;
        }
        nstart = i;
        while (i < end && zb_is_name_char(s[i])) ++i;
        nend = i;
        while (i < end && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' ||
                           s[i] == '\r')) {
            ++i;
        }
        if (i < end && s[i] == '=') {
            ++i;
            while (i < end && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' ||
                               s[i] == '\r')) {
                ++i;
            }
            if (i < end && (s[i] == '"' || s[i] == '\'')) {
                char q = s[i++];
                size_t vstart = i;
                while (i < end && s[i] != q) ++i;
                if (nend - nstart == wn &&
                    strncmp(s + nstart, wanted, wn) == 0) {
                    (void)zb_buf_put(out, s + vstart, i - vstart);
                    return 1;
                }
                if (i < end) ++i;
            } else {
                size_t vstart = i;
                while (i < end && s[i] != ' ' && s[i] != '\t' &&
                       s[i] != '\n' && s[i] != '\r') {
                    ++i;
                }
                if (nend - nstart == wn &&
                    strncmp(s + nstart, wanted, wn) == 0) {
                    (void)zb_buf_put(out, s + vstart, i - vstart);
                    return 1;
                }
            }
        } else if (nend > nstart && nend - nstart == wn &&
                   strncmp(s + nstart, wanted, wn) == 0) {
            return 1; /* 布尔属性 */
        }
        if (nend == nstart) ++i; /* 防死循环 */
    }
    return 0;
}

/* ============================================================
 *  标签分类
 * ============================================================ */

static int zb_heading_level(const char *n) {
    if (n[0] == 'h' && n[1] >= '1' && n[1] <= '6' && n[2] == '\0') {
        return n[1] - '0';
    }
    return 0;
}

static int zb_tag_is_block(const char *n) {
    static const char *const names[] = {
        "p",     "div",   "section", "article", "header", "footer", "main",
        "aside", "nav",   "h1",      "h2",      "h3",     "h4",     "h5",
        "h6",    "ul",    "ol",      "li",      "dl",     "dt",     "dd",
        "blockquote", "pre", "table", "thead", "tbody", "tfoot", "tr",
        "td",    "th",    "caption", "figure",  "figcaption", "form",
        "fieldset", "legend", "address", "center", "details", "summary",
        "hr",    "body",  "html",    "head",    "title",  "meta",   "link",
        "base",  "img",   "br",      "noscript", "template", "iframe",
        NULL};
    int i;
    for (i = 0; names[i] != NULL; ++i) {
        if (strcmp(names[i], n) == 0) return 1;
    }
    return 0;
}

static int zb_tag_is_skip(const char *n) {
    static const char *const names[] = {"script", "style",   "noscript",
                                       "svg",    "canvas",  "template",
                                       "iframe", "object",  "embed",
                                       "math",   "select",  "textarea",
                                       "video",  "audio",   "map",
                                       NULL};
    int i;
    for (i = 0; names[i] != NULL; ++i) {
        if (strcmp(names[i], n) == 0) return 1;
    }
    return 0;
}

static uint16_t zb_tag_inline_style(const char *n) {
    if (strcmp(n, "b") == 0 || strcmp(n, "strong") == 0) return ZB_STYLE_BOLD;
    if (strcmp(n, "i") == 0 || strcmp(n, "em") == 0 || strcmp(n, "cite") == 0 ||
        strcmp(n, "var") == 0 || strcmp(n, "dfn") == 0) {
        return ZB_STYLE_ITALIC;
    }
    if (strcmp(n, "u") == 0 || strcmp(n, "ins") == 0) return ZB_STYLE_UNDERLINE;
    if (strcmp(n, "code") == 0 || strcmp(n, "kbd") == 0 ||
        strcmp(n, "samp") == 0 || strcmp(n, "tt") == 0) {
        return ZB_STYLE_CODE;
    }
    return 0;
}

static int zb_tag_is_inline(const char *n) {
    static const char *const names[] = {
        "a",    "b",     "strong", "i",     "em",    "u",     "ins",  "code",
        "kbd",  "samp",  "tt",     "span",  "small", "big",   "sup",  "sub",
        "mark", "abbr",  "cite",   "q",     "var",   "dfn",   "time", "label",
        "font", "s",     "del",    "strike","wbr",   "nobr",  "bdi",  "bdo",
        "rb",   "rt",    "ruby",   "data",  "output", NULL};
    int i;
    for (i = 0; names[i] != NULL; ++i) {
        if (strcmp(names[i], n) == 0) return 1;
    }
    return 0;
}

/* ============================================================
 *  href 所有权
 * ============================================================ */

static char *zb_p_own_href(zb_parser *p, const char *href) {
    char *copy = zb_strdup(href);
    if (copy == NULL) return NULL;
    if (p->nowned == p->cowned) {
        size_t cap = (p->cowned == 0) ? 4 : p->cowned * 2;
        char **np = (char **)realloc(p->owned_hrefs, cap * sizeof(char *));
        if (np == NULL) {
            free(copy);
            return NULL;
        }
        p->owned_hrefs = np;
        p->cowned = cap;
    }
    p->owned_hrefs[p->nowned++] = copy;
    return copy;
}

static void zb_p_add_anchor(zb_parser *p, const char *id, size_t block_index) {
    zb_doc *d = p->doc;
    zb_anchor *a;
    size_t i;
    if (d == NULL || id == NULL || id[0] == '\0') return;
    if (d->nanchors >= (size_t)ZB_MAX_ANCHORS) return;
    for (i = 0; i < d->nanchors; ++i) {
        if (strcmp(d->anchors[i].id, id) == 0) return; /* 同名锚点保留第一个 */
    }
    if (d->nanchors == d->canchors) {
        size_t cap = (d->canchors == 0) ? 8 : d->canchors * 2;
        zb_anchor *np = (zb_anchor *)realloc(d->anchors, cap * sizeof(zb_anchor));
        if (np == NULL) return;
        d->anchors = np;
        d->canchors = cap;
    }
    a = &d->anchors[d->nanchors];
    a->id = zb_strdup(id);
    if (a->id == NULL) return;
    a->block = block_index;
    d->nanchors++;
}

/* ============================================================
 *  跳过特殊标签内容
 * ============================================================ */

/* 从 i 起跳过 name 元素的内容，返回到其结束标签之后 */
static size_t zb_skip_element(const char *s, size_t len, size_t i,
                              const char *name) {
    size_t nl = strlen(name);
    while (i + 2 + nl <= len) {
        if (s[i] == '<' && s[i + 1] == '/') {
            size_t k;
            int ok = 1;
            for (k = 0; k < nl; ++k) {
                if (zb_ascii_lower(s[i + 2 + k]) != name[k]) {
                    ok = 0;
                    break;
                }
            }
            if (ok) {
                size_t j = i + 2 + nl;
                while (j < len && s[j] != '>') ++j;
                return (j < len) ? j + 1 : len;
            }
        }
        ++i;
    }
    return len;
}

/* ============================================================
 *  主循环
 * ============================================================ */

static void zb_p_open_tag_body(zb_parser *p, const char *s, size_t end,
                               size_t name_end, const char *name) {
    zb_buf attr;
    int hl;
    zb_buf_init(&attr);

    /* 待补空格先落到旧样式上，避免空格串进新开的链接 / 加粗片段 */
    zb_p_flush_pending_space(p);

    if (strcmp(name, "head") == 0) {
        p->in_head = 1;
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "body") == 0 || strcmp(name, "html") == 0) {
        p->in_head = 0;
    }
    if (strcmp(name, "title") == 0) {
        /* 只进入"标题采集"状态，不改 in_head：没有 <head> 的文档，
         * </title> 之后的正文仍要正常解析 */
        p->in_title = 1;
        zb_buf_free(&attr);
        return;
    }
    if (zb_tag_is_skip(name)) {
        zb_buf_free(&attr);
        return; /* 内容已在主循环里跳过 */
    }
    if (strcmp(name, "base") == 0 || strcmp(name, "meta") == 0 ||
        strcmp(name, "link") == 0) {
        zb_buf_free(&attr);
        return;
    }

    if (strcmp(name, "br") == 0) {
        zb_p_put_cp(p, '\n');
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "hr") == 0) {
        zb_block *b;
        zb_p_flush(p);
        b = zb_doc_new_block(p->doc, ZB_NODE_HR);
        if (b != NULL) b->indent = p->quote_depth;
        p->cur = NULL;
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "img") == 0 || strcmp(name, "image") == 0) {
        zb_block *b;
        zb_buf_clear(&attr);
        if (!zb_find_attr(s, name_end, end, "alt", &attr) || attr.len == 0) {
            zb_buf_clear(&attr);
            if (zb_find_attr(s, name_end, end, "src", &attr)) {
                const char *src = zb_buf_cstr(&attr);
                const char *slash = strrchr(src, '/');
                const char *q = strchr(src, '?');
                size_t n;
                zb_buf_clear(&attr);
                if (slash != NULL) {
                    src = slash + 1;
                }
                n = strlen(src);
                if (q != NULL && q > src) n = (size_t)(q - src);
                (void)zb_buf_put(&attr, src, n);
            }
        }
        zb_p_flush(p);
        b = zb_doc_new_block(p->doc, ZB_NODE_IMAGE);
        if (b != NULL) {
            b->indent = p->quote_depth;
            b->alt = zb_strdup(attr.len > 0 ? zb_buf_cstr(&attr) : "image");
        }
        p->cur = NULL;
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "pre") == 0) {
        zb_p_flush(p);
        p->pend_kind = ZB_NODE_PRE;
        p->in_pre = 1;
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "blockquote") == 0) {
        zb_p_flush(p);
        if (p->quote_depth < 8) ++p->quote_depth;
        zb_p_reset_pending(p);
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "ul") == 0 || strcmp(name, "ol") == 0 ||
        strcmp(name, "dl") == 0) {
        zb_p_flush(p);
        if (p->list_depth < ZB_LIST_STACK) {
            p->list_kind[p->list_depth] = (strcmp(name, "ol") == 0) ? 1 : 0;
            p->list_count[p->list_depth] = 0;
            ++p->list_depth;
        }
        zb_p_reset_pending(p);
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "li") == 0 || strcmp(name, "dd") == 0 ||
        strcmp(name, "dt") == 0) {
        int ordered = 0;
        int index = 0;
        zb_p_flush(p);
        if (p->list_depth > 0) {
            int top = p->list_depth - 1;
            ordered = p->list_kind[top];
            if (ordered) {
                p->list_count[top] += 1;
                index = p->list_count[top];
            }
        }
        p->pend_kind = ZB_NODE_LIST_ITEM;
        p->pend_ordered = ordered;
        p->pend_index = index;
        p->pend_indent = p->quote_depth + p->list_depth;
        p->pending_space = 0;
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "td") == 0 || strcmp(name, "th") == 0) {
        zb_p_flush(p);
        zb_p_put_bytes(p, "  ", 2);
        zb_buf_free(&attr);
        return;
    }
    hl = zb_heading_level(name);
    if (hl > 0) {
        zb_p_flush(p);
        p->pend_kind = ZB_NODE_HEADING;
        p->pend_level = hl;
        p->pend_indent = p->quote_depth;
        zb_buf_free(&attr);
        return;
    }
    if (strcmp(name, "a") == 0) {
        zb_buf_clear(&attr);
        if (zb_find_attr(s, name_end, end, "href", &attr) && attr.len > 0) {
            char *copy = zb_p_own_href(p, zb_buf_cstr(&attr));
            if (p->frame_depth < ZB_TAG_STACK) {
                p->frame[p->frame_depth].style = p->style;
                p->frame[p->frame_depth].href = p->href;
                ++p->frame_depth;
            }
            p->href = copy;
            p->style = (uint16_t)(p->style | ZB_STYLE_LINK | ZB_STYLE_UNDERLINE);
        } else if (p->frame_depth < ZB_TAG_STACK) {
            p->frame[p->frame_depth].style = p->style;
            p->frame[p->frame_depth].href = p->href;
            ++p->frame_depth;
        }
        zb_buf_free(&attr);
        return;
    }
    if (zb_tag_is_inline(name)) {
        uint16_t add = zb_tag_inline_style(name);
        if (add != 0) {
            if (p->frame_depth < ZB_TAG_STACK) {
                p->frame[p->frame_depth].style = p->style;
                p->frame[p->frame_depth].href = p->href;
                ++p->frame_depth;
            }
            p->style = (uint16_t)(p->style | add);
        }
        zb_buf_free(&attr);
        return;
    }
    if (zb_tag_is_block(name)) {
        zb_p_flush(p);
        if (p->quote_depth > 0) {
            p->pend_indent = p->quote_depth;
            p->pend_kind = ZB_NODE_QUOTE;
        }
        zb_buf_free(&attr);
        return;
    }
    /* 未知标签：只当成行内分隔（什么也不做） */
    zb_buf_free(&attr);
}

/* 打开标签：先取出 id / name 锚点，派发完再按块的生成情况登记锚点下标 */
static void zb_p_open_tag(zb_parser *p, const char *s, size_t end,
                          size_t name_end, const char *name, int self_closing) {
    zb_buf anchor;
    int is_immediate_block;
    zb_buf_init(&anchor);
    if (zb_find_attr(s, name_end, end, "id", &anchor) && anchor.len > 0) {
        /* 已取得 id */
    } else if (strcmp(name, "a") == 0 &&
               zb_find_attr(s, name_end, end, "name", &anchor) &&
               anchor.len > 0) {
        /* <a name="x"> 也是锚点 */
    } else {
        zb_buf_clear(&anchor);
    }

    zb_p_open_tag_body(p, s, end, name_end, name);

    if (anchor.len > 0 && !self_closing) {
        size_t idx;
        is_immediate_block = (strcmp(name, "hr") == 0 || strcmp(name, "img") == 0 ||
                              strcmp(name, "image") == 0);
        if (is_immediate_block) {
            idx = (p->doc->nblocks > 0) ? (p->doc->nblocks - 1) : 0;
        } else if (zb_tag_is_block(name) || zb_heading_level(name) > 0) {
            idx = p->doc->nblocks; /* 后续内容会新开这一块 */
        } else {
            idx = (p->doc->nblocks > 0) ? (p->doc->nblocks - 1) : 0;
        }
        if (idx >= p->doc->nblocks && p->doc->nblocks > 0) {
            idx = p->doc->nblocks - 1;
        }
        zb_p_add_anchor(p, zb_buf_cstr(&anchor), idx);
    }
    zb_buf_free(&anchor);
}

static void zb_p_close_tag(zb_parser *p, const char *name) {
    if (strcmp(name, "head") == 0) {
        p->in_head = 0;
        return;
    }
    if (strcmp(name, "title") == 0) {
        p->in_title = 0;
        return;
    }
    if (strcmp(name, "pre") == 0) {
        zb_p_flush(p);
        p->in_pre = 0;
        return;
    }
    if (strcmp(name, "blockquote") == 0) {
        zb_p_flush(p);
        if (p->quote_depth > 0) --p->quote_depth;
        zb_p_reset_pending(p);
        return;
    }
    if (strcmp(name, "ul") == 0 || strcmp(name, "ol") == 0 ||
        strcmp(name, "dl") == 0) {
        zb_p_flush(p);
        if (p->list_depth > 0) --p->list_depth;
        zb_p_reset_pending(p);
        return;
    }
    if (strcmp(name, "li") == 0 || strcmp(name, "dd") == 0 ||
        strcmp(name, "dt") == 0) {
        zb_p_flush(p);
        return;
    }
    if (strcmp(name, "td") == 0 || strcmp(name, "th") == 0 ||
        strcmp(name, "tr") == 0) {
        zb_p_flush(p);
        return;
    }
    if (strcmp(name, "a") == 0) {
        if (p->frame_depth > 0) {
            --p->frame_depth;
            p->style = p->frame[p->frame_depth].style;
            p->href = p->frame[p->frame_depth].href;
        } else {
            p->style = (uint16_t)(p->style & ~(ZB_STYLE_LINK | ZB_STYLE_UNDERLINE));
            p->href = NULL;
        }
        return;
    }
    if (zb_tag_inline_style(name) != 0) {
        if (p->frame_depth > 0) {
            --p->frame_depth;
            p->style = p->frame[p->frame_depth].style;
            p->href = p->frame[p->frame_depth].href;
        }
        return;
    }
    if (zb_tag_is_block(name) || zb_heading_level(name) > 0) {
        zb_p_flush(p);
        return;
    }
}

static int zb_p_run(zb_parser *p) {
    while (p->i < p->len) {
        char c = p->html[p->i];
        if (c != '<') {
            size_t start = p->i;
            size_t j = p->i;
            while (j < p->len && p->html[j] != '<') ++j;
            if (p->in_pre) {
                zb_p_text_pre(p, p->html + start, j - start);
            } else {
                zb_p_text(p, p->html + start, j - start);
            }
            p->i = j;
            continue;
        }
        /* c == '<' */
        if (p->i + 1 >= p->len) {
            p->i = p->len;
            break;
        }
        if (p->html[p->i + 1] == '!') {
            if (p->i + 3 < p->len && p->html[p->i + 2] == '-' &&
                p->html[p->i + 3] == '-') {
                size_t j = p->i + 4;
                while (j + 2 < p->len &&
                       !(p->html[j] == '-' && p->html[j + 1] == '-' &&
                         p->html[j + 2] == '>')) {
                    ++j;
                }
                p->i = (j + 2 < p->len) ? j + 3 : p->len;
            } else {
                size_t j = p->i + 2;
                while (j < p->len && p->html[j] != '>') ++j;
                p->i = (j < p->len) ? j + 1 : p->len;
            }
            continue;
        }
        if (p->html[p->i + 1] == '?') {
            size_t j = p->i + 2;
            while (j < p->len && p->html[j] != '>') ++j;
            p->i = (j < p->len) ? j + 1 : p->len;
            continue;
        }
        {
            int closing = 0;
            size_t ni = p->i + 1;
            size_t name_end;
            size_t end;
            char name[ZB_TAG_NAME_MAX];
            int self_closing = 0;
            if (ni < p->len && p->html[ni] == '/') {
                closing = 1;
                ++ni;
            }
            name_end = zb_read_name(p->html, p->len, ni, name, sizeof(name));
            if (name_end == ni) {
                /* 不是合法标签：当普通文本 '<' 处理 */
                if (p->in_pre) {
                    zb_p_text_pre(p, "<", 1);
                } else {
                    zb_p_text(p, "<", 1);
                }
                p->i = ni;
                continue;
            }
            end = zb_tag_end(p->html, p->len, name_end);
            if (end > name_end && p->html[end - 1] == '/') self_closing = 1;
            if (closing) {
                zb_p_close_tag(p, name);
                p->i = (end < p->len) ? end + 1 : p->len;
                continue;
            }
            if (zb_tag_is_skip(name) && !self_closing) {
                /* 跳过内容，但 <title>/<head> 等不在此列 */
                p->i = zb_skip_element(p->html, p->len, end + 1, name);
                continue;
            }
            zb_p_open_tag(p, p->html, end, name_end, name, self_closing);
            p->i = (end < p->len) ? end + 1 : p->len;
            if (strcmp(name, "pre") == 0 && !self_closing) {
                /* pre 紧随其后的第一个换行按 HTML 规范丢弃 */
                if (p->i < p->len && p->html[p->i] == '\n') ++p->i;
                if (p->i + 1 < p->len && p->html[p->i] == '\r' &&
                    p->html[p->i + 1] == '\n') {
                    p->i += 2;
                }
            }
        }
    }
    return 0;
}

/* ============================================================
 *  对外接口
 * ============================================================ */

void zb_doc_init(zb_doc *d) {
    if (d == NULL) return;
    d->blocks = NULL;
    d->nblocks = 0;
    d->cblocks = 0;
    d->anchors = NULL;
    d->nanchors = 0;
    d->canchors = 0;
    d->title = NULL;
    d->text = NULL;
    d->text_ready = 0;
}

void zb_doc_reset(zb_doc *d) {
    size_t i;
    if (d == NULL) return;
    for (i = 0; i < d->nblocks; ++i) {
        zb_block *b = &d->blocks[i];
        size_t k;
        for (k = 0; k < b->nruns; ++k) {
            free(b->runs[k].text);
            free(b->runs[k].href);
        }
        free(b->runs);
        free(b->alt);
    }
    free(d->blocks);
    for (i = 0; i < d->nanchors; ++i) free(d->anchors[i].id);
    free(d->anchors);
    free(d->title);
    free(d->text);
    zb_doc_init(d);
}

int zb_doc_parse_html(zb_doc *d, const char *html) {
    zb_parser p;
    size_t i;
    const char *src = (html != NULL) ? html : "";
    size_t len = strlen(src);
    int truncated = 0;

    if (d == NULL) return -1;
    zb_doc_reset(d);
    if (len > (size_t)ZB_MAX_HTML_BYTES) {
        len = (size_t)ZB_MAX_HTML_BYTES;
        truncated = 1;
    }

    memset(&p, 0, sizeof(p));
    p.doc = d;
    p.html = src;
    p.len = len;
    p.i = 0;
    p.style = 0;
    p.href = NULL;
    p.in_pre = 0;
    p.in_head = 0;
    p.in_title = 0;
    p.quote_depth = 0;
    p.pending_space = 0;
    p.list_depth = 0;
    zb_buf_init(&p.title);
    for (i = 0; i < (size_t)ZB_LIST_STACK; ++i) {
        p.list_kind[i] = 0;
        p.list_count[i] = 0;
    }
    zb_p_reset_pending(&p);

    (void)zb_p_run(&p);
    zb_p_flush(&p);

    /* 标题 */
    {
        size_t start = 0;
        size_t n = zb_trim_len(zb_buf_cstr(&p.title), p.title.len, &start);
        if (n > 0) {
            size_t cap = (n > (size_t)ZB_MAX_TITLE_LEN) ? (size_t)ZB_MAX_TITLE_LEN : n;
            d->title = zb_strndup(zb_buf_cstr(&p.title) + start, cap);
        }
    }
    zb_buf_free(&p.title);

    for (i = 0; i < p.nowned; ++i) free(p.owned_hrefs[i]);
    free(p.owned_hrefs);
    return truncated ? 1 : 0;
}

int zb_doc_parse_plain(zb_doc *d, const char *text) {
    const char *src = (text != NULL) ? text : "";
    size_t len = strlen(src);
    zb_block *b;
    zb_run *r;
    if (d == NULL) return -1;
    zb_doc_reset(d);
    if (len > (size_t)ZB_MAX_HTML_BYTES) len = (size_t)ZB_MAX_HTML_BYTES;
    if (len == 0) return 0;
    b = zb_doc_new_block(d, ZB_NODE_PARAGRAPH);
    if (b == NULL) return -1;
    r = zb_block_add_run(b, 0, NULL);
    if (r == NULL) return -1;
    {
        size_t i = 0;
        while (i < len) {
            if (src[i] == '\r') {
                if (i + 1 < len && src[i + 1] == '\n') {
                    ++i;
                    continue;
                }
                if (zb_run_append(r, "\n", 1) != 0) break;
                ++i;
                continue;
            }
            if (zb_run_append(r, src + i, 1) != 0) break;
            ++i;
        }
    }
    return 0;
}

const char *zb_doc_text(zb_doc *d) {
    zb_buf out;
    size_t i;
    if (d == NULL) return "";
    if (d->text_ready && d->text != NULL) return d->text;
    free(d->text);
    d->text = NULL;
    d->text_ready = 0;
    zb_buf_init(&out);
    for (i = 0; i < d->nblocks; ++i) {
        const zb_block *b = &d->blocks[i];
        size_t k;
        if (b->kind == ZB_NODE_HR) continue;
        if (b->kind == ZB_NODE_IMAGE) {
            if (b->alt != NULL) {
                (void)zb_buf_puts(&out, b->alt);
                (void)zb_buf_putc(&out, '\n');
            }
            continue;
        }
        for (k = 0; k < b->nruns; ++k) {
            const zb_run *r = &b->runs[k];
            if (r->text != NULL) (void)zb_buf_put(&out, r->text, r->tlen);
        }
        (void)zb_buf_putc(&out, '\n');
        if (out.len >= (size_t)ZB_MAX_DOC_TEXT) break;
    }
    d->text = zb_buf_detach(&out);
    if (d->text == NULL) d->text = zb_strdup("");
    d->text_ready = 1;
    return d->text != NULL ? d->text : "";
}
