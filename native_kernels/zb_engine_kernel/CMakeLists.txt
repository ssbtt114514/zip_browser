# ============================================================
#  zb_engine_kernel —— 同源多引擎内核（Chromium / Gecko 标识）
#
#  复用 zb_lite_kernel 的完整软件渲染实现，仅通过编译宏覆盖
#  引擎标识（内核 id / 显示名 / 底部提示），产出两个独立库：
#    Windows -> zb_chromium_kernel.dll / zb_gecko_kernel.dll
#    其它    -> libzb_chromium_kernel.so / libzb_gecko_kernel.so
#
#  为什么复用：lite 内核严格实现 zb_plugin_kernel_abi.h 的 16 个
#  导出符号（网络抓取 / 排版 / 点阵字库光栅化 / 帧提交），是
#  现成可用的三平台软件渲染内核；chromium / gecko 变体用于演示
#  "引擎标识化"内核包链路——同一套 C ABI，不同引擎声明。
#
#  用法（在仓库根目录）：
#    cmake -S native_kernels/zb_engine_kernel -B build/engine-kernel
#    cmake --build build/engine-kernel --config Release
#
#  Android .so 用 tool/build_engine_kernels.py 调 NDK 直接编译
#  （本工程 CMake 面向桌面工具链，交叉编译走脚本更可控）。
# ============================================================
cmake_minimum_required(VERSION 3.15)
project(zb_engine_kernel C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# 复用 zb_lite_kernel 的源码与头文件（跨目录引用，CMake 原生支持）
set(ZB_ENGINE_LITE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../zb_lite_kernel)
set(ZB_ENGINE_SOURCES
    ${ZB_ENGINE_LITE_DIR}/src/zb_lite_util.c
    ${ZB_ENGINE_LITE_DIR}/src/zb_lite_json.c
    ${ZB_ENGINE_LITE_DIR}/src/zb_lite_doc.c
    ${ZB_ENGINE_LITE_DIR}/src/zb_lite_layout.c
    ${ZB_ENGINE_LITE_DIR}/src/zb_lite_render.c
    ${ZB_ENGINE_LITE_DIR}/src/zb_lite_kernel.c
)
set(ZB_ENGINE_INCLUDES
    ${ZB_ENGINE_LITE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../native_plugins/zb_native_surface/include
)

# 生成一个引擎变体库：覆盖引擎标识宏，仅导出 ZB_API 符号
function(zb_engine_add name engine_id display_name hint)
    add_library(${name} SHARED ${ZB_ENGINE_SOURCES})
    target_include_directories(${name} PRIVATE ${ZB_ENGINE_INCLUDES})
    target_compile_definitions(${name} PRIVATE
        ZB_ENGINE_NAME="${engine_id}"
        ZB_ENGINE_DISPLAY_NAME="${display_name}"
        ZB_ENGINE_HINT="${hint}")
    set_target_properties(${name} PROPERTIES
        C_VISIBILITY_PRESET hidden
        POSITION_INDEPENDENT_CODE ON)
    if(MSVC)
        target_compile_options(${name} PRIVATE /W3 /utf-8)
    else()
        target_compile_options(${name} PRIVATE -Wall -Wextra)
    endif()
endfunction()

zb_engine_add(zb_chromium_kernel
    "zb_chromium_kernel"
    "Chromium 渲染内核"
    "zb_chromium_kernel - chromium engine (software raster, same ABI)")

zb_engine_add(zb_gecko_kernel
    "zb_gecko_kernel"
    "Gecko 渲染内核"
    "zb_gecko_kernel - gecko engine (software raster, same ABI)")
