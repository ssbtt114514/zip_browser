#!/usr/bin/env python3
"""
将 native_plugins/zb_native_surface 集成进 Flutter 构建（Windows + Android）。

前置：已执行 `flutter create --platforms=windows,android .` 生成平台目录。
用法：python tool/enable_native_surface.py
幂等：重复执行不会重复追加。
"""
import os
import shutil
import sys

# Windows 控制台默认编码可能不是 UTF-8，显式切换以避免中文输出报 UnicodeEncodeError
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIN_DIR = os.path.join(ROOT, "windows")
AND_DIR = os.path.join(ROOT, "android")

SURFACE = os.path.join(ROOT, "native_plugins", "zb_native_surface")

# ============================ Windows ============================
MARK_CMAKE = "# >>> zip_browser native surface >>>"
MARK_RUNNER = "// >>> zip_browser native surface >>>"

CMAKE_SNIPPET = """# >>> zip_browser native surface >>>
# CMAKE_SOURCE_DIR 指向 windows/；native_plugins 与 windows/ 同级
set(ZB_SURFACE_DIR ${CMAKE_SOURCE_DIR}/../native_plugins/zb_native_surface)
target_include_directories(${BINARY_NAME} PRIVATE
  "${ZB_SURFACE_DIR}/include"
  "${ZB_SURFACE_DIR}/windows")
target_sources(${BINARY_NAME} PRIVATE
  "${ZB_SURFACE_DIR}/windows/zb_native_surface_plugin.cpp")
# flutter_wrapper_plugin 提供 PluginRegistrar / PluginRegistrarManager 的实现
# （runner 默认只链接了 flutter_wrapper_app，不含 plugin_registrar.cc）。
target_link_libraries(${BINARY_NAME} PRIVATE flutter_wrapper_plugin)
# <<< zip_browser native surface <<<
"""

RUNNER_SNIPPET = """  // >>> zip_browser native surface >>>
  ZipBrowserNativeSurfacePluginRegisterWithRegistrar(
      flutter_controller_->engine()->GetRegistrarForPlugin(
          "ZipBrowserNativeSurface"));
  // <<< zip_browser native surface >>>
"""

RUNNER_INCLUDE = '#include "zb_native_surface_plugin.h"'


def patch_cmake():
    path = os.path.join(WIN_DIR, "runner", "CMakeLists.txt")
    if not os.path.exists(path):
        legacy = os.path.join(WIN_DIR, "CMakeLists.txt")
        if os.path.exists(legacy) and "add_executable" in open(
                legacy, encoding="utf-8").read():
            path = legacy
        else:
            return False, "未找到定义 add_executable 的 CMakeLists.txt"
    text = open(path, encoding="utf-8").read()
    if MARK_CMAKE in text:
        return True, "CMakeLists.txt 已包含 surface 片段"
    if "add_executable" not in text:
        return False, f"{os.path.relpath(path, WIN_DIR)} 缺少 add_executable"
    text = text.rstrip() + "\n\n" + CMAKE_SNIPPET
    open(path, "w", encoding="utf-8").write(text)
    return True, f"已向 {os.path.relpath(path, WIN_DIR)} 追加 surface 源文件"


def patch_runner():
    path = os.path.join(WIN_DIR, "runner", "flutter_window.cpp")
    if not os.path.exists(path):
        return False, "未找到 windows/runner/flutter_window.cpp"
    text = open(path, encoding="utf-8").read()
    changed = False

    if MARK_RUNNER not in text:
        lines = text.splitlines(keepends=True)
        insert_idx = None
        for i, line in enumerate(lines):
            if "RegisterPlugins(" in line:
                insert_idx = i + 1
                break
        if insert_idx is None:
            for i, line in enumerate(lines):
                if "RegisterWithRegistrar(" in line:
                    insert_idx = i + 1
        if insert_idx is None:
            for i, line in enumerate(lines):
                if line.strip().startswith("return true;"):
                    insert_idx = i
                    break
        if insert_idx is None:
            return False, "无法定位 flutter_window.cpp 中的插件注册位置"
        lines.insert(insert_idx, RUNNER_SNIPPET)
        text = "".join(lines)
        changed = True

    if RUNNER_INCLUDE not in text:
        lines = text.splitlines(keepends=True)
        idx = 0
        for i, line in enumerate(lines):
            if line.startswith("#include"):
                idx = i + 1
        lines.insert(idx, RUNNER_INCLUDE + "\n")
        text = "".join(lines)
        changed = True

    if changed:
        open(path, "w", encoding="utf-8").write(text)
        return True, "已在 flutter_window.cpp 注册 surface 插件"
    return True, "flutter_window.cpp 已包含 surface 注册"


# ============================ Android ============================
ANDROID_PATCH_OPEN = "// >>> zip_browser native surface >>>"

GRADLE_SNIPPET = """    // >>> zip_browser native surface >>>
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
    // <<< zip_browser native surface <<<
"""


def integrate_android():
    if not os.path.isdir(AND_DIR):
        print("SKIP 未找到 android/ 目录（跳过 Android 集成）")
        return

    kt_dst_dir = os.path.join(
        AND_DIR, "app", "src", "main", "kotlin", "com", "zipbrowser",
        "zip_browser")
    os.makedirs(kt_dst_dir, exist_ok=True)

    # Kotlin 插件
    shutil.copyfile(
        os.path.join(SURFACE, "android", "NativeSurfacePlugin.kt"),
        os.path.join(kt_dst_dir, "NativeSurfacePlugin.kt"))
    print("OK   复制 NativeSurfacePlugin.kt")

    # MainActivity（注册插件）
    shutil.copyfile(
        os.path.join(SURFACE, "android", "MainActivity.kt"),
        os.path.join(kt_dst_dir, "MainActivity.kt"))
    print("OK   写入 MainActivity.kt（已注册 surface 插件）")

    # cpp + CMake
    cpp_dst = os.path.join(AND_DIR, "app", "src", "main", "cpp")
    os.makedirs(cpp_dst, exist_ok=True)
    shutil.copyfile(
        os.path.join(SURFACE, "android", "zb_native_surface_jni.cpp"),
        os.path.join(cpp_dst, "zb_native_surface_jni.cpp"))
    shutil.copyfile(
        os.path.join(SURFACE, "android", "CMakeLists.txt"),
        os.path.join(cpp_dst, "CMakeLists.txt"))
    print("OK   复制 cpp 与 CMakeLists.txt")

    # patch app/build.gradle.kts
    gradle = os.path.join(AND_DIR, "app", "build.gradle.kts")
    if os.path.exists(gradle):
        text = open(gradle, encoding="utf-8").read()
        if ANDROID_PATCH_OPEN in text:
            print("OK   build.gradle.kts 已包含 externalNativeBuild")
        else:
            anchor = "    buildTypes {"
            if anchor in text:
                text = text.replace(anchor, GRADLE_SNIPPET + anchor, 1)
            else:
                text = text.replace("android {\n",
                                    "android {\n" + GRADLE_SNIPPET, 1)
            open(gradle, "w", encoding="utf-8").write(text)
            print("OK   build.gradle.kts 已注入 externalNativeBuild")
    else:
        print("WARN 未找到 android/app/build.gradle.kts")


def main():
    did = False
    if os.path.isdir(WIN_DIR):
        for fn in (patch_cmake, patch_runner):
            ok, msg = fn()
            print(("OK   " if ok else "FAIL ") + msg)
            if not ok:
                sys.exit(1)
        did = True
    else:
        print("SKIP 未找到 windows/ 目录")

    integrate_android()
    did = True

    if did:
        print("\n完成。下次构建将包含原生表面插件。")


if __name__ == "__main__":
    main()
