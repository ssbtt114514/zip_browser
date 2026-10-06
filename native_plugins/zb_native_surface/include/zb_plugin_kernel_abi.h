/*
 * Zip Browser —— 插件内核 C ABI
 *
 * 与 lib/core/plugin/ffi_kernel_loader.dart 严格对应。
 * 插件内核必须编译为动态库（Windows .dll / Android .so / Linux .so / macOS .dylib），
 * 并导出下列全部符号。返回 const char* 的函数，内存由库内分配，
 * 宿主读取后通过 zb_free_ptr 释放。
 */
#ifndef ZIPBROWSER_PLUGIN_KERNEL_ABI_H
#define ZIPBROWSER_PLUGIN_KERNEL_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ZB_ABI_VERSION 1

#if defined(_WIN32)
#  define ZB_API __declspec(dllexport)
#else
#  define ZB_API __attribute__((visibility("default")))
#endif

typedef struct zb_kernel_s *zb_kernel_t;

/* 内核 -> 宿主：请求宿主能力。宿主随后调用
 * zb_kernel_dispatch_from_host 发回 {request_id, result|error} */
typedef void (*zb_host_dispatch_fn)(int64_t request_id,
                                    const char *method,
                                    const char *params_json);

/* 帧提交回调：RGBA8888（小端内存为 B,G,R,A 顺序写入时注意），
 * stride 为每行字节数。通常指向宿主 surface 插件的提交入口。 */
typedef void (*zb_frame_submit_fn)(int64_t texture_id,
                                   const uint8_t *rgba,
                                   int32_t width,
                                   int32_t height,
                                   int32_t stride);

ZB_API int32_t zb_abi_version(void);

ZB_API zb_kernel_t zb_kernel_create(const char *config_json,
                                    zb_host_dispatch_fn host_dispatch);
ZB_API void zb_kernel_destroy(zb_kernel_t k);

ZB_API const char *zb_kernel_name(zb_kernel_t k);
ZB_API const char *zb_kernel_version(zb_kernel_t k);

ZB_API int32_t zb_kernel_load_url(zb_kernel_t k, const char *url);
ZB_API int32_t zb_kernel_go_back(zb_kernel_t k);
ZB_API int32_t zb_kernel_go_forward(zb_kernel_t k);
ZB_API int32_t zb_kernel_reload(zb_kernel_t k);

ZB_API const char *zb_kernel_eval_js(zb_kernel_t k, const char *script);
ZB_API const char *zb_kernel_current_url(zb_kernel_t k);
ZB_API const char *zb_kernel_title(zb_kernel_t k);

ZB_API int32_t zb_kernel_attach_surface(zb_kernel_t k,
                                        int64_t texture_id,
                                        zb_frame_submit_fn frame_cb,
                                        int32_t width,
                                        int32_t height);
ZB_API int32_t zb_kernel_tick(zb_kernel_t k);
ZB_API int32_t zb_kernel_dispatch_from_host(zb_kernel_t k,
                                            const char *message_json);

ZB_API void zb_free_ptr(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* ZIPBROWSER_PLUGIN_KERNEL_ABI_H */
