/*
 * Zip Browser —— zb_lite_kernel：通用工具
 *
 * 动态缓冲、字符串、UTF-8 编解码。只用 C99 标准库，且所有分配失败都有
 * 降级路径（缓冲变成"只读空缓冲"，put 返回 -1，不崩溃）。
 */
#include <stdlib.h>
#include <string.h>

#include "zb_lite_internal.h"

/* ============================================================
 *  动态缓冲
 * ============================================================ */

void zb_buf_init(zb_buf *b) {
    if (b == NULL) return;
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
}

void zb_buf_free(zb_buf *b) {
    if (b == NULL) return;
    free(b->data);
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
}

void zb_buf_clear(zb_buf *b) {
    if (b == NULL) return;
    b->len = 0;
    if (b->data != NULL && b->cap > 0) b->data[0] = '\0';
}

int zb_buf_reserve(zb_buf *b, size_t extra) {
    size_t need;
    size_t cap;
    char *p;
    if (b == NULL) return -1;
    if (extra > (size_t)-1 - b->len - 1) return -1; /* 溢出保护 */
    need = b->len + extra + 1;
    if (b->data != NULL && need <= b->cap) return 0;
    cap = (b->cap == 0) ? 64 : b->cap;
    while (cap < need) {
        if (cap > ((size_t)-1) / 2) {
            cap = need;
            break;
        }
        cap *= 2;
    }
    p = (char *)realloc(b->data, cap);
    if (p == NULL) return -1;
    b->data = p;
    b->cap = cap;
    if (b->len == 0) b->data[0] = '\0';
    return 0;
}

int zb_buf_putc(zb_buf *b, char c) {
    if (zb_buf_reserve(b, 1) != 0) return -1;
    b->data[b->len++] = c;
    b->data[b->len] = '\0';
    return 0;
}

int zb_buf_put(zb_buf *b, const char *s, size_t n) {
    if (b == NULL) return -1;
    if (s == NULL || n == 0) return 0;
    if (zb_buf_reserve(b, n) != 0) return -1;
    memcpy(b->data + b->len, s, n);
    b->len += n;
    b->data[b->len] = '\0';
    return 0;
}

int zb_buf_puts(zb_buf *b, const char *s) {
    if (s == NULL) return 0;
    return zb_buf_put(b, s, strlen(s));
}

int zb_buf_put_int(zb_buf *b, long long v) {
    char tmp[32];
    int n = 0;
    int i;
    unsigned long long uv;
    if (v < 0) {
        if (zb_buf_putc(b, '-') != 0) return -1;
        uv = (unsigned long long)(-(v + 1)) + 1ULL;
    } else {
        uv = (unsigned long long)v;
    }
    if (uv == 0) return zb_buf_putc(b, '0');
    while (uv > 0 && n < (int)sizeof(tmp)) {
        tmp[n++] = (char)('0' + (int)(uv % 10ULL));
        uv /= 10ULL;
    }
    for (i = n - 1; i >= 0; --i) {
        if (zb_buf_putc(b, tmp[i]) != 0) return -1;
    }
    return 0;
}

static const char ZB_HEX[] = "0123456789abcdef";

int zb_buf_put_json_string(zb_buf *b, const char *s) {
    const unsigned char *p = (const unsigned char *)(s != NULL ? s : "");
    if (zb_buf_putc(b, '"') != 0) return -1;
    for (; *p != 0; ++p) {
        unsigned char c = *p;
        switch (c) {
            case '"':
                if (zb_buf_put(b, "\\\"", 2) != 0) return -1;
                break;
            case '\\':
                if (zb_buf_put(b, "\\\\", 2) != 0) return -1;
                break;
            case '\n':
                if (zb_buf_put(b, "\\n", 2) != 0) return -1;
                break;
            case '\r':
                if (zb_buf_put(b, "\\r", 2) != 0) return -1;
                break;
            case '\t':
                if (zb_buf_put(b, "\\t", 2) != 0) return -1;
                break;
            case '\b':
                if (zb_buf_put(b, "\\b", 2) != 0) return -1;
                break;
            case '\f':
                if (zb_buf_put(b, "\\f", 2) != 0) return -1;
                break;
            default:
                if (c < 0x20) {
                    char esc[6];
                    esc[0] = '\\';
                    esc[1] = 'u';
                    esc[2] = '0';
                    esc[3] = '0';
                    esc[4] = ZB_HEX[(c >> 4) & 0x0F];
                    esc[5] = ZB_HEX[c & 0x0F];
                    if (zb_buf_put(b, esc, 6) != 0) return -1;
                } else {
                    if (zb_buf_putc(b, (char)c) != 0) return -1;
                }
                break;
        }
    }
    return zb_buf_putc(b, '"');
}

const char *zb_buf_cstr(const zb_buf *b) {
    if (b == NULL || b->data == NULL) return "";
    return b->data;
}

char *zb_buf_detach(zb_buf *b) {
    char *out;
    if (b == NULL) return NULL;
    if (b->data == NULL) {
        out = (char *)malloc(1);
        if (out != NULL) out[0] = '\0';
        return out;
    }
    out = b->data;
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
    return out;
}

/* ============================================================
 *  字符串
 * ============================================================ */

char *zb_strndup(const char *s, size_t n) {
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

char *zb_strdup(const char *s) {
    if (s == NULL) return NULL;
    return zb_strndup(s, strlen(s));
}

char zb_ascii_lower(char c) {
    if (c >= 'A' && c <= 'Z') return (char)(c - 'A' + 'a');
    return c;
}

int zb_has_prefix(const char *s, const char *prefix) {
    size_t n;
    if (s == NULL || prefix == NULL) return 0;
    n = strlen(prefix);
    if (n == 0) return 1;
    return strncmp(s, prefix, n) == 0;
}

int zb_has_prefix_ci(const char *s, const char *prefix) {
    size_t i;
    if (s == NULL || prefix == NULL) return 0;
    for (i = 0; prefix[i] != '\0'; ++i) {
        if (s[i] == '\0') return 0;
        if (zb_ascii_lower(s[i]) != zb_ascii_lower(prefix[i])) return 0;
    }
    return 1;
}

int zb_ascii_ieq(const char *a, const char *b) {
    size_t i = 0;
    if (a == NULL || b == NULL) return 0;
    for (;;) {
        char ca = zb_ascii_lower(a[i]);
        char cb = zb_ascii_lower(b[i]);
        if (ca != cb) return 0;
        if (ca == '\0') return 1;
        ++i;
    }
}

int zb_find_ci(const char *hay, const char *needle) {
    size_t hl;
    size_t nl;
    size_t i;
    if (hay == NULL || needle == NULL) return -1;
    nl = strlen(needle);
    if (nl == 0) return 0;
    hl = strlen(hay);
    if (hl < nl) return -1;
    for (i = 0; i + nl <= hl; ++i) {
        size_t j;
        for (j = 0; j < nl; ++j) {
            if (zb_ascii_lower(hay[i + j]) != zb_ascii_lower(needle[j])) break;
        }
        if (j == nl) return (int)i;
    }
    return -1;
}

static int zb_is_space_ch(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

size_t zb_trim_len(const char *s, size_t n, size_t *start) {
    size_t b = 0;
    size_t e = n;
    if (s == NULL) {
        if (start != NULL) *start = 0;
        return 0;
    }
    while (b < e && zb_is_space_ch(s[b])) ++b;
    while (e > b && zb_is_space_ch(s[e - 1])) --e;
    if (start != NULL) *start = b;
    return e - b;
}

char *zb_trim_dup(const char *s) {
    size_t start = 0;
    size_t n;
    if (s == NULL) return NULL;
    n = zb_trim_len(s, strlen(s), &start);
    return zb_strndup(s + start, n);
}

/* ============================================================
 *  UTF-8
 * ============================================================ */

size_t zb_utf8_encode(uint32_t cp, char out[4]) {
    if (cp < 0x80u) {
        out[0] = (char)cp;
        return 1;
    }
    if (cp < 0x800u) {
        out[0] = (char)(0xC0u | (cp >> 6));
        out[1] = (char)(0x80u | (cp & 0x3Fu));
        return 2;
    }
    if (cp < 0x10000u) {
        out[0] = (char)(0xE0u | (cp >> 12));
        out[1] = (char)(0x80u | ((cp >> 6) & 0x3Fu));
        out[2] = (char)(0x80u | (cp & 0x3Fu));
        return 3;
    }
    if (cp <= 0x10FFFFu) {
        out[0] = (char)(0xF0u | (cp >> 18));
        out[1] = (char)(0x80u | ((cp >> 12) & 0x3Fu));
        out[2] = (char)(0x80u | ((cp >> 6) & 0x3Fu));
        out[3] = (char)(0x80u | (cp & 0x3Fu));
        return 4;
    }
    out[0] = '?';
    return 1;
}

uint32_t zb_utf8_next(const char *s, size_t len, size_t *i) {
    unsigned char c;
    size_t p;
    uint32_t cp;
    int need;
    int k;
    if (s == NULL || i == NULL || *i >= len) return 0;
    p = *i;
    c = (unsigned char)s[p];
    if (c < 0x80u) {
        *i = p + 1;
        return (uint32_t)c;
    }
    if ((c & 0xE0u) == 0xC0u) {
        cp = (uint32_t)(c & 0x1Fu);
        need = 1;
    } else if ((c & 0xF0u) == 0xE0u) {
        cp = (uint32_t)(c & 0x0Fu);
        need = 2;
    } else if ((c & 0xF8u) == 0xF0u) {
        cp = (uint32_t)(c & 0x07u);
        need = 3;
    } else {
        *i = p + 1; /* 非法起始字节：按单字节处理 */
        return 0xFFFDu;
    }
    for (k = 0; k < need; ++k) {
        unsigned char cc;
        if (p + 1 + (size_t)k >= len) {
            *i = p + 1;
            return 0xFFFDu;
        }
        cc = (unsigned char)s[p + 1 + (size_t)k];
        if ((cc & 0xC0u) != 0x80u) {
            *i = p + 1;
            return 0xFFFDu;
        }
        cp = (cp << 6) | (uint32_t)(cc & 0x3Fu);
    }
    *i = p + 1 + (size_t)need;
    if (cp > 0x10FFFFu) return 0xFFFDu;
    return cp;
}

int zb_cp_is_wide(uint32_t cp) {
    /* 简化的东亚宽度判定：CJK / 假名 / 韩文 / 全角标点等占 2 个字符格 */
    if (cp < 0x1100u) return 0;
    if (cp <= 0x115Fu) return 1;              /* 谚文字母 */
    if (cp >= 0x2E80u && cp <= 0x303Eu) return 1; /* CJK 部首、标点 */
    if (cp >= 0x3041u && cp <= 0x33FFu) return 1; /* 假名、注音、CJK 兼容 */
    if (cp >= 0x3400u && cp <= 0x4DBFu) return 1; /* CJK 扩展 A */
    if (cp >= 0x4E00u && cp <= 0x9FFFu) return 1; /* CJK 基本区 */
    if (cp >= 0xA000u && cp <= 0xA4CFu) return 1; /* 彝文 */
    if (cp >= 0xAC00u && cp <= 0xD7A3u) return 1; /* 谚文音节 */
    if (cp >= 0xF900u && cp <= 0xFAFFu) return 1; /* CJK 兼容表意 */
    if (cp >= 0xFE30u && cp <= 0xFE6Fu) return 1; /* CJK 兼容形式 */
    if (cp >= 0xFF00u && cp <= 0xFF60u) return 1; /* 全角形式 */
    if (cp >= 0xFFE0u && cp <= 0xFFE6u) return 1;
    if (cp >= 0x20000u && cp <= 0x3FFFDu) return 1;
    return 0;
}
