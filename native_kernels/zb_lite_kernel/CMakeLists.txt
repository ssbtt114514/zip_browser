# ============================================================
#  zb_lite_kernel —— "轻量文本内核"（零依赖软件渲染内核）
#
#  产物：
#    Windows -> zb_lite_kernel.dll
#    其它    -> libzb_lite_kernel.so
#
#  用法（在仓库根目录或本目录均可）：
#    cmake -S native_kernels/zb_lite_kernel -B build/lite-kernel
#    cmake --build build/lite-kernel --config Release
#
#  编译条件与 docs/KERNEL_ABI.md 一致：C99、位置无关代码、-Wall -Wextra。
# ============================================================
cmake_minimum_required(VERSION 3.15)
project(zb_lite_kernel C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# 内核源码（按分层组织：util / json / doc / layout / render / kernel）
set(ZB_LITE_SOURCES
    src/zb_lite_util.c
    src/zb_lite_json.c
    src/zb_lite_doc.c
    src/zb_lite_layout.c
    src/zb_lite_render.c
    src/zb_lite_kernel.c
)

add_library(zb_lite_kernel SHARED ${ZB_LITE_SOURCES})

target_include_directories(zb_lite_kernel
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../native_plugins/zb_native_surface/include
)

# 只导出 ZB_API 标注的 16 个符号
set_target_properties(zb_lite_kernel PROPERTIES
    C_VISIBILITY_PRESET hidden
    POSITION_INDEPENDENT_CODE ON
)

if(MSVC)
    target_compile_options(zb_lite_kernel PRIVATE /W3 /utf-8)
else()
    target_compile_options(zb_lite_kernel PRIVATE -Wall -Wextra)
endif()

# 自检程序（可选：-DZB_LITE_BUILD_SELFTEST=ON）
option(ZB_LITE_BUILD_SELFTEST "构建 zb_lite_kernel 自检程序" OFF)
if(ZB_LITE_BUILD_SELFTEST)
    add_executable(zb_lite_kernel_selftest
        ${ZB_LITE_SOURCES}
        tests/zb_lite_kernel_selftest.c
    )
    target_include_directories(zb_lite_kernel_selftest
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/include
            ${CMAKE_CURRENT_SOURCE_DIR}/../../native_plugins/zb_native_surface/include
    )
    if(MSVC)
        target_compile_options(zb_lite_kernel_selftest PRIVATE /W3 /utf-8)
    else()
        target_compile_options(zb_lite_kernel_selftest PRIVATE -Wall -Wextra)
    endif()
endif()
