/*
 * Zip Browser —— zb_lite_kernel：C ABI 实现（"轻量文本内核"）
 *
 * 严格实现 native_plugins/zb_native_surface/include/zb_plugin_kernel_abi.h
 * 中的 16 个导出符号，不新增任何导出符号。
 *
 * 内核能力：
 *   1. 通过 host_dispatch("net.fetch") 让宿主抓取 http/https 页面，宿主经
 *      dispatch_from_host 回传 {request_id,result|error}；等待期间渲染"加载中"；
 *   2. 把 HTML 解析成文档模型、排版、用内置 8x16 点阵字库绘制到 RGBA 帧缓冲，
 *      经 frame_submit 上屏；
 *   3. 通过 dispatch_from_host 接收输入事件（pointer / scroll / key）；
 *   4. 通过 host_dispatch("kernel.state") 主动上报状态（宿主未注册时忽略回执）；
 *   5. eval_js 提供一组"命令式"接口（不是 JS 引擎），未知脚本诚实返回
 *      {"ok":false,"error":"unsupported script"}。
 *
 * 内存约定：所有返回给宿主的 const char* 都是库内 malloc 的新内存，宿主用
 * zb_free_ptr 释放；任何分配失败都走降级路径，不崩溃。
 * 线程约定：所有调用来自同一线程，内部不加锁。
 */
#include <stdlib.h>
#include <string.h>

#include "zb_lite_internal.h"

/* 引擎标识由 zb_lite_internal.h 提供（构建时可经 -D 覆盖） */
#define ZB_LITE_NAME ZB_ENGINE_NAME
#define ZB_LITE_VERSION ZB_ENGINE_VERSION
#define ZB_LITE_DISPLAY_NAME ZB_ENGINE_DISPLAY_NAME

#define ZB_FETCH_MAX_BYTES 2097152

/* 页面形态 */
enum {
    ZB_PAGE_DOC = 0,     /* 已排版文档 */
    ZB_PAGE_LOADING = 1, /* 等待宿主网络回包 */
    ZB_PAGE_ERROR = 2    /* 加载失败 */
};

typedef struct {
    char *url;
    char *html; /* NULL 表示内容尚未取得（等待网络） */
} zb_hist_entry;

struct zb_kernel_s {
    /* 宿主回调 */
    zb_host_dispatch_fn dispatch;
    int64_t next_request_id;

    /* 配置 */
    int dark;
    const zb_theme *theme;

    /* 输出表面 */
    int64_t texture_id;
    zb_frame_submit_fn frame_cb;
    int32_t width;
    int32_t height;
    int32_t stride;
    uint8_t *fb;
    int has_surface;

    /* 页面 */
    char *url;
    char *title;
    zb_doc doc;
    zb_layout layout;
    int layout_width;
    int layout_dirty;
    int scroll_y;
    int doc_height;
    int page_kind;
    char error_text[192];

    /* 历史 */
    zb_hist_entry hist[ZB_MAX_HISTORY];
    int nhist;
    int hist_pos; /* -1 表示空 */

    /* 网络 */
    int loading;
    int64_t pending_request;

    /* 交互 */
    int down_x;
    int down_y;
    int down_valid;

    /* 其他 */
    int frame;
    int need_state;
};

/* ============================================================
 *  小工具
 * ============================================================ */

static int zb_streq(const char *a, const char *b) {
    if (a == NULL || b == NULL) return 0;
    return strcmp(a, b) == 0;
}

static void zb_set_str(char **dst, const char *src) {
    char *copy = (src != NULL) ? zb_strdup(src) : NULL;
    free(*dst);
    *dst = copy;
}

/* 拷贝字符串但限制长度（历史条目里的 HTML 缓存用，避免超大页面把内存撑爆） */
static char *zb_strdup_capped(const char *src, size_t cap) {
    size_t n;
    if (src == NULL) return NULL;
    n = strlen(src);
    if (n > cap) n = cap;
    return zb_strndup(src, n);
}

/* 输入是否"像 HTML" */
static int zb_looks_like_html(const char *s) {
    size_t i;
    size_t len;
    if (s == NULL) return 0;
    len = strlen(s);
    for (i = 0; i + 1 < len; ++i) {
        if (s[i] == '<') {
            char n = s[i + 1];
            if ((n >= 'a' && n <= 'z') || (n >= 'A' && n <= 'Z') || n == '/' ||
                n == '!' || n == '?') {
                return 1;
            }
        }
    }
    return 0;
}

/* 输入是否"像个地址"（无空格且含 . 或 : 或 localhost） */
static int zb_looks_like_url(const char *s) {
    size_t i;
    int has_dot = 0;
    int has_colon = 0;
    if (s == NULL || s[0] == '\0') return 0;
    for (i = 0; s[i] != '\0'; ++i) {
        if (s[i] == ' ' || s[i] == '\t' || s[i] == '\n') return 0;
        if (s[i] == '.') has_dot = 1;
        if (s[i] == ':') has_colon = 1;
    }
    if (zb_has_prefix_ci(s, "localhost")) return 1;
    return (has_dot || has_colon) ? 1 : 0;
}

/* 取 URL 的主机名 */
static void zb_host_of(const char *url, char *out, size_t outsz) {
    const char *p;
    size_t o = 0;
    if (outsz == 0) return;
    out[0] = '\0';
    if (url == NULL) return;
    p = strstr(url, "://");
    p = (p != NULL) ? (p + 3) : url;
    while (*p != '\0' && *p != '/' && *p != '?' && *p != '#' && o + 1 < outsz) {
        out[o++] = *p++;
    }
    out[o] = '\0';
    /* 去掉 user@ 前缀 */
    {
        char *at = strchr(out, '@');
        if (at != NULL) {
            size_t n = strlen(at + 1);
            memmove(out, at + 1, n + 1);
        }
    }
}

/* ============================================================
 *  状态上报
 * ============================================================ */

static void zb_report_state(zb_kernel_t k) {
    zb_buf b;
    if (k == NULL || k->dispatch == NULL) return;
    zb_buf_init(&b);
    (void)zb_buf_puts(&b, "{\"url\":");
    (void)zb_buf_put_json_string(&b, k->url != NULL ? k->url : "");
    (void)zb_buf_puts(&b, ",\"title\":");
    (void)zb_buf_put_json_string(&b, k->title != NULL ? k->title : "");
    (void)zb_buf_puts(&b, ",\"can_back\":");
    (void)zb_buf_puts(&b, (k->hist_pos > 0) ? "true" : "false");
    (void)zb_buf_puts(&b, ",\"can_forward\":");
    (void)zb_buf_puts(&b, (k->hist_pos >= 0 && k->hist_pos + 1 < k->nhist) ? "true"
                                                                          : "false");
    (void)zb_buf_puts(&b, ",\"loading\":");
    (void)zb_buf_puts(&b, k->loading ? "true" : "false");
    (void)zb_buf_puts(&b, ",\"scroll_y\":");
    (void)zb_buf_put_int(&b, k->scroll_y);
    (void)zb_buf_puts(&b, ",\"doc_height\":");
    (void)zb_buf_put_int(&b, k->doc_height);
    (void)zb_buf_puts(&b, ",\"error\":");
    if (k->page_kind == ZB_PAGE_ERROR && k->error_text[0] != '\0') {
        (void)zb_buf_put_json_string(&b, k->error_text);
    } else {
        (void)zb_buf_puts(&b, "null");
    }
    (void)zb_buf_puts(&b, ",\"kernel\":");
    (void)zb_buf_put_json_string(&b, ZB_LITE_NAME);
    (void)zb_buf_puts(&b, "}");
    k->dispatch(k->next_request_id++, "kernel.state", zb_buf_cstr(&b));
    zb_buf_free(&b);
}

/* ============================================================
 *  历史
 * ============================================================ */

static void zb_hist_clear(zb_kernel_t k) {
    int i;
    for (i = 0; i < k->nhist; ++i) {
        free(k->hist[i].url);
        free(k->hist[i].html);
        k->hist[i].url = NULL;
        k->hist[i].html = NULL;
    }
    k->nhist = 0;
    k->hist_pos = -1;
}

static void zb_hist_push(zb_kernel_t k, const char *url, const char *html) {
    int i;
    for (i = k->hist_pos + 1; i < k->nhist; ++i) {
        free(k->hist[i].url);
        free(k->hist[i].html);
        k->hist[i].url = NULL;
        k->hist[i].html = NULL;
    }
    k->nhist = (k->hist_pos + 1 > 0) ? (k->hist_pos + 1) : 0;
    if (k->nhist >= ZB_MAX_HISTORY) {
        free(k->hist[0].url);
        free(k->hist[0].html);
        for (i = 1; i < k->nhist; ++i) k->hist[i - 1] = k->hist[i];
        k->nhist--;
        if (k->hist_pos > 0) k->hist_pos--;
    }
    k->hist[k->nhist].url = zb_strdup(url != NULL ? url : "");
    k->hist[k->nhist].html =
        (html != NULL) ? zb_strdup_capped(html, (size_t)ZB_MAX_HIST_HTML) : NULL;
    k->nhist++;
    k->hist_pos = k->nhist - 1;
}

/* 更新当前条目的内容 */
static void zb_hist_update(zb_kernel_t k, const char *url, const char *html) {
    if (k->hist_pos < 0 || k->hist_pos >= k->nhist) return;
    if (url != NULL) zb_set_str(&k->hist[k->hist_pos].url, url);
    if (html != NULL) {
        char *copy = zb_strdup_capped(html, (size_t)ZB_MAX_HIST_HTML);
        free(k->hist[k->hist_pos].html);
        k->hist[k->hist_pos].html = copy;
    }
}

/* ============================================================
 *  标题 / 滚动
 * ============================================================ */

/* 第一个 h1 的文本（没有 h1 时取第一个标题块） */
static void zb_title_from_headings(zb_kernel_t k, char *out, size_t outsz) {
    int pass;
    if (outsz == 0) return;
    out[0] = '\0';
    for (pass = 0; pass < 2; ++pass) {
        size_t i;
        for (i = 0; i < k->doc.nblocks; ++i) {
            const zb_block *b = &k->doc.blocks[i];
            size_t o = 0;
            size_t j;
            if (b->kind != ZB_NODE_HEADING) continue;
            if (pass == 0 && b->level != 1) continue;
            for (j = 0; j < b->nruns && o + 1 < outsz; ++j) {
                const zb_run *r = &b->runs[j];
                size_t n = r->tlen;
                if (n > outsz - 1 - o) n = outsz - 1 - o;
                if (r->text != NULL && n > 0) {
                    memcpy(out + o, r->text, n);
                    o += n;
                }
            }
            out[o] = '\0';
            if (o > 0) return;
        }
    }
}

static void zb_update_title(zb_kernel_t k) {
    char tmp[ZB_MAX_TITLE_LEN];
    if (k == NULL) return;
    if (k->doc.title != NULL && k->doc.title[0] != '\0') {
        zb_set_str(&k->title, k->doc.title);
        return;
    }
    tmp[0] = '\0';
    zb_title_from_headings(k, tmp, sizeof(tmp));
    if (tmp[0] != '\0') {
        zb_set_str(&k->title, tmp);
        return;
    }
    {
        char host[256];
        zb_host_of(k->url, host, sizeof(host));
        if (host[0] != '\0') {
            zb_set_str(&k->title, host);
        } else if (k->url != NULL && k->url[0] != '\0') {
            zb_set_str(&k->title, k->url);
        } else {
            zb_set_str(&k->title, "New Tab");
        }
    }
}

static int zb_max_scroll(zb_kernel_t k) {
    int m = k->doc_height - (int)k->height;
    if (m < 0) m = 0;
    return m;
}

static void zb_clamp_scroll(zb_kernel_t k) {
    int m;
    if (k == NULL) return;
    if (k->page_kind != ZB_PAGE_DOC) {
        k->scroll_y = 0;
        return;
    }
    m = zb_max_scroll(k);
    if (k->scroll_y < 0) k->scroll_y = 0;
    if (k->scroll_y > m) k->scroll_y = m;
}

/* ============================================================
 *  渲染
 * ============================================================ */

static void zb_rebuild_layout(zb_kernel_t k) {
    int w;
    if (k == NULL) return;
    w = (k->width > 0) ? (int)k->width : 800;
    k->doc_height = zb_layout_build(&k->layout, &k->doc, w, k->theme);
    k->layout_width = w;
    k->layout_dirty = 0;
    zb_clamp_scroll(k);
}

static void zb_render(zb_kernel_t k) {
    zb_canvas c;
    if (k == NULL || !k->has_surface || k->fb == NULL || k->frame_cb == NULL) return;
    if (k->width <= 0 || k->height <= 0) return;
    c.fb = k->fb;
    c.w = k->width;
    c.h = k->height;
    c.stride = k->stride;

    if (k->page_kind == ZB_PAGE_LOADING) {
        zb_render_loading(&c, k->theme, k->url, k->frame / 2, 0, NULL);
    } else if (k->page_kind == ZB_PAGE_ERROR) {
        zb_render_loading(&c, k->theme, k->url, k->frame / 2, 1, k->error_text);
    } else {
        if (k->layout_dirty || k->layout_width != (int)k->width) {
            zb_rebuild_layout(k);
        }
        zb_render_layout(&c, &k->layout, k->theme, k->scroll_y);
        zb_render_scrollbar(&c, k->theme, k->doc_height, k->scroll_y, (int)k->height);
    }
    k->frame_cb(k->texture_id, k->fb, k->width, k->height, k->stride);
}

/* ============================================================
 *  内容装载
 * ============================================================ */

static void zb_set_error_page(zb_kernel_t k, const char *message) {
    if (k == NULL) return;
    k->loading = 0;
    k->page_kind = ZB_PAGE_ERROR;
    k->pending_request = 0;
    if (message != NULL) {
        size_t n = strlen(message);
        if (n > sizeof(k->error_text) - 1) n = sizeof(k->error_text) - 1;
        memcpy(k->error_text, message, n);
        k->error_text[n] = '\0';
    } else {
        k->error_text[0] = '\0';
    }
    k->layout_dirty = 1;
    k->need_state = 1;
}

/* 取出 URL 中 '#' 之后的部分（没有则返回 NULL） */
static const char *zb_fragment_of(const char *url) {
    const char *h;
    if (url == NULL) return NULL;
    h = strchr(url, '#');
    if (h == NULL) return NULL;
    return h + 1;
}

/* 跳到锚点；返回 0 表示找到并跳转 */
static int zb_jump_anchor(zb_kernel_t k, const char *frag) {
    size_t i;
    if (k == NULL || frag == NULL || frag[0] == '\0') {
        k->scroll_y = 0;
        return 0;
    }
    for (i = 0; i < k->doc.nanchors; ++i) {
        if (strcmp(k->doc.anchors[i].id, frag) == 0) {
            size_t b = k->doc.anchors[i].block;
            if (k->layout_dirty || k->layout_width != (int)k->width) {
                zb_rebuild_layout(k);
            }
            if (b < k->layout.nblock_y) {
                k->scroll_y = k->layout.block_y[b] - 6;
                zb_clamp_scroll(k);
            }
            return 0;
        }
    }
    return -1;
}

/*
 * 设定页面内容。
 *   is_html != 0  -> 按 HTML 解析；否则按纯文本
 *   push != 0     -> 压入新历史条目；否则更新当前条目
 */
static void zb_set_content(zb_kernel_t k, const char *url, const char *content,
                           int is_html, int push) {
    if (k == NULL) return;
    if (url != NULL) zb_set_str(&k->url, url);
    {
        const char *body = (content != NULL) ? content : "";
        if (is_html) {
            (void)zb_doc_parse_html(&k->doc, body);
        } else {
            (void)zb_doc_parse_plain(&k->doc, body);
        }
    }
    if (push) {
        zb_hist_push(k, k->url, content);
    } else {
        zb_hist_update(k, k->url, content);
    }
    k->loading = 0;
    k->pending_request = 0;
    k->page_kind = ZB_PAGE_DOC;
    k->error_text[0] = '\0';
    k->scroll_y = 0;
    k->layout_dirty = 1;
    zb_update_title(k);
    zb_rebuild_layout(k);
    {
        const char *frag = zb_fragment_of(k->url);
        if (frag != NULL && frag[0] != '\0') (void)zb_jump_anchor(k, frag);
    }
    k->need_state = 1;
}

/* 空白页 / 首页 */
static void zb_load_home(zb_kernel_t k, int push) {
    static const char *const HOME =
        "<h1>zb_lite_kernel</h1>"
        "<p>Lite text kernel is ready. Type an address to load a page.</p>"
        "<p>This kernel renders HTML text with an 8x16 bitmap font and fetches "
        "pages through <code>net.fetch</code>. It has no JavaScript engine, no "
        "CSS layout, and CJK characters are drawn as placeholder boxes.</p>"
        "<hr>"
        "<p>Supported inline tags: a b strong i em u code span. Block tags: "
        "p div h1-h6 ul ol li blockquote pre table tr td th hr img.</p>";
    zb_set_content(k, "about:blank", HOME, 1, push);
    k->page_kind = ZB_PAGE_DOC;
}

/* 发起 net.fetch */
static void zb_start_fetch(zb_kernel_t k, const char *url, int push) {
    zb_buf b;
    int64_t rid;
    if (k == NULL) return;
    zb_set_str(&k->url, url);
    if (push) {
        zb_hist_push(k, url, NULL);
    } else {
        zb_hist_update(k, url, NULL);
    }
    k->page_kind = ZB_PAGE_LOADING;
    k->loading = 1;
    k->scroll_y = 0;
    k->error_text[0] = '\0';
    k->layout_dirty = 1;
    {
        char host[256];
        zb_host_of(url, host, sizeof(host));
        zb_set_str(&k->title, host[0] != '\0' ? host : (url != NULL ? url : ""));
    }
    k->need_state = 1;

    if (k->dispatch == NULL) {
        zb_set_error_page(k, "host dispatch unavailable");
        return;
    }
    rid = k->next_request_id++;
    k->pending_request = rid;
    zb_buf_init(&b);
    (void)zb_buf_puts(&b, "{\"url\":");
    (void)zb_buf_put_json_string(&b, url != NULL ? url : "");
    (void)zb_buf_puts(&b, ",\"method\":\"GET\",\"max_bytes\":");
    (void)zb_buf_put_int(&b, ZB_FETCH_MAX_BYTES);
    (void)zb_buf_puts(&b, "}");
    k->dispatch(rid, "net.fetch", zb_buf_cstr(&b));
    zb_buf_free(&b);
}

/* data: URL 解码（支持 base64 与百分号编码） */
static int zb_b64_value(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static char *zb_b64_decode(const char *s, size_t len) {
    zb_buf out;
    int acc = 0;
    int bits = 0;
    size_t i;
    zb_buf_init(&out);
    for (i = 0; i < len; ++i) {
        int v;
        if (s[i] == '=' || s[i] == '\n' || s[i] == '\r' || s[i] == ' ') continue;
        v = zb_b64_value(s[i]);
        if (v < 0) continue;
        acc = (acc << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            (void)zb_buf_putc(&out, (char)((acc >> bits) & 0xFF));
        }
    }
    return zb_buf_detach(&out);
}

static int zb_hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static char *zb_url_decode(const char *s, size_t len, int plus_is_space) {    zb_buf out;
    size_t i = 0;
    zb_buf_init(&out);
    while (i < len) {
        if (s[i] == '%' && i + 2 < len) {
            int hi = zb_hex_value(s[i + 1]);
            int lo = zb_hex_value(s[i + 2]);
            if (hi >= 0 && lo >= 0) {
                (void)zb_buf_putc(&out, (char)((hi << 4) | lo));
                i += 3;
                continue;
            }
        }
        if (plus_is_space && s[i] == '+') {
            (void)zb_buf_putc(&out, ' ');
            ++i;
            continue;
        }
        (void)zb_buf_putc(&out, s[i]);
        ++i;
    }
    return zb_buf_detach(&out);
}

/* 在长度受限的区间内忽略大小写查找子串 */
static int zb_contains_ci_n(const char *s, size_t n, const char *needle) {
    size_t nl;
    size_t i;
    if (s == NULL || needle == NULL) return 0;
    nl = strlen(needle);
    if (nl == 0 || n < nl) return 0;
    for (i = 0; i + nl <= n; ++i) {
        size_t j;
        for (j = 0; j < nl; ++j) {
            if (zb_ascii_lower(s[i + j]) != zb_ascii_lower(needle[j])) break;
        }
        if (j == nl) return 1;
    }
    return 0;
}

static void zb_load_data_url(zb_kernel_t k, const char *url) {
    const char *comma = strchr(url, ',');
    if (comma == NULL) {
        zb_set_error_page(k, "malformed data: URL");
        return;
    }
    {
        size_t head_len = (size_t)(comma - url);
        const char *data = comma + 1;
        size_t data_len = strlen(data);
        int is_base64 = 0;
        int is_html = 0;
        char *decoded;
        if (zb_contains_ci_n(url, head_len, "base64")) is_base64 = 1;
        if (zb_contains_ci_n(url, head_len, "html")) is_html = 1;
        if (is_base64) {
            decoded = zb_b64_decode(data, data_len);
        } else {
            decoded = zb_url_decode(data, data_len, 0);
        }
        if (decoded == NULL) {
            zb_set_error_page(k, "data: decode failed");
            return;
        }
        if (!is_html && zb_looks_like_html(decoded)) is_html = 1;
        zb_set_content(k, url, decoded, is_html, 1);
        free(decoded);
    }
}

/* ============================================================
 *  URL 解析（相对 -> 绝对）
 * ============================================================ */

/* 判断 href 是否带 scheme（字母开头的 scheme:） */
static int zb_has_scheme(const char *s) {
    size_t i = 0;
    if (s == NULL || s[0] == '\0') return 0;
    if (!((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z'))) return 0;
    while (s[i] != '\0') {
        char c = s[i];
        if (c == ':') return (i > 0) ? 1 : 0;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.')) {
            return 0;
        }
        ++i;
    }
    return 0;
}

static void zb_origin_of(const char *url, zb_buf *out) {
    const char *p;
    const char *end;
    zb_buf_clear(out);
    if (url == NULL) return;
    p = strstr(url, "://");
    if (p == NULL) return;
    end = p + 3;
    while (*end != '\0' && *end != '/' && *end != '?' && *end != '#') ++end;
    (void)zb_buf_put(out, url, (size_t)(end - url));
}

static char *zb_resolve_url(const char *base, const char *href) {
    zb_buf out;
    size_t start = 0;
    size_t n;
    if (href == NULL) return NULL;
    n = zb_trim_len(href, strlen(href), &start);
    href += start;
    if (n == 0) return zb_strdup(base != NULL ? base : "");
    zb_buf_init(&out);

    if (href[0] == '#') {
        /* 页内跳转：保留 base 去掉 fragment 的部分 */
        if (base != NULL) {
            const char *h = strchr(base, '#');
            size_t blen = (h != NULL) ? (size_t)(h - base) : strlen(base);
            (void)zb_buf_put(&out, base, blen);
        }
        (void)zb_buf_put(&out, href, n);
    } else if (zb_has_scheme(href)) {
        (void)zb_buf_put(&out, href, n);
    } else if (n >= 2 && href[0] == '/' && href[1] == '/') {
        zb_buf origin;
        zb_buf_init(&origin);
        zb_origin_of(base, &origin);
        (void)zb_buf_puts(&out, zb_buf_cstr(&origin));
        (void)zb_buf_put(&out, href, n);
        zb_buf_free(&origin);
    } else if (href[0] == '/') {
        zb_buf origin;
        zb_buf_init(&origin);
        zb_origin_of(base, &origin);
        (void)zb_buf_puts(&out, zb_buf_cstr(&origin));
        (void)zb_buf_put(&out, href, n);
        zb_buf_free(&origin);
    } else if (base != NULL && strstr(base, "://") != NULL) {
        const char *after_scheme = strstr(base, "://") + 3;
        if (href[0] == '?') {
            /* 相对查询串：base 去掉 ? 与 # 后拼接 */
            const char *q = strpbrk(base, "?#");
            size_t blen = (q != NULL) ? (size_t)(q - base) : strlen(base);
            (void)zb_buf_put(&out, base, blen);
            (void)zb_buf_put(&out, href, n);
        } else {
            /* 目录 = base 中最后一个 '/' 之前（含 '/'），且不早于 origin */
            const char *last_slash = NULL;
            const char *r;
            for (r = after_scheme; *r != '\0'; ++r) {
                if (*r == '?' || *r == '#') break;
                if (*r == '/') last_slash = r;
            }
            if (last_slash != NULL) {
                (void)zb_buf_put(&out, base, (size_t)(last_slash - base + 1));
            } else {
                zb_buf origin;
                zb_buf_init(&origin);
                zb_origin_of(base, &origin);
                (void)zb_buf_puts(&out, zb_buf_cstr(&origin));
                (void)zb_buf_putc(&out, '/');
                zb_buf_free(&origin);
            }
            (void)zb_buf_put(&out, href, n);
        }
    } else {
        /* base 不是绝对 URL：原样使用 href */
        (void)zb_buf_put(&out, href, n);
    }

    if (out.data == NULL) {
        zb_buf_free(&out);
        return zb_strdup(href);
    }
    return zb_buf_detach(&out);
}

/* ============================================================
 *  导航
 * ============================================================ */

static void zb_navigate(zb_kernel_t k, const char *href, int push) {
    char *resolved;
    if (k == NULL || href == NULL) return;
    resolved = zb_resolve_url(k->url, href);
    if (resolved == NULL) return;
    if (resolved[0] == '#') {
        free(resolved);
        return;
    }
    if (zb_has_prefix_ci(resolved, "http://") ||
        zb_has_prefix_ci(resolved, "https://")) {
        zb_start_fetch(k, resolved, push);
    } else if (zb_has_prefix_ci(resolved, "data:")) {
        zb_load_data_url(k, resolved);
    } else if (zb_has_prefix_ci(resolved, "about:")) {
        zb_load_home(k, push);
    } else if (zb_looks_like_html(resolved)) {
        zb_set_content(k, "about:inline", resolved, 1, push);
    } else if (zb_has_scheme(resolved)) {
        /* mailto: / javascript: / file: 等：不做处理，如实登记 */
        zb_set_error_page(k, "unsupported URL scheme");
    } else {
        zb_set_content(k, "about:text", resolved, 0, push);
    }
    free(resolved);
}

/* 点击链接：命中则导航 */
static void zb_handle_click(zb_kernel_t k, int x, int y) {
    int cy;
    size_t i;
    if (k == NULL) return;
    if (k->page_kind != ZB_PAGE_DOC) return;
    if (k->layout_dirty || k->layout_width != (int)k->width) zb_rebuild_layout(k);
    cy = y + k->scroll_y;
    for (i = k->layout.nops; i > 0; --i) {
        const zb_op *op = &k->layout.ops[i - 1];
        if (op->kind != ZB_OP_TEXT || op->link < 0) continue;
        if (x < op->x || x >= op->x + op->w) continue;
        if (cy < op->y || cy >= op->y + op->h) continue;
        if ((size_t)op->link < k->layout.nlinks) {
            const char *href = k->layout.links[op->link];
            const char *frag = zb_fragment_of(href);
            if (href[0] == '#') {
                /* 页内跳转：URL 更新 + 历史 + 滚动 */
                if (frag != NULL) {
                    zb_buf u;
                    char *keep_html = NULL;
                    if (k->hist_pos >= 0 && k->hist_pos < k->nhist &&
                        k->hist[k->hist_pos].html != NULL) {
                        keep_html = zb_strdup(k->hist[k->hist_pos].html);
                    }
                    zb_buf_init(&u);
                    {
                        const char *h = (k->url != NULL) ? strchr(k->url, '#') : NULL;
                        size_t blen = (h != NULL)
                                          ? (size_t)(h - k->url)
                                          : (k->url != NULL ? strlen(k->url) : 0);
                        if (k->url != NULL) (void)zb_buf_put(&u, k->url, blen);
                    }
                    (void)zb_buf_putc(&u, '#');
                    (void)zb_buf_puts(&u, frag);
                    zb_set_str(&k->url, zb_buf_cstr(&u));
                    zb_hist_push(k, k->url, keep_html);
                    free(keep_html);
                    zb_buf_free(&u);
                    (void)zb_jump_anchor(k, frag);
                    k->need_state = 1;
                }
            } else if (zb_has_prefix_ci(href, "javascript:") ||
                       zb_has_prefix_ci(href, "mailto:") ||
                       zb_has_prefix_ci(href, "tel:")) {
                /* 无 JS 引擎：如实忽略 */
            } else {
                zb_navigate(k, href, 1);
            }
        }
        break;
    }
    zb_render(k);
}

static void zb_scroll_by(zb_kernel_t k, int dy) {
    if (k == NULL) return;
    if (k->page_kind != ZB_PAGE_DOC) return;
    if (k->layout_dirty || k->layout_width != (int)k->width) zb_rebuild_layout(k);
    k->scroll_y += dy;
    zb_clamp_scroll(k);
    k->need_state = 1;
    zb_render(k);
}

static void zb_handle_key(zb_kernel_t k, const char *key) {
    int page;
    if (k == NULL || key == NULL) return;
    if (k->layout_dirty || k->layout_width != (int)k->width) zb_rebuild_layout(k);
    page = (int)k->height - 40;
    if (page < 20) page = 20;
    if (zb_ascii_ieq(key, "Home")) {
        k->scroll_y = 0;
    } else if (zb_ascii_ieq(key, "End")) {
        k->scroll_y = zb_max_scroll(k);
    } else if (zb_ascii_ieq(key, "PageUp")) {
        k->scroll_y -= page;
    } else if (zb_ascii_ieq(key, "PageDown")) {
        k->scroll_y += page;
    } else if (zb_ascii_ieq(key, "ArrowUp") || zb_ascii_ieq(key, "Up")) {
        k->scroll_y -= 48;
    } else if (zb_ascii_ieq(key, "ArrowDown") || zb_ascii_ieq(key, "Down")) {
        k->scroll_y += 48;
    } else {
        return;
    }
    zb_clamp_scroll(k);
    k->need_state = 1;
    zb_render(k);
}

/* 输入事件 */
static void zb_handle_input(zb_kernel_t k, const zb_json *msg, const char *event) {
    if (zb_streq(event, "pointer")) {
        const char *type = zb_json_get_str(msg, "type");
        int x = zb_json_get_int(msg, "x", -9999);
        int y = zb_json_get_int(msg, "y", -9999);
        if (zb_streq(type, "down")) {
            k->down_x = x;
            k->down_y = y;
            k->down_valid = 1;
        } else if (zb_streq(type, "up")) {
            if (k->down_valid) {
                int dx = x - k->down_x;
                int dy = y - k->down_y;
                if (dx < 0) dx = -dx;
                if (dy < 0) dy = -dy;
                if (dx <= 12 && dy <= 12) zb_handle_click(k, x, y);
            }
            k->down_valid = 0;
            k->need_state = 1;
        } else if (zb_streq(type, "move")) {
            /* 悬停无高亮实现，忽略 */
        }
    } else if (zb_streq(event, "scroll")) {
        int dy = zb_json_get_int(msg, "dy", 0);
        (void)zb_json_get_int(msg, "dx", 0);
        zb_scroll_by(k, dy);
    } else if (zb_streq(event, "key")) {
        zb_handle_key(k, zb_json_get_str(msg, "key"));
    } else if (zb_streq(event, "resize")) {
        k->layout_dirty = 1;
        zb_render(k);
    }
}

/* ============================================================
 *  网络回包
 * ============================================================ */

static void zb_handle_fetch_result(zb_kernel_t k, const zb_json *result,
                                   const char *error) {
    const char *body;
    const char *final_url;
    const char *ctype;
    int status;
    int is_html = 1;
    if (k == NULL) return;
    if (error != NULL) {
        zb_set_error_page(k, error);
        return;
    }
    if (result == NULL || result->kind != ZB_JSON_OBJ) {
        zb_set_error_page(k, "empty net.fetch result");
        return;
    }
    status = zb_json_get_int(result, "status", 0);
    body = zb_json_get_str(result, "body");
    final_url = zb_json_get_str(result, "final_url");
    ctype = zb_json_get_str(result, "content_type");
    if (final_url != NULL && final_url[0] != '\0') zb_set_str(&k->url, final_url);

    if (ctype != NULL) {
        if (zb_find_ci(ctype, "text/plain") >= 0) {
            is_html = 0;
        } else if (zb_find_ci(ctype, "html") >= 0) {
            is_html = 1;
        } else if (body != NULL) {
            is_html = zb_looks_like_html(body);
        }
    } else if (body != NULL) {
        is_html = zb_looks_like_html(body);
    }

    if (body == NULL || body[0] == '\0') {
        if (status > 0) {
            zb_buf m;
            zb_buf_init(&m);
            (void)zb_buf_puts(&m, "HTTP status ");
            (void)zb_buf_put_int(&m, status);
            zb_set_error_page(k, zb_buf_cstr(&m));
            zb_buf_free(&m);
        } else {
            zb_set_error_page(k, "empty response body");
        }
        return;
    }
    zb_set_content(k, k->url, body, is_html, 0);
}

/* ============================================================
 *  eval_js 支持的命令
 * ============================================================ */

static void zb_eval_ok_str(zb_buf *b, const char *v) {
    (void)zb_buf_puts(b, "{\"ok\":true,\"value\":");
    (void)zb_buf_put_json_string(b, v != NULL ? v : "");
    (void)zb_buf_puts(b, "}");
}

static void zb_eval_fail(zb_buf *b, const char *err) {
    (void)zb_buf_puts(b, "{\"ok\":false,\"error\":");
    (void)zb_buf_put_json_string(b, err != NULL ? err : "error");
    (void)zb_buf_puts(b, "}");
}

/* 解析 window.scrollTo(0,N) / window.scrollBy(0,N)，取最后一个整型参数 */
static int zb_parse_scroll_call(const char *s, const char *fname, int *value) {
    size_t fl = strlen(fname);
    const char *p;
    int found = 0;
    int val = 0;
    int sign = 1;
    if (s == NULL) return 0;
    if (strncmp(s, fname, fl) != 0) return 0;
    p = s + fl;
    while (*p == ' ' || *p == '\t') ++p;
    if (*p != '(') return 0;
    ++p;
    while (*p != '\0' && *p != ')') {
        if (*p == '-') {
            sign = -1;
            ++p;
            continue;
        }
        if (*p == '+') {
            ++p;
            continue;
        }
        if (*p >= '0' && *p <= '9') {
            long n = 0;
            while (*p >= '0' && *p <= '9') {
                if (n < 100000000L) n = n * 10 + (*p - '0');
                ++p;
            }
            val = (int)(sign * n);
            found = 1;
            sign = 1;
            continue;
        }
        ++p;
    }
    if (!found) return 0;
    *value = val;
    return 1;
}

/* document.links：页面所有链接（按出现顺序去重） */
static void zb_eval_links(zb_kernel_t k, zb_buf *b) {
    size_t i;
    size_t count = 0;
    (void)zb_buf_puts(b, "{\"ok\":true,\"value\":[");
    for (i = 0; i < k->doc.nblocks && count < 200; ++i) {
        const zb_block *blk = &k->doc.blocks[i];
        size_t j;
        for (j = 0; j < blk->nruns && count < 200; ++j) {
            const zb_run *r = &blk->runs[j];
            size_t m;
            int dup = 0;
            if (r->href == NULL || r->href[0] == '\0') continue;
            for (m = 0; m < i; ++m) {
                const zb_block *pb = &k->doc.blocks[m];
                size_t q;
                for (q = 0; q < pb->nruns; ++q) {
                    if (pb->runs[q].href != NULL &&
                        strcmp(pb->runs[q].href, r->href) == 0) {
                        dup = 1;
                        break;
                    }
                }
                if (dup) break;
            }
            {
                size_t q;
                for (q = 0; q < j; ++q) {
                    if (blk->runs[q].href != NULL &&
                        strcmp(blk->runs[q].href, r->href) == 0) {
                        dup = 1;
                        break;
                    }
                }
            }
            if (dup) continue;
            if (count > 0) (void)zb_buf_putc(b, ',');
            (void)zb_buf_puts(b, "{\"href\":");
            (void)zb_buf_put_json_string(b, r->href);
            (void)zb_buf_puts(b, ",\"text\":");
            {
                zb_buf txt;
                size_t q;
                zb_buf_init(&txt);
                for (q = j; q < blk->nruns && txt.len < 200; ++q) {
                    if (blk->runs[q].href != NULL &&
                        strcmp(blk->runs[q].href, r->href) == 0 &&
                        blk->runs[q].text != NULL) {
                        (void)zb_buf_put(&txt, blk->runs[q].text,
                                         blk->runs[q].tlen);
                    }
                }
                (void)zb_buf_put_json_string(b, zb_buf_cstr(&txt));
                zb_buf_free(&txt);
            }
            (void)zb_buf_puts(b, "}");
            ++count;
        }
    }
    (void)zb_buf_puts(b, "],\"count\":");
    (void)zb_buf_put_int(b, (long long)count);
    (void)zb_buf_puts(b, "}");
}

/* ============================================================
 *  ABI：16 个导出符号
 * ============================================================ */

ZB_API int32_t zb_abi_version(void) { return ZB_ABI_VERSION; }

ZB_API zb_kernel_t zb_kernel_create(const char *config_json,
                                   zb_host_dispatch_fn host_dispatch) {
    zb_kernel_t k = (zb_kernel_t)calloc(1, sizeof(struct zb_kernel_s));
    if (k == NULL) return NULL;

    k->dispatch = host_dispatch;
    k->next_request_id = 1;
    k->dark = 0;
    k->theme = zb_theme_for(0);
    k->texture_id = 0;
    k->frame_cb = NULL;
    k->width = 0;
    k->height = 0;
    k->stride = 0;
    k->fb = NULL;
    k->has_surface = 0;
    k->url = NULL;
    k->title = NULL;
    k->layout_width = 0;
    k->layout_dirty = 1;
    k->scroll_y = 0;
    k->doc_height = 1;
    k->page_kind = ZB_PAGE_DOC;
    k->error_text[0] = '\0';
    k->nhist = 0;
    k->hist_pos = -1;
    k->loading = 0;
    k->pending_request = 0;
    k->down_x = 0;
    k->down_y = 0;
    k->down_valid = 0;
    k->frame = 0;
    k->need_state = 0;
    zb_doc_init(&k->doc);
    zb_layout_init(&k->layout);

    /* 配置：{"dark":true} 等 */
    if (config_json != NULL && config_json[0] != '\0') {
        zb_json_arena arena;
        zb_json *root;
        const char *err = NULL;
        zb_json_arena_init(&arena);
        root = zb_json_parse(config_json, &arena, &err);
        if (root != NULL && root->kind == ZB_JSON_OBJ) {
            if (zb_json_get_bool(root, "dark", 0)) k->dark = 1;
        }
        zb_json_arena_free(&arena);
    }
    k->theme = zb_theme_for(k->dark);

    /* 初始首页 */
    zb_set_str(&k->url, "about:blank");
    zb_set_str(&k->title, "New Tab");
    zb_load_home(k, 1);
    k->need_state = 0;
    return k;
}

ZB_API void zb_kernel_destroy(zb_kernel_t k) {
    if (k == NULL) return;
    zb_hist_clear(k);
    zb_doc_reset(&k->doc);
    zb_layout_free(&k->layout);
    free(k->url);
    free(k->title);
    free(k->fb);
    free(k);
}

ZB_API const char *zb_kernel_name(zb_kernel_t k) {
    (void)k;
    return zb_strdup(ZB_LITE_NAME);
}

ZB_API const char *zb_kernel_version(zb_kernel_t k) {
    (void)k;
    return zb_strdup(ZB_LITE_VERSION);
}

ZB_API int32_t zb_kernel_load_url(zb_kernel_t k, const char *url) {
    size_t start = 0;
    size_t n;
    if (k == NULL) return -1;
    if (url == NULL) {
        zb_load_home(k, 1);
        zb_render(k);
        return 0;
    }
    n = zb_trim_len(url, strlen(url), &start);
    url += start;
    if (n == 0) {
        zb_load_home(k, 1);
        zb_render(k);
        return 0;
    }
    if (zb_has_prefix_ci(url, "http://") || zb_has_prefix_ci(url, "https://")) {
        zb_start_fetch(k, url, 1);
    } else if (zb_has_prefix_ci(url, "data:")) {
        zb_load_data_url(k, url);
    } else if (zb_looks_like_html(url)) {
        zb_set_content(k, "about:inline", url, 1, 1);
    } else if (zb_has_prefix_ci(url, "about:")) {
        zb_load_home(k, 1);
    } else if (zb_looks_like_url(url)) {
        /* 用户直接输入域名：补 https:// */
        zb_buf b;
        zb_buf_init(&b);
        (void)zb_buf_puts(&b, "https://");
        (void)zb_buf_put(&b, url, n);
        zb_start_fetch(k, zb_buf_cstr(&b), 1);
        zb_buf_free(&b);
    } else if (zb_has_scheme(url)) {
        zb_set_error_page(k, "unsupported URL scheme");
    } else {
        /* 既不是地址也不像 HTML：按纯文本页显示 */
        zb_set_content(k, "about:text", url, 0, 1);
    }
    zb_render(k);
    zb_report_state(k);
    return 0;
}

ZB_API int32_t zb_kernel_go_back(zb_kernel_t k) {
    if (k == NULL) return -1;
    if (k->hist_pos <= 0) return -1;
    k->hist_pos--;
    {
        const zb_hist_entry *e = &k->hist[k->hist_pos];
        if (e->url != NULL && (zb_has_prefix_ci(e->url, "http://") ||
                               zb_has_prefix_ci(e->url, "https://")) &&
            e->html == NULL) {
            char *u = zb_strdup(e->url);
            if (u != NULL) {
                zb_start_fetch(k, u, 0);
                free(u);
            }
        } else if (e->html != NULL) {
            zb_set_content(k, e->url, e->html, 1, 0);
        } else if (e->url != NULL && zb_has_prefix_ci(e->url, "about:")) {
            zb_load_home(k, 0);
        } else {
            return -1;
        }
    }
    k->need_state = 1;
    zb_render(k);
    zb_report_state(k);
    return 0;
}

ZB_API int32_t zb_kernel_go_forward(zb_kernel_t k) {
    if (k == NULL) return -1;
    if (k->hist_pos < 0 || k->hist_pos + 1 >= k->nhist) return -1;
    k->hist_pos++;
    {
        const zb_hist_entry *e = &k->hist[k->hist_pos];
        if (e->url != NULL && (zb_has_prefix_ci(e->url, "http://") ||
                               zb_has_prefix_ci(e->url, "https://")) &&
            e->html == NULL) {
            char *u = zb_strdup(e->url);
            if (u != NULL) {
                zb_start_fetch(k, u, 0);
                free(u);
            }
        } else if (e->html != NULL) {
            zb_set_content(k, e->url, e->html, 1, 0);
        } else if (e->url != NULL && zb_has_prefix_ci(e->url, "about:")) {
            zb_load_home(k, 0);
        } else {
            return -1;
        }
    }
    k->need_state = 1;
    zb_render(k);
    zb_report_state(k);
    return 0;
}

ZB_API int32_t zb_kernel_reload(zb_kernel_t k) {
    if (k == NULL) return -1;
    if (k->hist_pos < 0 || k->hist_pos >= k->nhist) {
        zb_load_home(k, 0);
        zb_render(k);
        return 0;
    }
    {
        const zb_hist_entry *e = &k->hist[k->hist_pos];
        if (e->url != NULL && (zb_has_prefix_ci(e->url, "http://") ||
                               zb_has_prefix_ci(e->url, "https://"))) {
            char *u = zb_strdup(e->url);
            if (u != NULL) {
                zb_start_fetch(k, u, 0);
                free(u);
            }
        } else if (e->html != NULL) {
            zb_set_content(k, e->url, e->html, 1, 0);
        } else {
            zb_load_home(k, 0);
        }
    }
    k->need_state = 1;
    zb_render(k);
    zb_report_state(k);
    return 0;
}

ZB_API const char *zb_kernel_eval_js(zb_kernel_t k, const char *script) {
    zb_buf out;
    char *result;
    if (k == NULL) return NULL;
    zb_buf_init(&out);
    if (script == NULL) {
        zb_eval_fail(&out, "unsupported script");
    } else {
        size_t start = 0;
        size_t n = zb_trim_len(script, strlen(script), &start);
        const char *s = script + start;
        char buf[256];
        size_t copy = (n < sizeof(buf) - 1) ? n : sizeof(buf) - 1;
        memcpy(buf, s, copy);
        buf[copy] = '\0';

        if (strcmp(buf, "document.title") == 0) {
            zb_eval_ok_str(&out, k->title != NULL ? k->title : "");
        } else if (strcmp(buf, "document.body.innerText") == 0 ||
                   strcmp(buf, "document.body.innerText;") == 0) {
            const char *text = zb_doc_text(&k->doc);
            size_t len = (text != NULL) ? strlen(text) : 0;
            if (len > 8000) len = 8000;
            (void)zb_buf_puts(&out, "{\"ok\":true,\"value\":");
            {
                char *tmp = zb_strndup(text != NULL ? text : "", len);
                (void)zb_buf_put_json_string(&out, tmp != NULL ? tmp : "");
                free(tmp);
            }
            (void)zb_buf_puts(&out, "}");
        } else if (strcmp(buf, "document.links") == 0) {
            zb_eval_links(k, &out);
        } else if (strcmp(buf, "location.href") == 0) {
            zb_eval_ok_str(&out, k->url != NULL ? k->url : "");
        } else {
            int value = 0;
            if (zb_parse_scroll_call(buf, "window.scrollTo", &value) ||
                zb_parse_scroll_call(buf, "scrollTo", &value)) {
                if (k->layout_dirty || k->layout_width != (int)k->width) {
                    zb_rebuild_layout(k);
                }
                k->scroll_y = value;
                zb_clamp_scroll(k);
                k->need_state = 1;
                zb_render(k);
                zb_report_state(k);
                (void)zb_buf_puts(&out, "{\"ok\":true,\"value\":");
                (void)zb_buf_put_int(&out, k->scroll_y);
                (void)zb_buf_puts(&out, "}");
            } else if (zb_parse_scroll_call(buf, "window.scrollBy", &value) ||
                       zb_parse_scroll_call(buf, "scrollBy", &value)) {
                if (k->layout_dirty || k->layout_width != (int)k->width) {
                    zb_rebuild_layout(k);
                }
                k->scroll_y += value;
                zb_clamp_scroll(k);
                k->need_state = 1;
                zb_render(k);
                zb_report_state(k);
                (void)zb_buf_puts(&out, "{\"ok\":true,\"value\":");
                (void)zb_buf_put_int(&out, k->scroll_y);
                (void)zb_buf_puts(&out, "}");
            } else {
                zb_eval_fail(&out, "unsupported script");
            }
        }
    }
    result = zb_buf_detach(&out);
    if (result == NULL) result = zb_strdup("{\"ok\":false,\"error\":\"out of memory\"}");
    return result;
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
                                        zb_frame_submit_fn frame_cb, int32_t width,
                                        int32_t height) {
    size_t need;
    if (k == NULL) return -1;
    if (frame_cb == NULL) return -2;
    if (width <= 0 || height <= 0) return -3;
    if (width > 16384 || height > 16384) return -3;
    need = (size_t)width * (size_t)height * 4u;

    k->texture_id = texture_id;
    if (k->fb == NULL || k->width != width || k->height != height) {
        uint8_t *fb = (uint8_t *)malloc(need);
        if (fb == NULL) {
            k->frame_cb = NULL;
            k->has_surface = 0;
            return -4;
        }
        memset(fb, 0, need);
        free(k->fb);
        k->fb = fb;
        k->width = width;
        k->height = height;
        k->stride = width * 4;
        k->layout_dirty = 1;
    }
    k->frame_cb = frame_cb;
    k->has_surface = 1;
    zb_rebuild_layout(k);
    zb_render(k);
    return 0;
}

ZB_API int32_t zb_kernel_tick(zb_kernel_t k) {
    if (k == NULL) return -1;
    k->frame++;
    if (k->frame > 1000000000) k->frame = 0;
    zb_render(k);
    if (k->need_state) {
        k->need_state = 0;
        zb_report_state(k);
    }
    return 0;
}

ZB_API int32_t zb_kernel_dispatch_from_host(zb_kernel_t k,
                                            const char *message_json) {
    zb_json_arena arena;
    zb_json *root;
    const char *err = NULL;
    int is_input = 0;
    if (k == NULL) return -1;
    if (message_json == NULL) return -1;
    zb_json_arena_init(&arena);
    root = zb_json_parse(message_json, &arena, &err);
    if (root == NULL) {
        zb_json_arena_free(&arena);
        return -1;
    }
    if (root->kind == ZB_JSON_OBJ) {
        const char *event = zb_json_get_str(root, "event");
        if (event != NULL && event[0] != '\0') {
            zb_handle_input(k, root, event);
            is_input = 1;
        } else {
            int rid = zb_json_get_int(root, "request_id", -1);
            const char *e = zb_json_get_str(root, "error");
            zb_json *result = zb_json_obj_get(root, "result");
            if (rid >= 0 && (int64_t)rid == k->pending_request) {
                zb_handle_fetch_result(k, result, e);
                zb_render(k);
                zb_report_state(k);
            }
            /* 其它 request_id（例如 kernel.state 的回执）容错忽略 */
        }
    }
    zb_json_arena_free(&arena);
    /* 输入事件引起的变化立刻回报一次状态（宿主未注册时其回执同样是错误，被忽略） */
    if (is_input && k->need_state) {
        k->need_state = 0;
        zb_report_state(k);
    }
    return 0;
}

ZB_API void zb_free_ptr(void *ptr) { free(ptr); }
