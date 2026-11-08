#!/usr/bin/env python3
"""
为 Flutter 生成的 Android 工程补丁 gradle 文件。

1. build.gradle.kts：部分插件（如 file_picker）子模块硬编码了较低的 compileSdk，
   但其依赖的 AndroidX 库要求更高的 compileSdk，导致 Gradle 报
   `:xxx:checkReleaseAarMetadata` 失败。做法：在第一个 subprojects 块内注册
   afterEvaluate，把各插件子模块的 compileSdk 统一提升到 36。
   必须放在 `evaluationDependsOn(":app")` 之前注册，否则部分子项目已完成求值。
2. app/build.gradle.kts：把 minSdk 钉到 21（Flutter 引擎下限，
   Android 4.0–4.4 无法支持，结论见 docs/ANDROID_COMPAT.md）。
3. app/build.gradle.kts：注入 ML Kit 文字识别（中文脚本）原生库依赖，
   供 lib/services/ocr_service.dart 的 OCR 功能使用。

前置：已执行 `flutter create --platforms=android .` 生成 android/ 目录。
用法：python3 tool/patch_android_gradle.py
幂等：重复执行不会重复插入。
"""
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRADLE_FILE = os.path.join(ROOT, "android", "build.gradle.kts")
APP_GRADLE_FILE = os.path.join(ROOT, "android", "app", "build.gradle.kts")

COMPILE_SDK = 36

# 应用 minSdk 下限：Flutter 3.22 引擎自身要求 21（Android 5.0），
# 低于 21 无法启动（Android 4.0–4.4 因此无法支持，见 docs/ANDROID_COMPAT.md）。
MIN_SDK = 21

# ML Kit 文字识别（中文脚本）原生库：google_mlkit_text_recognition 插件只带
# API，各脚本模型需在 app gradle 自行引入（pub.dev 插件 README 的要求）。
MLKIT_CHINESE_VERSION = "16.0.1"
MLKIT_MARKER = "// >>> zip_browser mlkit ocr >>>"
MLKIT_SNIPPET = f"""
{MLKIT_MARKER}
dependencies {{
    // 文字识别（OCR）中文脚本原生库；lib/services/ocr_service.dart 使用
    // TextRecognitionScript.chinese，缺了它运行时会报脚本识别器缺失。
    implementation("com.google.mlkit:text-recognition-chinese:{MLKIT_CHINESE_VERSION}")
}}
// <<< zip_browser mlkit ocr <<<
"""

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


def patch_root_compile_sdk():
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


def patch_app_min_sdk():
    """把 app minSdk 钉到 21：文档化下限，防止模板默认值漂移。"""
    if not os.path.isfile(APP_GRADLE_FILE):
        print("WARN 未找到 android/app/build.gradle.kts，跳过 minSdk 钉定")
        return
    text = open(APP_GRADLE_FILE, encoding="utf-8").read()
    # 入库的 gradle 已把 minSdk 钉到 21（flutter create 重生成时才会是模板默认值）
    if re.search(r"minSdk\s*=\s*21\b", text):
        print("OK   android/app/build.gradle.kts 已把 minSdk 钉到 21")
        return
    needle = "minSdk = flutter.minSdkVersion"
    if needle not in text:
        print("WARN app gradle 未找到 minSdk = flutter.minSdkVersion，跳过钉定")
        return
    text = text.replace(
        needle,
        f"minSdk = {MIN_SDK} // zip_browser minSdk：固定 {MIN_SDK}"
        "（Android 5.0；Flutter 引擎下限，见 docs/ANDROID_COMPAT.md）",
        1,
    )
    open(APP_GRADLE_FILE, "w", encoding="utf-8").write(text)
    print(f"OK   已把 app minSdk 钉到 {MIN_SDK}")


def patch_app_mlkit():
    """注入 ML Kit 中文文字识别原生库依赖（OCR 功能所需）。"""
    if not os.path.isfile(APP_GRADLE_FILE):
        print("WARN 未找到 android/app/build.gradle.kts，跳过 ML Kit 依赖注入")
        return
    text = open(APP_GRADLE_FILE, encoding="utf-8").read()
    if MLKIT_MARKER in text or "text-recognition-chinese" in text:
        print("OK   android/app/build.gradle.kts 已包含 ML Kit 依赖")
        return
    text = text.rstrip() + "\n" + MLKIT_SNIPPET
    open(APP_GRADLE_FILE, "w", encoding="utf-8").write(text)
    print("OK   已注入 ML Kit 中文文字识别依赖（text-recognition-chinese）")


def main():
    if not os.path.isfile(GRADLE_FILE):
        print("错误：未找到 android/build.gradle.kts，"
              "请先执行 flutter create --platforms=android .")
        sys.exit(1)
    patch_root_compile_sdk()
    patch_app_min_sdk()
    patch_app_mlkit()


if __name__ == "__main__":
    main()
