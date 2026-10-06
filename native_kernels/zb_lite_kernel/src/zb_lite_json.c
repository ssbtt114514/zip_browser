/*
 * Zip Browser —— zb_lite_kernel：最小 JSON 解析
 *
 * 用途：解析宿主回传的 dispatch_from_host 消息
 *   {"request_id":7,"result":{"status":200,"body":"..."}}
 *   {"request_id":7,"error":"..."}
 *   {"event":"pointer","type":"up","x":10,"y":20}
 * 以及内核自己的 config_json。
 *
 * 只做只读解析：节点从 arena 里分配（分块，指针稳定），字符串单独 malloc，
 * 释放时遍历块链一次性完成，不需要递归。
 *
 * 解码支持：\" \\ \/ \b \f \n \r \t \uXXXX（含代理对 -> UTF-8）。
 */
#include <stdlib.h>
#include <string.h>

#include "zb_lite_internal.h"

#define ZB_JSON_BLOCK_NODES 512

struct zb_json_block_s {
    zb_json nodes[ZB_JSON_BLOCK_NODES];
    struct zb_json_block_s *next;
};

/* ============================================================
 *  arena
 * ============================================================ */

void zb_json_arena_init(zb_json_arena *a) {
    if (a == NULL) return;
    a->head = NULL;
    a->cur = NULL;
    a->used = 0;
    a->count = 0;
}

void zb_json_arena_free(zb_json_arena *a) {
    struct zb_json_block_s *b;
    if (a == NULL) return;
    b = a->head;
    while (b != NULL) {
        struct zb_json_block_s *next = b->next;
        size_t i;
        for (i = 0; i < ZB_JSON_BLOCK_NODES; ++i) {
            free(b->nodes[i].sval);
            free(b->nodes[i].key);
            b->nodes[i].sval = NULL;
            b->nodes[i].key = NULL;
        }
        free(b);
        b = next;
    }
    a->head = NULL;
    a->cur = NULL;
    a->used = 0;
    a->count = 0;
}

static zb_json *zb_json_new(zb_json_arena *a) {
    struct zb_json_block_s *b;
    zb_json *n;
    if (a == NULL) return NULL;
    if (a->count >= (size_t)ZB_JSON_MAX_NODES) return NULL;
    if (a->cur == NULL || a->used >= (size_t)ZB_JSON_BLOCK_NODES) {
        b = (struct zb_json_block_s *)malloc(sizeof(struct zb_json_block_s));
        if (b == NULL) return NULL;
        /* 必须清零：arena_free 会遍历整块释放 sval/key */
        memset(b, 0, sizeof(*b));
        b->next = a->head;
        a->head = b;
        a->cur = b;
        a->used = 0;
    }
    n = &a->cur->nodes[a->used++];
    a->count++;
    memset(n, 0, sizeof(*n));
    n->kind = ZB_JSON_NULL;
    return n;
}

/* ============================================================
 *  解析器
 * ============================================================ */

typedef struct {
    const char *p;
    size_t len;
    size_t i;
    int depth;
    const char *error;
    zb_json_arena *arena;
} zb_jparse;

static void zb_jp_ws(zb_jparse *s) {
    while (s->i < s->len) {
        char c = s->p[s->i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            ++s->i;
        } else {
            break;
        }
    }
}

static int zb_jp_hex4(zb_jparse *s, uint32_t *out) {
    uint32_t v = 0;
    int k;
    if (s->i + 4 > s->len) return 0;
    for (k = 0; k < 4; ++k) {
        char c = s->p[s->i + (size_t)k];
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
    }
    s->i += 4;
    *out = v;
    return 1;
}

/* 解析字符串字面量（s->i 位于起始引号），把解码结果写入 out */
static int zb_jp_string(zb_jparse *s, zb_buf *out) {
    if (s->i >= s->len || s->p[s->i] != '"') {
        s->error = "expected string";
        return 0;
    }
    ++s->i;
    for (;;) {
        unsigned char c;
        if (s->i >= s->len) {
            s->error = "unterminated string";
            return 0;
        }
        c = (unsigned char)s->p[s->i];
        if (c == '"') {
            ++s->i;
            return 1;
        }
        if (c == '\\') {
            ++s->i;
            if (s->i >= s->len) {
                s->error = "bad escape";
                return 0;
            }
            c = (unsigned char)s->p[s->i++];
            switch (c) {
                case '"':
                    if (zb_buf_putc(out, '"') != 0) goto nomem;
                    break;
                case '\\':
                    if (zb_buf_putc(out, '\\') != 0) goto nomem;
                    break;
                case '/':
                    if (zb_buf_putc(out, '/') != 0) goto nomem;
                    break;
                case 'b':
                    if (zb_buf_putc(out, '\b') != 0) goto nomem;
                    break;
                case 'f':
                    if (zb_buf_putc(out, '\f') != 0) goto nomem;
                    break;
                case 'n':
                    if (zb_buf_putc(out, '\n') != 0) goto nomem;
                    break;
                case 'r':
                    if (zb_buf_putc(out, '\r') != 0) goto nomem;
                    break;
                case 't':
                    if (zb_buf_putc(out, '\t') != 0) goto nomem;
                    break;
                case 'u': {
                    uint32_t cp = 0;
                    char enc[4];
                    size_t n;
                    if (!zb_jp_hex4(s, &cp)) {
                        s->error = "bad \\u escape";
                        return 0;
                    }
                    if (cp >= 0xD800u && cp <= 0xDBFFu) {
                        uint32_t lo = 0;
                        if (s->i + 1 < s->len && s->p[s->i] == '\\' &&
                            s->p[s->i + 1] == 'u') {
                            s->i += 2;
                            if (!zb_jp_hex4(s, &lo)) {
                                s->error = "bad low surrogate";
                                return 0;
                            }
                            if (lo >= 0xDC00u && lo <= 0xDFFFu) {
                                cp = 0x10000u + ((cp - 0xD800u) << 10) +
                                     (lo - 0xDC00u);
                            } else {
                                cp = 0xFFFDu;
                            }
                        } else {
                            cp = 0xFFFDu;
                        }
                    } else if (cp >= 0xDC00u && cp <= 0xDFFFu) {
                        cp = 0xFFFDu;
                    }
                    n = zb_utf8_encode(cp, enc);
                    if (zb_buf_put(out, enc, n) != 0) goto nomem;
                    break;
                }
                default:
                    /* 宽松处理：未知转义按原字符保留 */
                    if (zb_buf_putc(out, (char)c) != 0) goto nomem;
                    break;
            }
            continue;
        }
        if (c < 0x20u) {
            s->error = "control char in string";
            return 0;
        }
        if (zb_buf_putc(out, (char)c) != 0) goto nomem;
        ++s->i;
    }
nomem:
    s->error = "out of memory";
    return 0;
}

static zb_json *zb_jp_value(zb_jparse *s);

static zb_json *zb_jp_array(zb_jparse *s) {
    zb_json *arr = zb_json_new(s->arena);
    zb_json *last = NULL;
    if (arr == NULL) {
        s->error = "out of memory";
        return NULL;
    }
    arr->kind = ZB_JSON_ARR;
    ++s->i; /* '[' */
    zb_jp_ws(s);
    if (s->i < s->len && s->p[s->i] == ']') {
        ++s->i;
        return arr;
    }
    for (;;) {
        zb_json *v;
        zb_jp_ws(s);
        v = zb_jp_value(s);
        if (v == NULL) return NULL;
        if (last == NULL) {
            arr->child = v;
        } else {
            last->next = v;
        }
        last = v;
        zb_jp_ws(s);
        if (s->i < s->len && s->p[s->i] == ',') {
            ++s->i;
            continue;
        }
        if (s->i < s->len && s->p[s->i] == ']') {
            ++s->i;
            return arr;
        }
        s->error = "expected ',' or ']'";
        return NULL;
    }
}

static zb_json *zb_jp_object(zb_jparse *s) {
    zb_json *obj = zb_json_new(s->arena);
    zb_json *last = NULL;
    if (obj == NULL) {
        s->error = "out of memory";
        return NULL;
    }
    obj->kind = ZB_JSON_OBJ;
    ++s->i; /* '{' */
    zb_jp_ws(s);
    if (s->i < s->len && s->p[s->i] == '}') {
        ++s->i;
        return obj;
    }
    for (;;) {
        zb_buf key;
        zb_json *v;
        zb_buf_init(&key);
        zb_jp_ws(s);
        if (!zb_jp_string(s, &key)) {
            zb_buf_free(&key);
            return NULL;
        }
        zb_jp_ws(s);
        if (s->i >= s->len || s->p[s->i] != ':') {
            s->error = "expected ':'";
            zb_buf_free(&key);
            return NULL;
        }
        ++s->i;
        zb_jp_ws(s);
        v = zb_jp_value(s);
        if (v == NULL) {
            zb_buf_free(&key);
            return NULL;
        }
        v->key = zb_buf_detach(&key);
        if (v->key == NULL) {
            s->error = "out of memory";
            return NULL;
        }
        if (last == NULL) {
            obj->child = v;
        } else {
            last->next = v;
        }
        last = v;
        zb_jp_ws(s);
        if (s->i < s->len && s->p[s->i] == ',') {
            ++s->i;
            continue;
        }
        if (s->i < s->len && s->p[s->i] == '}') {
            ++s->i;
            return obj;
        }
        s->error = "expected ',' or '}'";
        return NULL;
    }
}

static zb_json *zb_jp_number(zb_jparse *s) {
    zb_json *n = zb_json_new(s->arena);
    size_t start = s->i;
    int neg = 0;
    double v = 0.0;
    int any = 0;
    int exp = 0;
    int expneg = 0;
    if (n == NULL) {
        s->error = "out of memory";
        return NULL;
    }
    if (s->i < s->len && (s->p[s->i] == '-' || s->p[s->i] == '+')) {
        neg = (s->p[s->i] == '-');
        ++s->i;
    }
    while (s->i < s->len && s->p[s->i] >= '0' && s->p[s->i] <= '9') {
        v = v * 10.0 + (double)(s->p[s->i] - '0');
        any = 1;
        ++s->i;
    }
    if (s->i < s->len && s->p[s->i] == '.') {
        double scale = 0.1;
        ++s->i;
        while (s->i < s->len && s->p[s->i] >= '0' && s->p[s->i] <= '9') {
            v += (double)(s->p[s->i] - '0') * scale;
            scale /= 10.0;
            any = 1;
            ++s->i;
        }
    }
    if (!any) {
        s->i = start;
        s->error = "bad number";
        return NULL;
    }
    if (s->i < s->len && (s->p[s->i] == 'e' || s->p[s->i] == 'E')) {
        ++s->i;
        if (s->i < s->len && (s->p[s->i] == '-' || s->p[s->i] == '+')) {
            expneg = (s->p[s->i] == '-');
            ++s->i;
        }
        while (s->i < s->len && s->p[s->i] >= '0' && s->p[s->i] <= '9') {
            if (exp < 1000) exp = exp * 10 + (s->p[s->i] - '0');
            ++s->i;
        }
    }
    while (exp > 0) {
        if (expneg) {
            v /= 10.0;
        } else {
            v *= 10.0;
        }
        --exp;
    }
    n->kind = ZB_JSON_NUM;
    n->nval = neg ? -v : v;
    return n;
}

static zb_json *zb_jp_value(zb_jparse *s) {
    zb_json *n;
    char c;
    if (s->depth >= ZB_JSON_MAX_DEPTH) {
        s->error = "too deeply nested";
        return NULL;
    }
    if (s->i >= s->len) {
        s->error = "unexpected end of input";
        return NULL;
    }
    c = s->p[s->i];
    if (c == '{') {
        zb_json *v;
        ++s->depth;
        v = zb_jp_object(s);
        --s->depth;
        return v;
    }
    if (c == '[') {
        zb_json *v;
        ++s->depth;
        v = zb_jp_array(s);
        --s->depth;
        return v;
    }
    if (c == '"') {
        zb_buf tmp;
        zb_json *v;
        zb_buf_init(&tmp);
        if (!zb_jp_string(s, &tmp)) {
            zb_buf_free(&tmp);
            return NULL;
        }
        v = zb_json_new(s->arena);
        if (v == NULL) {
            zb_buf_free(&tmp);
            s->error = "out of memory";
            return NULL;
        }
        v->kind = ZB_JSON_STR;
        v->sval = zb_buf_detach(&tmp);
        if (v->sval == NULL) {
            s->error = "out of memory";
            return NULL;
        }
        return v;
    }
    if (c == 't' && s->i + 4 <= s->len && strncmp(s->p + s->i, "true", 4) == 0) {
        s->i += 4;
        n = zb_json_new(s->arena);
        if (n == NULL) {
            s->error = "out of memory";
            return NULL;
        }
        n->kind = ZB_JSON_BOOL;
        n->bval = 1;
        return n;
    }
    if (c == 'f' && s->i + 5 <= s->len && strncmp(s->p + s->i, "false", 5) == 0) {
        s->i += 5;
        n = zb_json_new(s->arena);
        if (n == NULL) {
            s->error = "out of memory";
            return NULL;
        }
        n->kind = ZB_JSON_BOOL;
        n->bval = 0;
        return n;
    }
    if (c == 'n' && s->i + 4 <= s->len && strncmp(s->p + s->i, "null", 4) == 0) {
        s->i += 4;
        n = zb_json_new(s->arena);
        if (n == NULL) {
            s->error = "out of memory";
            return NULL;
        }
        n->kind = ZB_JSON_NULL;
        return n;
    }
    if (c == '-' || c == '+' || (c >= '0' && c <= '9')) {
        return zb_jp_number(s);
    }
    s->error = "unexpected character";
    return NULL;
}

zb_json *zb_json_parse(const char *text, zb_json_arena *a, const char **error) {
    zb_jparse s;
    zb_json *root;
    if (error != NULL) *error = NULL;
    if (a == NULL) {
        if (error != NULL) *error = "no arena";
        return NULL;
    }
    if (text == NULL) {
        if (error != NULL) *error = "null input";
        return NULL;
    }
    s.p = text;
    s.len = strlen(text);
    s.i = 0;
    s.depth = 0;
    s.error = NULL;
    s.arena = a;
    zb_jp_ws(&s);
    root = zb_jp_value(&s);
    if (root == NULL) {
        if (error != NULL) *error = (s.error != NULL) ? s.error : "parse failed";
        return NULL;
    }
    return root;
}

/* ============================================================
 *  取值
 * ============================================================ */

zb_json *zb_json_obj_get(const zb_json *obj, const char *key) {
    const zb_json *c;
    if (obj == NULL || key == NULL) return NULL;
    if (obj->kind != ZB_JSON_OBJ) return NULL;
    for (c = obj->child; c != NULL; c = c->next) {
        if (c->key != NULL && strcmp(c->key, key) == 0) return (zb_json *)c;
    }
    return NULL;
}

zb_json *zb_json_arr_at(const zb_json *arr, size_t index) {
    const zb_json *c;
    size_t i = 0;
    if (arr == NULL || arr->kind != ZB_JSON_ARR) return NULL;
    for (c = arr->child; c != NULL; c = c->next) {
        if (i == index) return (zb_json *)c;
        ++i;
    }
    return NULL;
}

const char *zb_json_get_str(const zb_json *obj, const char *key) {
    zb_json *v = zb_json_obj_get(obj, key);
    if (v == NULL || v->kind != ZB_JSON_STR) return NULL;
    return v->sval != NULL ? v->sval : "";
}

int zb_json_get_int(const zb_json *obj, const char *key, int def) {
    zb_json *v = zb_json_obj_get(obj, key);
    if (v == NULL || v->kind != ZB_JSON_NUM) return def;
    if (v->nval > 2147483647.0) return 2147483647;
    if (v->nval < -2147483648.0) return -2147483648;
    return (int)v->nval;
}

double zb_json_get_num(const zb_json *obj, const char *key, double def) {
    zb_json *v = zb_json_obj_get(obj, key);
    if (v == NULL || v->kind != ZB_JSON_NUM) return def;
    return v->nval;
}

int zb_json_get_bool(const zb_json *obj, const char *key, int def) {
    zb_json *v = zb_json_obj_get(obj, key);
    if (v == NULL) return def;
    if (v->kind == ZB_JSON_BOOL) return v->bval;
    if (v->kind == ZB_JSON_NUM) return v->nval != 0.0;
    return def;
}
