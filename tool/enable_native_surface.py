#!/usr/bin/env python3
"""
将 native_plugins/zb_native_surface 集成进 Flutter Windows 构建。

前置：已执行 `flutter create --platforms=windows .` 生成 windows/ 目录。
用法：python tool/enable_native_surface.py
幂等：重复执行不会重复追加。
"""
import os
import sys

# Windows 控制台默认编码可能不是 UTF-8，显式切换以避免中文输出报 UnicodeEncodeError
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIN_DIR = os.path.join(ROOT, "windows")

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
# <<< zip_browser native surface <<<
"""

# 模板里引擎成员名是 flutter_controller_；FlutterEngine 继承 PluginRegistry，
# 用 GetRegistrarForPlugin(名字) 取得 FlutterDesktopPluginRegistrarRef。
RUNNER_SNIPPET = """  // >>> zip_browser native surface >>>
  ZipBrowserNativeSurfacePluginRegisterWithRegistrar(
      flutter_controller_->engine()->GetRegistrarForPlugin(
          "ZipBrowserNativeSurface"));
  // <<< zip_browser native surface <<<
"""

RUNNER_INCLUDE = '#include "zb_native_surface_plugin.h"'


def patch_cmake():
    # add_executable 位于 windows/runner/CMakeLists.txt（新版 Flutter）
    path = os.path.join(WIN_DIR, "runner", "CMakeLists.txt")
    if not os.path.exists(path):
        # 兼容旧布局：顶层 windows/CMakeLists.txt
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
        # 优先紧跟引擎插件注册调用；否则退回其他 *_RegisterWithRegistrar 调用之后；
        # 再退回到 Run() 的 return 前。
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


def main():
    if not os.path.isdir(WIN_DIR):
        print("错误：未找到 windows/ 目录，请先执行 flutter create --platforms=windows .")
        sys.exit(1)

    for fn in (patch_cmake, patch_runner):
        ok, msg = fn()
        print(("OK   " if ok else "FAIL ") + msg)
        if not ok:
            sys.exit(1)

    print("\n完成。下次 flutter run -d windows 将包含原生表面插件。")


if __name__ == "__main__":
    main()
