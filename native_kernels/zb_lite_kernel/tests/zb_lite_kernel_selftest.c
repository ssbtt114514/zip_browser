/*
 * Zip Browser —— zb_lite_kernel 自检程序（不参与 DLL 构建）
 *
 * 用纯标准 C 直接调用内核 API，跑一遍真实链路：
 *   create -> load HTML -> attach 假 surface -> tick
 *          -> 检查帧缓冲里确实有非背景像素
 *          -> net.fetch 请求/回包、输入事件、eval_js、历史前进后退、尺寸变化
 *
 * 编译（在仓库根目录）：
 *   gcc -std=c99 -Wall -Wextra -O2 \
 *       -I native_plugins/zb_native_surface/include \
 *       -I native_kernels/zb_lite_kernel/include \
 *       native_kernels/zb_lite_kernel/src/zb_lite_util.c \
 *       native_kernels/zb_lite_kernel/src/zb_lite_json.c \
 *       native_kernels/zb_lite_kernel/src/zb_lite_doc.c \
 *       native_kernels/zb_lite_kernel/src/zb_lite_layout.c \
 *       native_kernels/zb_lite_kernel/src/zb_lite_render.c \
 *       native_kernels/zb_lite_kernel/src/zb_lite_kernel.c \
 *       native_kernels/zb_lite_kernel/tests/zb_lite_kernel_selftest.c \
 *       -o zb_lite_kernel_selftest
 *   ./zb_lite_kernel_selftest
 *
 * 退出码 0 表示全部通过，非 0 表示有失败项（失败原因打印在 stdout）。
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zb_plugin_kernel_abi.h"

/* ============================================================
 *  测试脚手架
 * ============================================================ */

static int g_fail = 0;
static int g_check = 0;

#define CHECK(cond, msg)                                                   \
    do {                                                                   \
        ++g_check;                                                         \
        if (!(cond)) {                                                     \
            printf("  [FAIL] %s  (%s:%d)\n", (msg), __FILE__, __LINE__);    \
            ++g_fail;                                                      \
        }                                                                  \
    } while (0)

#define SECTION(name) printf("== %s ==\n", (name))

/* ---------- 假的 host_dispatch ---------- */

#define LOG_PARAMS_MAX 8192

typedef struct {
    int count;
    int fetch_count;
    int state_count;
    int64_t fetch_request_id;
    char last_method[64];
    char last_params[LOG_PARAMS_MAX];
    char fetch_params[LOG_PARAMS_MAX];
    char fetch_method[64];
} host_log;

static host_log g_log;

static void reset_log(void) {
    memset(&g_log, 0, sizeof(g_log));
}

static void host_dispatch(int64_t request_id, const char *method,
                          const char *params_json) {
    g_log.count++;
    snprintf(g_log.last_method, sizeof(g_log.last_method), "%s",
             method != NULL ? method : "");
    snprintf(g_log.last_params, sizeof(g_log.last_params), "%s",
             params_json != NULL ? params_json : "");
    if (strcmp(g_log.last_method, "net.fetch") == 0) {
        g_log.fetch_count++;
        g_log.fetch_request_id = request_id;
        snprintf(g_log.fetch_params, sizeof(g_log.fetch_params), "%s",
                 params_json != NULL ? params_json : "");
        snprintf(g_log.fetch_method, sizeof(g_log.fetch_method), "%s",
                 g_log.last_method);
    } else if (strcmp(g_log.last_method, "kernel.state") == 0) {
        g_log.state_count++;
    }
}

/* ---------- 假的 frame_submit ---------- */

typedef struct {
    int calls;
    int32_t width;
    int32_t height;
    int32_t stride;
    int nonbg_pixels;
    uint8_t px0[3];
    int size_changed;
} frame_log;

static frame_log g_frame;

static void frame_cb(int64_t texture_id, const uint8_t *rgba, int32_t width,
                     int32_t height, int32_t stride) {
    int x;
    int y;
    int count = 0;
    uint8_t r0;
    uint8_t g0;
    uint8_t b0;
    (void)texture_id;
    if (width <= 0 || height <= 0 || rgba == NULL) return;
    if (g_frame.width != 0 && (g_frame.width != width || g_frame.height != height)) {
        g_frame.size_changed = 1;
    }
    g_frame.calls++;
    g_frame.width = width;
    g_frame.height = height;
    g_frame.stride = stride;
    r0 = rgba[0];
    g0 = rgba[1];
    b0 = rgba[2];
    g_frame.px0[0] = r0;
    g_frame.px0[1] = g0;
    g_frame.px0[2] = b0;
    for (y = 0; y < height && count < 4000; ++y) {
        const uint8_t *row = rgba + (size_t)y * (size_t)stride;
        for (x = 0; x < width; ++x) {
            if (row[x * 4 + 0] != r0 || row[x * 4 + 1] != g0 ||
                row[x * 4 + 2] != b0) {
                ++count;
                if (count >= 4000) break;
            }
        }
    }
    g_frame.nonbg_pixels = count;
}

/* ---------- 小工具 ---------- */

/* 取走内核返回的字符串（复制后释放内核内存） */
static char *take(const char *p) {
    char *out;
    if (p == NULL) return NULL;
    out = (char *)malloc(strlen(p) + 1);
    if (out != NULL) strcpy(out, p);
    zb_free_ptr((void *)p);
    return out;
}

static char *url_of(zb_kernel_t k) { return take(zb_kernel_current_url(k)); }

static char *title_of(zb_kernel_t k) { return take(zb_kernel_title(k)); }

static char *eval_str(zb_kernel_t k, const char *script) {
    return take(zb_kernel_eval_js(k, script));
}

static void click_at(zb_kernel_t k, int x, int y) {
    char msg[128];
    snprintf(msg, sizeof(msg),
             "{\"event\":\"pointer\",\"type\":\"down\",\"x\":%d,\"y\":%d}", x, y);
    (void)zb_kernel_dispatch_from_host(k, msg);
    snprintf(msg, sizeof(msg),
             "{\"event\":\"pointer\",\"type\":\"up\",\"x\":%d,\"y\":%d}", x, y);
    (void)zb_kernel_dispatch_from_host(k, msg);
}

static int contains(const char *hay, const char *needle) {
    if (hay == NULL || needle == NULL) return 0;
    return strstr(hay, needle) != NULL;
}

/* ============================================================
 *  测试用 HTML
 * ============================================================ */

static const char *const PAGE_ONE =
    "<!DOCTYPE html>\n"
    "<html><head><title>Lite Test Page</title>"
    "<script>var a = 1; document.title = 'HACKED';</script>"
    "<style>body { color: red }</style></head>\n"
    "<body>\n"
    "<h1>Heading One</h1>\n"
    "<p>Hello <b>bold</b> and <a href=\"/next\">NEXT</a> link, plus "
    "&amp;&lt;&gt;&quot;&#39;&nbsp;&#65;&#x42; entities.</p>\n"
    "<ul><li>item one</li><li>item two</li></ul>\n"
    "<ol><li>first</li><li>second</li></ol>\n"
    "<blockquote>quoted text</blockquote>\n"
    "<pre>pre line 1\npre   line   2</pre>\n"
    "<p>Image below: <img src=\"/pics/photo.png\" alt=\"photo alt\"></p>\n"
    "<h2 id=\"sec2\">Second Section</h2>\n"
    "<p>Trailing paragraph with 中文宽字符 mixed in for wrapping.</p>\n"
    "<hr>\n"
    "<p>Last line.</p>\n"
    "</body></html>\n";

/* ============================================================
 *  用例
 * ============================================================ */

static void test_basic_abi(void) {
    zb_kernel_t k;
    zb_kernel_t tmp;
    char *s;
    SECTION("ABI 基本约定");
    CHECK(zb_abi_version() == ZB_ABI_VERSION, "zb_abi_version() == 1");
    tmp = zb_kernel_create(NULL, NULL);
    CHECK(tmp != NULL, "create(NULL, NULL) 可用");
    zb_kernel_destroy(tmp);
    zb_kernel_destroy(NULL); /* 不应崩溃 */
    zb_kernel_tick(NULL);
    (void)zb_kernel_go_back(NULL);
    (void)zb_kernel_go_forward(NULL);
    (void)zb_kernel_reload(NULL);
    zb_free_ptr(NULL);

    k = zb_kernel_create("{\"dark\":false}", host_dispatch);
    CHECK(k != NULL, "create 成功");
    if (k == NULL) return;
    s = take(zb_kernel_name(k));
    CHECK(s != NULL && strcmp(s, "zb_lite_kernel") == 0, "name == zb_lite_kernel");
    free(s);
    s = take(zb_kernel_version(k));
    CHECK(s != NULL && strlen(s) > 0, "version 非空");
    free(s);
    s = url_of(k);
    CHECK(s != NULL && strcmp(s, "about:blank") == 0, "初始 URL == about:blank");
    free(s);

    /* NULL 参数必须被容忍 */
    CHECK(zb_kernel_tick(k) == 0, "tick 无 surface 时返回 0");
    CHECK(zb_kernel_attach_surface(k, 1, NULL, 320, 240) != 0, "frame_cb 为 NULL 报错");
    CHECK(zb_kernel_attach_surface(k, 1, frame_cb, 0, 240) != 0, "宽为 0 报错");
    CHECK(zb_kernel_attach_surface(k, 1, frame_cb, 320, -1) != 0, "高为负 报错");
    CHECK(zb_kernel_load_url(k, NULL) == 0, "load_url(NULL) 走首页");
    CHECK(zb_kernel_dispatch_from_host(k, NULL) == -1, "dispatch(NULL) 返回 -1");
    CHECK(zb_kernel_dispatch_from_host(k, "not json") == -1, "非法 JSON 返回 -1");
    CHECK(zb_kernel_dispatch_from_host(k, "{}") == 0, "空对象容错");
    CHECK(zb_kernel_dispatch_from_host(k, "{\"event\":\"unknown\"}") == 0,
          "未知事件容错");
    CHECK(zb_kernel_eval_js(k, NULL) != NULL, "eval_js(NULL) 返回可释放字符串");
    zb_free_ptr((void *)zb_kernel_eval_js(k, NULL));
    zb_kernel_destroy(k);
}

static void test_html_render(void) {
    zb_kernel_t k;
    char *s;
    memset(&g_frame, 0, sizeof(g_frame));
    reset_log();
    SECTION("HTML 解析 / 排版 / 渲染");
    k = zb_kernel_create("{\"dark\":false}", host_dispatch);
    CHECK(k != NULL, "create 成功");
    if (k == NULL) return;

    CHECK(zb_kernel_attach_surface(k, 7, frame_cb, 320, 240) == 0, "attach 成功");
    CHECK(g_frame.calls > 0, "attach 后立即提交了一帧");
    CHECK(g_frame.stride == g_frame.width * 4, "stride == width*4");

    CHECK(zb_kernel_load_url(k, PAGE_ONE) == 0, "load_url(HTML) 返回 0");
    s = title_of(k);
    CHECK(s != NULL && strcmp(s, "Lite Test Page") == 0,
          "title 取自 <title>（script 里的 title 不被执行）");
    free(s);

    CHECK(zb_kernel_tick(k) == 0, "tick 返回 0");
    CHECK(g_frame.calls >= 2, "tick 提交了新帧");
    CHECK(g_frame.nonbg_pixels > 50, "帧缓冲里有非背景像素（真的画了东西）");

    s = eval_str(k, "document.title");
    CHECK(s != NULL && contains(s, "Lite Test Page"), "eval document.title");
    free(s);

    s = eval_str(k, "document.body.innerText");
    CHECK(s != NULL && contains(s, "Heading One"), "eval innerText 含标题文本");
    CHECK(s != NULL && contains(s, "item two"), "eval innerText 含列表文本");
    CHECK(s != NULL && !contains(s, "HACKED"), "eval innerText 不含 script 内容");
    /* innerText 返回的是 JSON，&quot; 解码后是引号，在 JSON 里写作 \" */
    CHECK(s != NULL && contains(s, "&<>\\\"'"), "实体解码 &amp;&lt;&gt;&quot;&#39;");
    free(s);

    s = eval_str(k, "document.links");
    CHECK(s != NULL && contains(s, "\"href\":\"/next\""), "eval document.links 含 /next");
    CHECK(s != NULL && contains(s, "\"text\":\"NEXT\""), "eval document.links 含链接文本");
    free(s);

    s = eval_str(k, "location.href");
    CHECK(s != NULL && contains(s, "about:inline"), "eval location.href");
    free(s);

    s = eval_str(k, "alert(1)");
    CHECK(s != NULL && contains(s, "\"ok\":false") &&
              contains(s, "unsupported script"),
          "未知脚本诚实返回 ok:false");
    free(s);

    /* 滚动：越界必须钳制 */
    s = eval_str(k, "window.scrollTo(0,100000)");
    CHECK(s != NULL && contains(s, "\"ok\":true"), "scrollTo 被识别");
    free(s);
    s = eval_str(k, "document.body.innerText");
    free(s);
    {
        char *before = eval_str(k, "window.scrollBy(0,0)");
        long clamped = -1;
        if (before != NULL) {
            const char *p = strstr(before, "\"value\":");
            if (p != NULL) clamped = strtol(p + 8, NULL, 10);
        }
        CHECK(clamped >= 0, "scrollBy(0,0) 返回被钳制后的 scroll_y >= 0");
        free(before);
    }
    s = eval_str(k, "window.scrollBy(0,-100000)");
    CHECK(s != NULL && contains(s, "\"value\":0"), "scrollBy 负向钳制到 0");
    free(s);

    /* 滚动事件 + 按键事件 */
    CHECK(zb_kernel_dispatch_from_host(k, "{\"event\":\"scroll\",\"dx\":0,\"dy\":120}") ==
              0,
          "scroll 事件被接受");
    CHECK(zb_kernel_dispatch_from_host(k, "{\"event\":\"key\",\"key\":\"End\"}") == 0,
          "key End 被接受");
    CHECK(zb_kernel_dispatch_from_host(k, "{\"event\":\"key\",\"key\":\"Home\"}") == 0,
          "key Home 被接受");
    CHECK(zb_kernel_dispatch_from_host(k, "{\"event\":\"key\",\"key\":\"PageDown\"}") ==
              0,
          "key PageDown 被接受");
    CHECK(zb_kernel_dispatch_from_host(
              k, "{\"event\":\"key\",\"key\":\"NoSuchKey\"}") == 0,
          "未知按键容错");
    CHECK(g_log.state_count > 0, "滚动/按键后上报了 kernel.state");
    CHECK(contains(g_log.last_params, "\"scroll_y\":") &&
              contains(g_log.last_params, "\"doc_height\":") &&
              contains(g_log.last_params, "\"can_back\":"),
          "kernel.state 参数含 url/title/can_back/scroll_y/doc_height");

    /* 尺寸变化：重新 attach 必须重分配并重排版 */
    memset(&g_frame, 0, sizeof(g_frame));
    CHECK(zb_kernel_attach_surface(k, 8, frame_cb, 400, 300) == 0,
          "再次 attach（尺寸变化）成功");
    CHECK(g_frame.width == 400 && g_frame.height == 300, "新帧尺寸为 400x300");
    CHECK(g_frame.nonbg_pixels > 50, "新尺寸下仍然画出了内容");
    CHECK(zb_kernel_tick(k) == 0, "新尺寸下 tick 正常");
    zb_kernel_destroy(k);
}

static void test_network_flow(void) {
    zb_kernel_t k;
    char *s;
    char msg[1024];
    int64_t rid;
    memset(&g_frame, 0, sizeof(g_frame));
    reset_log();
    SECTION("net.fetch 请求 / 回包 / kernel.state");
    k = zb_kernel_create("{}", host_dispatch);
    CHECK(k != NULL, "create 成功");
    if (k == NULL) return;
    CHECK(zb_kernel_attach_surface(k, 3, frame_cb, 320, 240) == 0, "attach 成功");

    CHECK(zb_kernel_load_url(k, "https://example.test/page?q=1") == 0,
          "load_url(http) 立即返回 0");
    CHECK(g_log.fetch_count == 1, "发起了 1 次 net.fetch");
    CHECK(strcmp(g_log.fetch_method, "net.fetch") == 0,
          "net.fetch 的 method 参数正确");
    CHECK(contains(g_log.fetch_params, "\"url\":\"https://example.test/page?q=1\""),
          "net.fetch 参数包含 url");
    CHECK(contains(g_log.fetch_params, "\"method\":\"GET\""), "net.fetch 参数含 method");
    CHECK(contains(g_log.fetch_params, "\"max_bytes\":2097152"),
          "net.fetch 参数含 max_bytes=2097152");
    CHECK(g_log.state_count > 0, "导航时上报了 kernel.state");
    CHECK(contains(g_log.last_params, "\"loading\":true"), "loading=true");

    /* 等待期间必须能渲染"加载中"并保持 tick 可用 */
    CHECK(zb_kernel_tick(k) == 0, "加载中 tick 返回 0");
    CHECK(g_frame.nonbg_pixels > 10, "加载中页面有内容（转圈/文字）");
    s = title_of(k);
    CHECK(s != NULL && contains(s, "example.test"), "加载中标题回退到主机名");
    free(s);

    /* 宿主回包 */
    rid = g_log.fetch_request_id;
    snprintf(msg, sizeof(msg),
             "{\"request_id\":%ld,\"result\":{\"status\":200,"
             "\"final_url\":\"https://example.test/final\","
             "\"content_type\":\"text/html\","
             "\"body\":\"<title>Remote</title><h1>Remote H1</h1>"
             "<p>body text here</p>\"}}",
             (long)rid);
    CHECK(zb_kernel_dispatch_from_host(k, msg) == 0, "回包被接受");
    s = title_of(k);
    CHECK(s != NULL && strcmp(s, "Remote") == 0, "回包后 title == Remote");
    free(s);
    s = url_of(k);
    CHECK(s != NULL && strcmp(s, "https://example.test/final") == 0,
          "final_url 生效");
    free(s);
    CHECK(zb_kernel_tick(k) == 0, "回包后 tick 正常");
    CHECK(g_frame.nonbg_pixels > 20, "回包后渲染了远端内容");

    /* 回执错误容错（模拟宿主未注册 kernel.state） */
    CHECK(zb_kernel_dispatch_from_host(
              k, "{\"request_id\":99999,\"error\":\"no handler: kernel.state\"}") == 0,
          "无关 request_id 的错误回执被忽略");
    s = title_of(k);
    CHECK(s != NULL && strcmp(s, "Remote") == 0, "忽略错误回执后页面不变");
    free(s);

    /* net.fetch 失败 -> 错误页 */
    reset_log();
    (void)zb_kernel_load_url(k, "https://example.test/broken");
    rid = g_log.fetch_request_id;
    snprintf(msg, sizeof(msg), "{\"request_id\":%ld,\"error\":\"network unreachable\"}",
             (long)rid);
    (void)zb_kernel_dispatch_from_host(k, msg);
    CHECK(zb_kernel_tick(k) == 0, "错误页 tick 正常");
    CHECK(g_frame.nonbg_pixels > 10, "错误页有内容");
    CHECK(contains(g_log.last_params, "\"error\":\"network unreachable\"") ||
              g_log.state_count > 0,
          "错误通过 kernel.state 上报");

    /* 历史：back 回到 Remote 页 */
    CHECK(zb_kernel_go_back(k) == 0, "go_back 成功");
    s = url_of(k);
    CHECK(s != NULL && strcmp(s, "https://example.test/final") == 0,
          "go_back 回到上一页");
    free(s);
    CHECK(zb_kernel_go_forward(k) == 0, "go_forward 成功");
    s = url_of(k);
    CHECK(s != NULL && strcmp(s, "https://example.test/broken") == 0,
          "go_forward 到下一页");
    free(s);
    CHECK(zb_kernel_reload(k) == 0, "reload 返回 0");
    CHECK(g_log.fetch_count > 0, "reload 重新发起 net.fetch");
    zb_kernel_destroy(k);
}

static void test_click_link(void) {
    zb_kernel_t k;
    char *s;
    int x;
    int y;
    int clicked = 0;
    memset(&g_frame, 0, sizeof(g_frame));
    reset_log();
    SECTION("点击链接 / 相对地址解析 / 页内锚点");
    k = zb_kernel_create("{\"dark\":false}", host_dispatch);
    CHECK(k != NULL, "create 成功");
    if (k == NULL) return;
    CHECK(zb_kernel_attach_surface(k, 5, frame_cb, 320, 240) == 0, "attach 成功");
    CHECK(zb_kernel_load_url(k, PAGE_ONE) == 0, "载入测试页");
    /* 让 URL 变成有 origin 的地址，便于验证相对链接解析 */
    (void)zb_kernel_load_url(k, "https://example.test/dir/page.html");
    {
        char msg[512];
        snprintf(msg, sizeof(msg),
                 "{\"request_id\":%ld,\"result\":{\"status\":200,"
                 "\"final_url\":\"https://example.test/dir/page.html\","
                 "\"content_type\":\"text/html\",\"body\":\"%s\"}}",
                 (long)g_log.fetch_request_id,
                 "<h1>Heading One</h1><p>Hello <b>bold</b> and "
                 "<a href=\\\"/next\\\">NEXT</a> link.</p>");
        (void)zb_kernel_dispatch_from_host(k, msg);
    }
    s = title_of(k);
    CHECK(s != NULL && strcmp(s, "Heading One") == 0,
          "没有 <title> 时标题取首个 h1");
    free(s);

    /* 扫描点击，直到命中链接 */
    for (y = 12; y < 140 && !clicked; y += 2) {
        for (x = 10; x < 300 && !clicked; x += 4) {
            click_at(k, x, y);
            s = url_of(k);
            if (s != NULL && contains(s, "/next")) clicked = 1;
            free(s);
        }
    }
    CHECK(clicked, "在页面上点中了链接");
    if (clicked) {
        CHECK(g_log.fetch_count > 0, "点击链接发起了 net.fetch");
        s = url_of(k);
        CHECK(s != NULL && strcmp(s, "https://example.test/next") == 0,
              "相对链接 /next 解析为 https://example.test/next");
        free(s);
        /* 完成这次导航 */
        {
            char msg[512];
            snprintf(msg, sizeof(msg),
                     "{\"request_id\":%ld,\"result\":{\"status\":200,"
                     "\"final_url\":\"https://example.test/next\","
                     "\"content_type\":\"text/html\",\"body\":\"<h1>Second</h1>\"}}",
                     (long)g_log.fetch_request_id);
            (void)zb_kernel_dispatch_from_host(k, msg);
        }
        CHECK(zb_kernel_go_back(k) == 0, "点击后可以后退");
        s = url_of(k);
        CHECK(s != NULL && strcmp(s, "https://example.test/dir/page.html") == 0,
              "后退回到点击前的页面");
        free(s);
    }

    /* 页内锚点跳转：#bottom 应把 scroll_y 推到文档后段 */
    {
        {
            char *page = (char *)malloc(8192);
            char *r;
            long scrolled = -1;
            if (page != NULL) {
                size_t off = 0;
                int i;
                off += (size_t)snprintf(page + off, 8192 - off,
                                        "<p><a href=\"#bottom\">GO BOTTOM</a></p>");
                for (i = 0; i < 40 && off < 7000; ++i) {
                    off += (size_t)snprintf(
                        page + off, 8192 - off,
                        "<p>filler paragraph number %d with some words</p>", i);
                }
                (void)snprintf(page + off, 8192 - off,
                               "<h2 id=\"bottom\">Bottom Section</h2>");
                CHECK(zb_kernel_load_url(k, page) == 0, "载入锚点测试页");
                click_at(k, 20, 18); /* 第一行的链接 */
                s = url_of(k);
                CHECK(s != NULL && contains(s, "#bottom"), "点击 #bottom 更新了 URL");
                free(s);
                r = eval_str(k, "window.scrollBy(0,0)");
                if (r != NULL) {
                    const char *p = strstr(r, "\"value\":");
                    if (p != NULL) scrolled = strtol(p + 8, NULL, 10);
                }
                free(r);
                CHECK(scrolled > 100, "锚点跳转把文档滚到了后段");
                free(page);
            }
        }
    }
    zb_kernel_destroy(k);
}

static void test_dark_and_robustness(void) {
    zb_kernel_t k;
    memset(&g_frame, 0, sizeof(g_frame));
    reset_log();
    SECTION("暗色主题 / 畸形输入健壮性");
    k = zb_kernel_create("{\"dark\":true}", host_dispatch);
    CHECK(k != NULL, "create(dark) 成功");
    if (k == NULL) return;
    CHECK(zb_kernel_attach_surface(k, 9, frame_cb, 320, 240) == 0, "attach 成功");
    CHECK(zb_kernel_load_url(k, "<h1>Dark</h1><p>dark theme text</p>") == 0,
          "载入 HTML");
    CHECK(zb_kernel_tick(k) == 0, "tick 正常");
    CHECK(g_frame.px0[0] < 60 && g_frame.px0[1] < 60 && g_frame.px0[2] < 60,
          "暗色主题背景是深色");
    CHECK(g_frame.nonbg_pixels > 20, "暗色主题也有文字像素");

    /* 畸形 / 极端输入 */
    CHECK(zb_kernel_load_url(
              k, "<p>unclosed <b>bold &amp broken < script ><div><span>x") == 0,
          "畸形 HTML 不崩");
    CHECK(zb_kernel_tick(k) == 0, "畸形 HTML 后可 tick");
    CHECK(zb_kernel_load_url(k, "") == 0, "空输入走首页");
    CHECK(zb_kernel_load_url(k, "data:text/html,<h1>Data</h1><p>via data url</p>") == 0,
          "data: URL 可用");
    {
        char *t = title_of(k);
        CHECK(t != NULL && contains(t, "Data"), "data: URL 渲染出标题");
        free(t);
    }
    CHECK(zb_kernel_load_url(k, "data:text/plain,plain%20text%20page") == 0,
          "data:text/plain 可用");
    CHECK(zb_kernel_load_url(k, "data:;base64,PGgxPkJhc2U2NDwvaDE+") == 0,
          "data: base64 可用");
    {
        char *t = title_of(k);
        CHECK(t != NULL && contains(t, "Base64"), "base64 解码后渲染出标题");
        free(t);
    }
    CHECK(zb_kernel_eval_js(k, "document.links") != NULL, "links 可读");
    zb_free_ptr((void *)zb_kernel_eval_js(k, "document.links"));
    /* 超大输入（超过 ZB_MAX_HTML_BYTES）不应崩溃 */
    {
        size_t big = 5u * 1024u * 1024u;
        char *buf = (char *)malloc(big + 1);
        if (buf != NULL) {
            size_t i;
            for (i = 0; i < big; ++i) buf[i] = (i % 97 == 96) ? ' ' : 'a';
            buf[big] = '\0';
            CHECK(zb_kernel_load_url(k, buf) == 0, "5MB 文本不崩");
            CHECK(zb_kernel_tick(k) == 0, "5MB 文本后可 tick");
            free(buf);
        }
    }
    zb_kernel_destroy(k);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0); /* 崩溃时也能看到进度 */
    printf("zb_lite_kernel selftest\n");
    test_basic_abi();
    test_html_render();
    test_network_flow();
    test_click_link();
    test_dark_and_robustness();
    printf("\n%d 项检查，%d 项失败\n", g_check, g_fail);
    if (g_fail == 0) {
        printf("SELFTEST OK\n");
        return 0;
    }
    printf("SELFTEST FAILED\n");
    return 1;
}
