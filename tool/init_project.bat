@echo off
REM ============================================================
REM  Zip Browser 工程初始化（Windows）
REM  生成 android / windows / linux 平台目录并拉取依赖
REM ============================================================
flutter create --platforms=android,windows,linux --org com.zipbrowser --project-name zip_browser .
if errorlevel 1 exit /b 1
flutter pub get
echo.
echo 初始化完成。
echo   运行 Android：flutter run -d ^<android-device^>
echo   运行 Windows：flutter run -d windows
echo   运行 Linux：  flutter run -d linux（需 libwebkit2gtk-4.1-dev）
echo   启用插件内核表面：python tool\enable_native_surface.py
