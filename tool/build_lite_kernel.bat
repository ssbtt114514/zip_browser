@echo off
REM ============================================================
REM  Build zb_lite_kernel (Windows x64) -> zb_lite_kernel.dll
REM
REM  Option 1: run in "x64 Native Tools Command Prompt for VS"
REM  Option 2: with LLVM installed, the script falls back to clang
REM
REM  Output: example_plugins\lite_kernel\kernels\windows\zb_lite_kernel.dll
REM
REM  NOTE: this file is intentionally ASCII-only. cmd.exe reads .bat files
REM  in the console code page, and UTF-8 Chinese text can break parsing
REM  (a trailing byte may be read as '|' or '&'). Chinese docs live in
REM  docs/KERNEL_LITE.md.
REM ============================================================
setlocal enabledelayedexpansion
set SRC=native_kernels\zb_lite_kernel\src
set INC1=native_kernels\zb_lite_kernel\include
set INC2=native_plugins\zb_native_surface\include
set OUT=example_plugins\lite_kernel\kernels\windows
set OBJ=build\lite-kernel-obj

if not exist "%OUT%" mkdir "%OUT%"
if not exist "%OBJ%" mkdir "%OBJ%"

set SRCONLY=
for %%f in ("%SRC%\zb_lite_util.c" "%SRC%\zb_lite_json.c" "%SRC%\zb_lite_doc.c" "%SRC%\zb_lite_layout.c" "%SRC%\zb_lite_render.c" "%SRC%\zb_lite_kernel.c") do set SRCONLY=!SRCONLY! %%f

where cl >nul 2>nul
if %errorlevel%==0 goto :msvc

where clang >nul 2>nul
if %errorlevel%==0 goto :clang

echo [ERROR] Neither cl nor clang found. Use a VS developer prompt or install LLVM.
exit /b 1

:msvc
cl /nologo /LD /O2 /W3 /utf-8 /I "%INC1%" /I "%INC2%" !SRCONLY! /Fo:"%OBJ%\\" /Fe:"%OUT%\zb_lite_kernel.dll"
if errorlevel 1 goto :failed
del /q "%OBJ%\*.obj" 2>nul
goto :ok

:clang
clang -shared -std=c99 -O2 -Wall -Wextra -fvisibility=hidden -I "%INC1%" -I "%INC2%" !SRCONLY! -o "%OUT%\zb_lite_kernel.dll"
if errorlevel 1 goto :failed
goto :ok

:ok
echo.
echo Built: %OUT%\zb_lite_kernel.dll
echo Self-test: gcc -std=c99 -Wall -Wextra -I %INC2% -I %INC1% %SRC%\*.c native_kernels\zb_lite_kernel\tests\zb_lite_kernel_selftest.c -o build\selftest.exe
echo Package:   python tool/pack_plugin.py example_plugins/lite_kernel
echo Note:      manifest declares 5 platforms; linux/android libs must be built on
echo            Linux/macOS (sh tool/build_lite_kernel.sh all) or taken from CI,
echo            otherwise pack_plugin.py refuses to pack an incomplete zip.
exit /b 0

:failed
echo [ERROR] Build failed.
exit /b 1
