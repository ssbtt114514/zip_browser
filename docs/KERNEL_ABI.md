# 原生内核 FFI ABI

自带渲染的内核以原生库（Windows `.dll` / Linux·Android `.so` /
macOS `.dylib`）形式发布，宿主通过 **dart:ffi** 加载。库必须实现
头文件 `native_plugins/zb_native_surface/include/zb_plugin_kernel_abi.h`
中声明的全部导出符号。当前 **ABI 版本 = 1**。

内核把像素绘制到 RGBA 帧缓冲，通过宿主提供的 `frame_submit` 回调提交，
由 native surface 插件注册为 Flutter 纹理上屏。

## 导出宏与句柄

```c
#ifdef _WIN32
#  define ZB_API __declspec(dllexport)
#else
#  define ZB_API __attribute__((visibility("default")))
#endif

typedef struct zb_kernel_s *zb_kernel_t;

/* 内核 -> 宿主：请求宿主能力；宿主随后用
 * zb_kernel_dispatch_from_host 发回 {request_id, result|error} */
typedef void (*zb_host_dispatch_fn)(int64_t request_id,
                                    const char *method,
                                    const char *params_json);

/* 帧提交回调：RGBA8888，stride 为每行字节数 */
typedef void (*zb_frame_submit_fn)(int64_t texture_id,
                                   const uint8_t *rgba,
                                   int32_t width,
                                   int32_t height,
                                   int32_t stride);
```

## 必须导出的 16 个符号

| 函数 | 签名 | 说明 |
|---|---|---|
| `zb_abi_version` | `int32_t (void)` | 返回 ABI 版本（当前 1） |
| `zb_kernel_create` | `zb_kernel_t (const char *config_json, zb_host_dispatch_fn)` | 创建内核实例 |
| `zb_kernel_destroy` | `void (zb_kernel_t)` | 销毁实例 |
| `zb_kernel_name` | `const char* (zb_kernel_t)` | 内核标识名 |
| `zb_kernel_version` | `const char* (zb_kernel_t)` | 内核版本 |
| `zb_kernel_load_url` | `int32_t (zb_kernel_t, const char *url)` | 加载 URL / data: HTML |
| `zb_kernel_go_back` | `int32_t (zb_kernel_t)` | 后退 |
| `zb_kernel_go_forward` | `int32_t (zb_kernel_t)` | 前进 |
| `zb_kernel_reload` | `int32_t (zb_kernel_t)` | 重载 |
| `zb_kernel_eval_js` | `const char* (zb_kernel_t, const char *script)` | 执行脚本，返回 JSON 字符串 |
| `zb_kernel_current_url` | `const char* (zb_kernel_t)` | 当前 URL |
| `zb_kernel_title` | `const char* (zb_kernel_t)` | 页面标题 |
| `zb_kernel_attach_surface` | `int32_t (zb_kernel_t, int64_t texture_id, zb_frame_submit_fn, int32_t w, int32_t h)` | 绑定输出表面 |
| `zb_kernel_tick` | `int32_t (zb_kernel_t)` | 推进一帧 |
| `zb_kernel_dispatch_from_host` | `int32_t (zb_kernel_t, const char *message_json)` | 宿主回传结果 |
| `zb_free_ptr` | `void (void*)` | 释放库内分配、返回给宿主的字符串 |

约定：

- 返回 `const char*` 的函数，其内存由库内分配，宿主使用后必须调用
  **`zb_free_ptr`** 释放。
- `attach_surface` 返回 `0` 成功；负值为错误（如尺寸非法、帧缓冲分配失败）。
- 尺寸变化时宿主会再次调用 `attach_surface`。
- 内核通过 `host_dispatch` 发起能力请求（如网络、下载），结果经
  `dispatch_from_host` 异步回传。

## 编译命令

**Android**（NDK，三 ABI）：

```bash
$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang \
  --target=aarch64-linux-android24 -shared -fPIC -O2 \
  -I native_plugins/zb_native_surface/include \
  -o libzb_example_kernel.so zb_example_kernel.c
# --target 分别取：
#   aarch64-linux-android24    -> arm64-v8a
#   armv7a-linux-androideabi24 -> armeabi-v7a
#   x86_64-linux-android24     -> x86_64
```

**Linux**：

```bash
gcc -shared -fPIC -O2 -I native_plugins/zb_native_surface/include \
  -o libzb_example_kernel.so zb_example_kernel.c
```

**Windows**：在 VS 开发者命令行（或 LLVM）下，见
`example_plugins/hello_ffi_kernel` 内的构建脚本，导出上述符号为 dll。

## 打包

- 作为独立内核分发：`.zbk`，见 [KERNEL_PACK.md](KERNEL_PACK.md)；
- 随功能插件分发：放入插件并在 `plugin.json` 的 `kernel` 字段声明，
  见 [PLUGIN_KERNEL_GUIDE.md](PLUGIN_KERNEL_GUIDE.md)。

## 参考实现

`example_plugins/hello_ffi_kernel/kernels/*/zb_example_kernel.c` 是零依赖
参考实现：接收 URL / data:HTML → 提取可见文本 → 内置 5×7 点阵字库绘制到
RGBA 帧缓冲 → 经 `frame_submit` 上屏。它不做真实 HTML 排版，仅用于验证
完整的内核加载与上屏链路。
