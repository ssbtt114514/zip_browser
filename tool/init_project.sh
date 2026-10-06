#!/usr/bin/env bash
# ============================================================
#  Zip Browser 工程初始化（Linux/macOS 主机，目标平台 Android/Windows/Linux）
# ============================================================
set -e
flutter create --platforms=android,windows,linux --org com.zipbrowser --project-name zip_browser .
flutter pub get
echo ""
echo "初始化完成。"
echo "  运行 Android：flutter run -d <android-device>"
echo "  运行 Windows：flutter run -d windows（需 Windows 主机）"
echo "  运行 Linux：  flutter run -d linux（需 libwebkit2gtk-4.1-dev）"
echo "  启用插件内核表面：python3 tool/enable_native_surface.py"
