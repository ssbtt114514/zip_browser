# zb_lite_kernel（轻量文本内核）源码

零外部依赖、C99、`-Wall -Wextra` 无警告的软件渲染浏览器内核。
内核标识名 `zb_lite_kernel`，显示名「轻量文本内核」。

设计与协议（`net.fetch` / 输入事件 / `kernel.state` / `eval_js` 命令清单 /
能力边界）：**[docs/KERNEL_LITE.md](../../docs/KERNEL_LITE.md)**。

```text
native_kernels/zb_lite_kernel/
├── CMakeLists.txt            库目标 zb_lite_kernel（Windows dll / 其它 so）
├── include/zb_lite_internal.h  内部分层声明（util / json / doc / layout / render）
├── src/
│   ├── zb_lite_util.c        动态缓冲 / 字符串 / UTF-8
│   ├── zb_lite_json.c        最小 JSON 解析与转义
│   ├── zb_lite_doc.c         HTML → 文档模型（块 / 行内 run / 锚点）
│   ├── zb_lite_layout.c      自动换行排版 → 绘制指令
│   ├── zb_lite_render.c      主题 + 8x16 点阵字库光栅化
│   ├── zb_lite_kernel.c      16 个 ABI 符号 / 历史 / 网络 / 事件 / eval_js
│   └── zb_lite_font.h        自动生成的 8x16 ASCII 字库
├── tests/zb_lite_kernel_selftest.c  端到端自检（不参与动态库构建）
└── tools/gen_font.py         从 5x7 源点阵生成 8x16 字库
```

## 构建

```bat
tool\build_lite_kernel.bat                  :: Windows -> 插件目录内的 dll
```

```bash
sh tool/build_lite_kernel.sh linux
sh tool/build_lite_kernel.sh android-arm64-v8a   # 另有 armeabi-v7a / x86_64
sh tool/build_lite_kernel.sh selftest            # 编译并运行自检
```

CMake：

```bash
cmake -S native_kernels/zb_lite_kernel -B build/lite-kernel -DZB_LITE_BUILD_SELFTEST=ON
cmake --build build/lite-kernel
```

## 自检

`tests/zb_lite_kernel_selftest.c` 用纯标准 C 调用内核 API，覆盖
`create → load HTML → attach 假 surface → tick → 校验帧缓冲确有非背景像素`
以及 `net.fetch` 请求/回包、点击链接、相对地址与锚点、历史前进后退、滚动钳制、
暗色主题、畸形与超大输入等 106 项断言。退出码 `0` 表示全部通过。
