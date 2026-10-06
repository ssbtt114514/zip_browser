#!/usr/bin/env bash
# ============================================================
#  Zip Browser 工程初始化（Linux/macOS 主机，目标平台 Android/Windows/Linux）
# ============================================================
set -e
flutter create --platforms=android,windows,linux --org com.zipbrowser --project-name zip_browser .
flutter pub get

# —— 浏览器必需的平台补丁（幂等）——
python3 tool/patch_android_gradle.py || echo "WARN: gradle 补丁未应用"
python3 tool/patch_android_manifest.py || echo "WARN: manifest 补丁未应用"
# 应用图标（SVG -> 各分辨率；需 pip install cairosvg）
python3 tool/make_app_icon.py || echo "WARN: 图标未生成（可 pip install cairosvg 后重跑）"
# 插件内核 native surface
python3 tool/enable_native_surface.py || echo "WARN: native surface 未启用"

echo ""
echo "初始化完成。"
echo "  运行 Android：flutter run -d <android-device>"
echo "  运行 Windows：flutter run -d windows（需 Windows 主机）"
echo "  运行 Linux：  flutter run -d linux（需 libwebkit2gtk-4.1-dev）"
