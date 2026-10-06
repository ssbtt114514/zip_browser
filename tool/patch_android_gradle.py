#!/usr/bin/env python3
"""
为 Flutter 生成的 Android 工程补丁 build.gradle.kts。

问题：部分插件（如 file_picker）子模块硬编码了较低的 compileSdk，
但其依赖的 AndroidX 库要求更高的 compileSdk，导致 Gradle 报
`:xxx:checkReleaseAarMetadata` 失败。

做法：在 android/build.gradle.kts 的第一个 subprojects 块内注册 afterEvaluate，
把各插件子模块的 compileSdk 统一提升到 36。
必须放在 `evaluationDependsOn(":app")` 之前注册，否则部分子项目已完成求值。

前置：已执行 `flutter create --platforms=android .` 生成 android/ 目录。
用法：python3 tool/patch_android_gradle.py
幂等：重复执行不会重复插入。
"""
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRADLE_FILE = os.path.join(ROOT, "android", "build.gradle.kts")

COMPILE_SDK = 36

MARKER = "// >>> zip_browser compileSdk pin >>>"

SNIPPET = f"""
    {MARKER}
    // 强制插件子模块使用 compileSdk {COMPILE_SDK}：部分插件硬编码了较低版本，
    // 但其依赖要求 {COMPILE_SDK}，否则 checkReleaseAarMetadata 失败。
    afterEvaluate {{
        val androidExt = extensions.findByName("android")
        when (androidExt) {{
            is com.android.build.gradle.LibraryExtension ->
                androidExt.compileSdkVersion({COMPILE_SDK})
            is com.android.build.gradle.AppExtension ->
                androidExt.compileSdkVersion({COMPILE_SDK})
        }}
    }}
    // <<< zip_browser compileSdk pin <<<
"""


def main():
    if not os.path.isfile(GRADLE_FILE):
        print("错误：未找到 android/build.gradle.kts，"
              "请先执行 flutter create --platforms=android .")
        sys.exit(1)

    text = open(GRADLE_FILE, encoding="utf-8").read()
    if MARKER in text:
        print("OK   android/build.gradle.kts 已包含 compileSdk 补丁")
        return

    idx = text.find("subprojects {")
    if idx == -1:
        print("FAIL android/build.gradle.kts 中未找到 subprojects 块，无法插入补丁")
        sys.exit(1)

    # 插入到第一个 subprojects 块的开括号之后
    brace = text.index("{", idx) + 1
    text = text[:brace] + "\n" + SNIPPET + text[brace:]
    open(GRADLE_FILE, "w", encoding="utf-8").write(text)
    print(f"OK   已为 android/build.gradle.kts 注入 compileSdk {COMPILE_SDK} 补丁")


if __name__ == "__main__":
    main()
