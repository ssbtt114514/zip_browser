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

## ABI v1 的输入与网络扩展约定

**ABI 版本保持 1 不变。** 内核需要网络、需要接收输入时，不需要新增导出符号——
全部复用既有的 `host_dispatch`（内核 → 宿主）与 `zb_kernel_dispatch_from_host`
（宿主 → 内核）这一对通道。这样老宿主可以安全加载新内核（缺少的桥接方法会
返回 `error`，内核必须容错），新宿主也可以继续加载只实现 16 个符号的简单内核。

### 1. 网络抓取：`net.fetch`

内核 → 宿主：

```c
host_dispatch(request_id, "net.fetch", "{\"url\":\"https://…\",\"method\":\"GET\",\"max_bytes\":2097152}");
```

宿主 → 内核（异步回传，`dispatch_from_host`）：

```json
{"request_id":7,"result":{"status":200,"final_url":"https://…","content_type":"text/html","body":"<html>…</html>"}}
{"request_id":7,"error":"network unreachable"}
```

- `body` 必须是完整响应体的 **UTF-8 文本**（gzip / 分块 / 字符集转换由宿主负责）；
- `final_url` 用于更新地址栏与相对链接解析基准；
- 宿主未注册 `net.fetch` 时会回 `{"request_id":N,"error":"no handler: net.fetch"}`，
  内核应把它当作一次加载失败处理（渲染错误页），而不是崩溃或死等。

### 2. 输入事件

宿主把用户输入编码成 JSON 交给 `zb_kernel_dispatch_from_host`：

```json
{"event":"pointer","type":"down|up|move","x":120,"y":240}
{"event":"scroll","dx":0,"dy":120}
{"event":"key","key":"Home|End|PageUp|PageDown|Up|Down"}
{"event":"resize"}
```

- 坐标是**表面像素坐标、相对可见区域左上角**，内核自己加滚动量换算文档坐标；
- `dy` 正数表示向下滚动；
- 内核必须把滚动量钳制在 `[0, doc_height - view_height]`。

### 3. 状态上报：`kernel.state`

内核 → 宿主（单向，宿主可不实现）：

```c
host_dispatch(request_id, "kernel.state", "{\"url\":…,\"title\":…,\"can_back\":true,\"can_forward\":false,\"loading\":false,\"scroll_y\":0,\"doc_height\":1234}");
```

宿主未注册该方法时回 `{"request_id":N,"error":"no handler: kernel.state"}`，
**内核必须忽略**（这条错误回执不能影响正在进行的导航）。

### 4. 约定小结

| 约定 | 说明 |
|---|---|
| ABI 版本 | 仍为 `1`，16 个导出符号不变 |
| 请求 id | 内核自增分配；只认领与自己等待中的请求匹配的回包 |
| 未知 method | 宿主回 `error`，内核容错 |
| 未知 event | 内核返回 `0`（已处理/忽略），不报错 |
| 字符编码 | 一律 UTF-8 文本，不做字节级解码 |

以上三组协议的完整字段表见 [KERNEL_LITE.md](KERNEL_LITE.md)。

## 打包

- 作为独立内核分发：`.zbk`，见 [KERNEL_PACK.md](KERNEL_PACK.md)；
- 随功能插件分发：放入插件并在 `plugin.json` 的 `kernel` 字段声明，
  见 [PLUGIN_KERNEL_GUIDE.md](PLUGIN_KERNEL_GUIDE.md)。

## 参考实现

仓库内有两个参考实现：

1. **`example_plugins/hello_ffi_kernel/kernels/*/zb_example_kernel.c`** ——
   最小演示内核：接收 URL / data:HTML → 提取可见文本 → 内置 5×7 点阵字库绘制到
   RGBA 帧缓冲 → 经 `frame_submit` 上屏。不做真实 HTML 排版，用于验证完整的内核
   加载与上屏链路。

2. **`native_kernels/zb_lite_kernel/`（「轻量文本内核」）** ——
   可用的软件渲染内核：经 `net.fetch` 真实抓取网页、解析 HTML（块级/行内标签、
   实体、链接区间、锚点）、按表面宽度自动换行排版（英文按单词、CJK 按字符 2 格宽）、
   用内置 8×16 点阵字库渲染 RGBA 帧，并支持滚动、点击链接、`#fragment` 页内跳转、
   前进/后退/刷新与一组命令式 `eval_js`。构建产物对应
   `example_plugins/lite_kernel/`（插件）与 `build_kernel_pkg/zb_lite_kernel/`（.zbk）。
   设计与协议详见 **[KERNEL_LITE.md](KERNEL_LITE.md)**，
   自检程序 `native_kernels/zb_lite_kernel/tests/zb_lite_kernel_selftest.c`
   可在 CI 里直接编译运行。
