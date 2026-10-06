/*
 * Zip Browser —— zb_lite_kernel 内部头文件
 *
 * 仅内核自身使用，不对外导出。分层：
 *   util   : 动态缓冲 / 字符串 / UTF-8
 *   json   : 最小 JSON 解析与转义
 *   doc    : HTML -> 文档模型
 *   layout : 文档模型 -> 绘制指令（自动换行、列表、引用、pre、图片占位）
 *   render : 绘制指令 -> RGBA8888 帧缓冲（内置 8x16 点阵字库）
 *   kernel : C ABI 实现、导航历史、网络请求、输入事件、eval_js
 *
 * 约定：全部调用发生在同一线程，内核内部不加锁。
 * 所有字符串内存用 malloc/free，失败时降级而不是崩溃。
 */
#ifndef ZB_LITE_INTERNAL_H
#define ZB_LITE_INTERNAL_H

#include <stddef.h>
#include <stdint.h>

#include "zb_plugin_kernel_abi.h"

/* ============================================================
 *  引擎标识（可由构建系统用 -D 覆盖，用于派生同源内核变体）
 *  zb_engine_kernel 通过覆盖这些宏产出 chromium / gecko 标识内核；
 *  不覆盖时保持 lite 原始行为，零回归。
 * ============================================================ */
#ifndef ZB_ENGINE_NAME
#define ZB_ENGINE_NAME "zb_lite_kernel"
#endif
#ifndef ZB_ENGINE_VERSION
#define ZB_ENGINE_VERSION "1.0.0"
#endif
#ifndef ZB_ENGINE_DISPLAY_NAME
#define ZB_ENGINE_DISPLAY_NAME "轻量文本内核"
#endif
#ifndef ZB_ENGINE_HINT
#define ZB_ENGINE_HINT "zb_lite_kernel - lite text kernel (no JS engine)"
#endif

/* ============================================================
 *  通用上限（防止恶意 / 超大输入把内存打爆）
 * ============================================================ */
#define ZB_MAX_HTML_BYTES (4 * 1024 * 1024) /* 单页 HTML 上限 */
#define ZB_MAX_DOC_TEXT (64 * 1024)         /* innerText 构建上限 */
#define ZB_MAX_BLOCKS 20000                 /* 文档块上限 */
#define ZB_MAX_OPS 60000                    /* 绘制指令上限 */
#define ZB_MAX_LINKS 4096                   /* 链接上限 */
#define ZB_MAX_ANCHORS 4096                 /* 锚点上限 */
#define ZB_MAX_HISTORY 32                   /* 历史栈深度 */
#define ZB_MAX_HIST_HTML (1024 * 1024)      /* 每个历史条目缓存的 HTML 上限 */
#define ZB_MAX_URL_LEN 4096                 /* URL 长度上限 */
#define ZB_MAX_TITLE_LEN 512                /* 标题长度上限 */
#define ZB_JSON_MAX_DEPTH 64                /* JSON 嵌套深度上限 */
#define ZB_JSON_MAX_NODES 400000            /* JSON 节点上限 */

/* ============================================================
 *  util：动态缓冲 / 字符串 / UTF-8
 * ============================================================ */

/* 可增长字节缓冲（始终 NUL 结尾，data 为 NULL 表示分配失败） */
typedef struct {
    char *data;
    size_t len;
    size_t cap;
} zb_buf;

void zb_buf_init(zb_buf *b);
void zb_buf_free(zb_buf *b);
void zb_buf_clear(zb_buf *b);
int zb_buf_reserve(zb_buf *b, size_t extra);
int zb_buf_putc(zb_buf *b, char c);
int zb_buf_put(zb_buf *b, const char *s, size_t n);
int zb_buf_puts(zb_buf *b, const char *s);
int zb_buf_put_int(zb_buf *b, long long v);
/* 追加一个 JSON 字符串字面量（含两端引号，转义控制字符与引号/反斜杠） */
int zb_buf_put_json_string(zb_buf *b, const char *s);
/* 取 C 字符串视图（永不返回 NULL） */
const char *zb_buf_cstr(const zb_buf *b);
/* 把缓冲内容交出去（调用方负责 free），重置缓冲；失败返回 NULL */
char *zb_buf_detach(zb_buf *b);

char *zb_strdup(const char *s);
char *zb_strndup(const char *s, size_t n);
/* 忽略大小写的 ASCII 前缀判断；s 为 NULL 时返回 0 */
int zb_has_prefix_ci(const char *s, const char *prefix);
int zb_has_prefix(const char *s, const char *prefix);
/* 忽略大小写的子串查找；返回下标或 -1 */
int zb_find_ci(const char *hay, const char *needle);
/* 去除首尾空白后返回新分配的字符串（可能为空串，失败返回 NULL） */
char *zb_trim_dup(const char *s);
size_t zb_trim_len(const char *s, size_t n, size_t *start);
/* UTF-8：解码一个码点，*i 为游标（越界或非法时按单字节处理） */
uint32_t zb_utf8_next(const char *s, size_t len, size_t *i);
/* 码点编码为 UTF-8，返回字节数（1..4） */
size_t zb_utf8_encode(uint32_t cp, char out[4]);
/* 宽字符（CJK 等）占 2 个字符格 */
int zb_cp_is_wide(uint32_t cp);
/* ASCII 小写化（非 ASCII 原样返回） */
char zb_ascii_lower(char c);
int zb_ascii_ieq(const char *a, const char *b);

/* ============================================================
 *  json：最小 JSON 解析（只读、arena 分配）
 * ============================================================ */

typedef enum {
    ZB_JSON_NULL = 0,
    ZB_JSON_BOOL,
    ZB_JSON_NUM,
    ZB_JSON_STR,
    ZB_JSON_ARR,
    ZB_JSON_OBJ
} zb_json_kind;

typedef struct zb_json_s zb_json;
struct zb_json_s {
    zb_json_kind kind;
    int bval;      /* BOOL */
    double nval;   /* NUM */
    char *sval;    /* STR（已解码，UTF-8，arena 拥有） */
    char *key;     /* 作为对象成员时的键（arena 拥有） */
    zb_json *child;/* ARR/OBJ 的第一个子节点 */
    zb_json *next; /* 兄弟节点 */
};

/* 节点池：按固定大小分块分配（指针稳定，扩容不会使已用指针失效），
 * 一次性释放整池，避免递归 free。 */
struct zb_json_block_s;
typedef struct {
    struct zb_json_block_s *head; /* 块链头 */
    struct zb_json_block_s *cur;  /* 当前分配块 */
    size_t used;                  /* 当前块已用节点数 */
    size_t count;                 /* 总节点数 */
} zb_json_arena;

void zb_json_arena_init(zb_json_arena *a);
void zb_json_arena_free(zb_json_arena *a);
/* 解析 JSON 文本；失败返回 NULL（errors 可选，写入静态说明字符串） */
zb_json *zb_json_parse(const char *text, zb_json_arena *a, const char **error);

zb_json *zb_json_obj_get(const zb_json *obj, const char *key);
zb_json *zb_json_arr_at(const zb_json *arr, size_t index);
/* 便捷取值；类型不符时返回默认值 */
const char *zb_json_get_str(const zb_json *obj, const char *key);
int zb_json_get_int(const zb_json *obj, const char *key, int def);
double zb_json_get_num(const zb_json *obj, const char *key, double def);
int zb_json_get_bool(const zb_json *obj, const char *key, int def);

/* ============================================================
 *  doc：文档模型
 * ============================================================ */

/* 行内样式位 */
#define ZB_STYLE_BOLD 0x0001
#define ZB_STYLE_ITALIC 0x0002
#define ZB_STYLE_UNDERLINE 0x0004
#define ZB_STYLE_CODE 0x0008
#define ZB_STYLE_LINK 0x0010

typedef enum {
    ZB_NODE_PARAGRAPH = 0, /* 普通段落 / div / 表格单元 */
    ZB_NODE_HEADING,       /* h1..h6 */
    ZB_NODE_LIST_ITEM,     /* li */
    ZB_NODE_QUOTE,         /* blockquote 内的段落（indent>0 时也有引用缩进） */
    ZB_NODE_PRE,           /* 预格式化（不折行、等宽） */
    ZB_NODE_HR,            /* 水平线 */
    ZB_NODE_IMAGE          /* 图片占位 */
} zb_node_kind;

/* 行内文本片段（一段同一样式的文本） */
typedef struct {
    char *text;     /* 拥有，始终 NUL 结尾 */
    size_t tlen;    /* 文本长度（不含结尾 NUL） */
    size_t tcap;    /* 文本缓冲容量 */
    uint16_t style;
    char *href;     /* 链接地址（拥有），无链接为 NULL */
} zb_run;

typedef struct {
    zb_node_kind kind;
    int level;   /* 标题级别 1..6；有序列表元素的缩进级别无关 */
    int ordered; /* li：是否有序列表 */
    int index;   /* li：序号（从 1 开始） */
    int indent;  /* 引用 / 列表的缩进级数（每级 1） */
    char *alt;   /* 图片替换文本（拥有） */
    zb_run *runs;
    size_t nruns;
    size_t cruns;
} zb_block;

typedef struct {
    char *id;        /* 锚点名（拥有） */
    size_t block;    /* 对应块下标 */
} zb_anchor;

typedef struct {
    zb_block *blocks;
    size_t nblocks;
    size_t cblocks;
    zb_anchor *anchors;
    size_t nanchors;
    size_t canchors;
    char *title;      /* 拥有，可能为 NULL */
    char *text;       /* 惰性构建的纯文本（拥有） */
    int text_ready;
} zb_doc;

void zb_doc_init(zb_doc *d);
/* 释放内部内容并把文档重置为空（结构体本身仍可用） */
void zb_doc_reset(zb_doc *d);
/* 解析 HTML；返回 0 成功，负值失败（仍会得到尽力而为的文档） */
int zb_doc_parse_html(zb_doc *d, const char *html);
/* 把纯文本当作一个段落（换行按硬换行处理） */
int zb_doc_parse_plain(zb_doc *d, const char *text);
/* 惰性构建的纯文本（永不返回 NULL） */
const char *zb_doc_text(zb_doc *d);

/* ============================================================
 *  layout：排版
 * ============================================================ */

typedef enum {
    ZB_OP_TEXT = 0, /* 一段文字（含样式 / 颜色 / 链接） */
    ZB_OP_RECT,     /* 实心矩形（hr、列表圆点、代码块底色） */
    ZB_OP_FRAME,    /* 1px 边框矩形（图片占位框） */
    ZB_OP_HR        /* 水平线 */
} zb_op_kind;

typedef struct {
    zb_op_kind kind;
    int x, y, w, h;
    char *text;     /* ZB_OP_TEXT 拥有 */
    uint16_t style;
    int scale;      /* 字号倍率 1..3 */
    uint32_t color; /* 0xRRGGBB */
    int link;       /* 链接下标；-1 表示无 */
    int clip_x;     /* 右边界裁剪（pre 用）；<=0 表示不裁剪 */
} zb_op;

typedef struct {
    zb_op *ops;
    size_t nops;
    size_t cops;
    char **links; /* 链接地址表（拥有），op.link 为下标 */
    size_t nlinks;
    size_t clinks;
    int *block_y; /* 每个文档块的起始 y */
    size_t nblock_y;
    int doc_height;
    int width; /* 排版宽度 */
} zb_layout;

/* 主题（定义见下方 render 一节） */
struct zb_theme_s;

void zb_layout_init(zb_layout *L);
void zb_layout_free(zb_layout *L);
/* 按给定宽度重新排版；返回文档总高度（>=1） */
int zb_layout_build(zb_layout *L, const zb_doc *d, int width,
                    const struct zb_theme_s *th);

/* ============================================================
 *  render：主题与光栅化
 * ============================================================ */

/* 内置点阵字库的字符格尺寸（与 src/zb_lite_font.h 保持一致） */
#ifndef ZB_FONT_CELL_W
#  define ZB_FONT_CELL_W 8
#endif
#ifndef ZB_FONT_CELL_H
#  define ZB_FONT_CELL_H 16
#endif

typedef struct zb_theme_s {
    uint8_t bg[3];
    uint8_t fg[3];
    uint8_t heading[3];
    uint8_t link[3];
    uint8_t code_bg[3];
    uint8_t code_fg[3];
    uint8_t box[3];
    uint8_t border[3];
    uint8_t hr[3];
    uint8_t dim[3];
    uint8_t accent[3];
    int dark;
} zb_theme;

const zb_theme *zb_theme_for(int dark);

/* 帧缓冲视图（RGBA8888：内存顺序 R,G,B,A） */
typedef struct {
    uint8_t *fb;
    int32_t w;
    int32_t h;
    int32_t stride; /* 每行字节数 */
} zb_canvas;

void zb_canvas_clear(zb_canvas *c, const uint8_t rgb[3]);
void zb_canvas_px(zb_canvas *c, int x, int y, const uint8_t rgb[3]);
void zb_canvas_fill(zb_canvas *c, int x, int y, int w, int h, const uint8_t rgb[3]);

/* 文本像素宽度（含宽字符 2 格） */
int zb_text_width(const char *s, int scale);
int zb_char_cells(uint32_t cp);
int zb_line_height(int scale);

/* 在帧缓冲上绘制一行文本；clip_x>0 时右侧裁切 */
void zb_draw_text(zb_canvas *c, int x, int y, const char *s, int scale,
                  const uint8_t rgb[3], int bold, int underline, int clip_x);

/* 绘制排版结果；scroll_y 为纵向滚动量 */
void zb_render_layout(zb_canvas *c, const zb_layout *L, const zb_theme *th, int scroll_y);
/* 绘制"加载中"页面 */
void zb_render_loading(zb_canvas *c, const zb_theme *th, const char *url, int phase,
                       int error_text_needed, const char *message);
/* 绘制右侧滚动条 */
void zb_render_scrollbar(zb_canvas *c, const zb_theme *th, int doc_height,
                         int scroll_y, int view_height);

#endif /* ZB_LITE_INTERNAL_H */
