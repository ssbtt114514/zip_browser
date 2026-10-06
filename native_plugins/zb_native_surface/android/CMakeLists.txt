cmake_minimum_required(VERSION 3.22.1)

# Zip Browser 原生表面插件（Android）
add_library(zb_native_surface SHARED
    zb_native_surface_jni.cpp)

find_library(log-lib log)

target_link_libraries(zb_native_surface
    android      # ANativeWindow
    EGL
    GLESv2
    ${log-lib})
