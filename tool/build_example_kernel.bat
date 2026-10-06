@echo off
REM ============================================================
REM  编译示例 FFI 内核 zb_example_kernel.dll（Windows）
REM  方式一：在 “x64 Native Tools Command Prompt for VS” 中运行
REM  方式二：安装 LLVM 后把 cl 换成 clang
REM ============================================================
setlocal
set SRC=example_plugins\hello_ffi_kernel\kernels\windows\zb_example_kernel.c
set INC=native_plugins\zb_native_surface\include
set OUT=example_plugins\hello_ffi_kernel\kernels\windows\

where cl >nul 2>nul
if %errorlevel%==0 (
  cl /nologo /LD /O2 /I %INC% %SRC% /Fe:%OUT%zb_example_kernel.dll
  del /q zb_example_kernel.obj 2>nul
) else (
  where clang >nul 2>nul
  if %errorlevel%==0 (
    clang -shared -O2 -I %INC% %SRC% -o %OUT%zb_example_kernel.dll
  ) else (
    echo 未找到 cl 或 clang，请使用 VS 开发者命令行或安装 LLVM。
    exit /b 1
  )
)
echo 编译完成：%OUT%zb_example_kernel.dll
echo 随后可打包：tool\pack_plugin.bat example_plugins\hello_ffi_kernel
