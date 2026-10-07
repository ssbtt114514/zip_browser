# Zip Browser v0.8.0 —— 字体 / 开关 / 相机 / 布局五项改进

## 新增功能

- **自定义字体，默认内置 OPPO Sans**：内置 OPPO Sans 4.0（官方免费商用授权，中文显示更统一）；外观设置新增「字体」分区，可在 内置 OPPO Sans / 跟随系统 / 导入本地 .ttf/.otf 之间切换，导入后即时生效无需重启。
- **开关视觉优化**：开关打开时滑块为背景色、轨道为主题色（Material 全局主题 + 设置开关），状态一眼可辨；Cupertino 风格同步。
- **剪贴板链接检测可关闭**：外观 → 浏览器界面 新增「剪贴板链接检测」开关，关闭后不再轮询剪贴板、不弹提示。
- **修复 Android 网页文件上传无法调用相机**：`input[type=file] accept="image/*" capture` 现在会拉起系统相机（ACTION_IMAGE_CAPTURE + FileProvider 临时文件），无相机应用自动回退相册；普通文件选择走系统文件选择器并支持多选。
- **底部导航栏模式顶栏精简**：启用底部导航栏（窄屏）时，顶部只保留搜索框；后退/前进/主页/工具箱/扩展/菜单全部收到底部导航栏，书签栏同步收起，操作不重复、布局更干净。

## 其他

- Android 构建基于 compileSdk 36；新增 androidx.core 依赖用于 FileProvider。
- 内置字体使 APK 体积增加约 16MB（原始字体 22MB，zip 压缩后约 16MB）。

## 安装包

- Android：4 个按 ABI 拆分的 APK（arm64-v8a / armeabi-v7a / x86_64）+ 通用（universal）APK
- Windows：zip 绿色版 + Inno Setup 安装程序（x64）
- Linux：amd64 / arm64（deb + tar.gz）
- 浏览器内核：zb_lite / zb_gecko / zb_chromium 三套内核包（Windows / Linux / Android 按平台拆分）

> 说明：Android APK 使用 debug 签名，CI 矩阵自动构建；安装器与内核包见同目录。
