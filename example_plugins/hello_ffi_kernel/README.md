# 示例插件：FFI 内核

演示如何用 zip 携带一个原生内核并替换浏览器内核。
内核为零依赖软件渲染（`zb_example_kernel.c`），画面为演示界面。

## 预编译产物（已包含）

- `kernels/windows/zb_example_kernel.dll`（x64，mingw/VS 可编译）
- `kernels/android/arm64-v8a/libzb_example_kernel.so`
- `kernels/android/armeabi-v7a/libzb_example_kernel.so`
- `kernels/android/x86_64/libzb_example_kernel.so`

宿主需先集成 native surface 插件（`tool/enable_native_surface.py`），
插件内核的帧才能通过 Flutter 纹理上屏。

## 使用

1. 浏览器中安装打包好的 zip
2. 菜单 → 设置 → 内核选择“示例软件渲染内核”
3. 新开标签页查看

## 从源码重新编译

源码为 `kernels/windows/zb_example_kernel.c`，ABI 头文件在
`native_plugins/zb_native_surface/include/zb_plugin_kernel_abi.h`。

- **Windows**：`tool\build_example_kernel.bat`（VS 开发者命令行，或安装了 LLVM 时用 clang）
- **Android**：用 NDK 的 clang 为各 ABI 分别编译，例如（`$TRIPLE` 取
  `aarch64-linux-android` / `armv7a-linux-androideabi` / `x86_64-linux-android`）：

  ```bash
  NDK=/path/to/android-ndk
  CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/${TRIPLE}24-clang"
  "$CC" -shared -fPIC -O2 -Wall -Wextra \
        -I native_plugins/zb_native_surface/include \
        kernels/windows/zb_example_kernel.c \
        -o kernels/android/<abi>/libzb_example_kernel.so
  ```
- **重新打包**：`python3 tool/pack_plugin.py example_plugins/hello_ffi_kernel`

以上三平台产物也可由 CI 工作流
[.github/workflows/build-kernel.yml](../../.github/workflows/build-kernel.yml)
一键构建（Windows 跑 MSVC，Android 跑 NDK），并自动打包出
`hello_ffi_kernel.zip`。

详见 [docs/PLUGIN_KERNEL_GUIDE.md](../../docs/PLUGIN_KERNEL_GUIDE.md)。
