# v0.12.0

## 破坏性变更

- **移除 zip 功能插件接口**：插件管理页、工具栏扩展按钮、受信任插件白名单
  开关全部下线。独立浏览器内核改由 .zbk 内核包机制承载（内核管理页不变）。
  「完整版 / 单内核版 / 无内核版」三种构建风味继续保留。

## 修复

- **Windows 安装器（安装后无法运行系列）**：
  - 修复 CI 向 ISCC 传 `/DFavor=` 而脚本读取 `#ifndef Flavor` 的拼写错位：
    此前三种风味的安装器全部按「完整版」打包，AppId 相同、输出文件同名互相
    覆盖。现在 single / none 安装器拥有独立 AppId、独立安装目录与正确命名。
  - 沿用 v0.10 系列的运行时保障：安装时静默装 VC++ 运行库与 WebView2
    常青版，Release 目录 app-local 捆绑 VCRUNTIME140 / WebView2Loader.dll。

## 新增

- **文字识别（OCR）**：菜单「工具 → 文字识别（图片取字）」，选图取字、
  可一键复制。Android 内置 ML Kit 离线识别（中文脚本，图片不上传，
  原生库由 patch_android_gradle.py 注入）；Windows / Linux 走
  「设置 → AI 解读」配置的多模态接口（如 gpt-4o-mini）。
- **AI 视觉取字**：AiService 新增多模态消息支持（image_url + base64），
  OCR 与后续图片理解共用该通道。
- **二级菜单**：桌面主菜单重构为「标签页 / 页面 / 数据 / 显示 / 工具 / 系统」
  六组二级菜单（MenuAnchor + SubmenuButton），开关项带勾选状态，
  快捷键提示保留；窄屏底部面板沿用扁平分组。

## 变更

- Android minSdk 钉死 21（Flutter 引擎下限），Android 4.0–4.4 的支持尝试
  结论与原因见 docs/ANDROID_COMPAT.md。
- 开发者工具箱「插件系统」行改为「已移除（v0.12.0）」；使用手册同步更新。
