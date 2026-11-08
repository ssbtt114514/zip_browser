# 需求规格：v0.12.0 平台修复 / OCR / 二级菜单 / 插件接口移除

日期：2026-11-08
状态：已实现
关联：v0.10.x「安装后无法运行」修复系列、build_flavor 三风味机制

## 1. 背景与目标

用户提出一批需求：修复 Windows 安装后无法运行；删除浏览器插件接口；所有平台
提供无内核 / 单内核版本；内置莫奈取色；液态玻璃；文字识别；AI 读取网页；
优化二级菜单；尝试支持 Android 4 / 4.4；检查更新；用户数据导出；开发者工具箱；
翻译；减少冗余功能。

其中大部分能力已在 v0.10.x – v0.11.0 落地（内置莫奈引擎、液态玻璃 ZbGlassBox、
AI 解读、翻译、检查更新、数据导出、开发者工具箱、三种构建风味）。本批次补齐
真实缺口并收敛冗余。

## 2. 需求清单（EARS 摘要）

### R1 Windows 安装器风味修复
- WHEN CI 以风味 `single|none` 调用 ISCC 时，THE installer SHALL 使用对应
  风味的 AppId / 安装目录 / 输出文件名。
- 约束：`build-windows.yml` 必须传 `/DFlavor=`（原 `/DFavor=` 为拼写错误，
  导致三风味安装器全部按 full 打包并互相覆盖）。

### R2 删除浏览器插件接口
- THE app SHALL 在所有构建风味下移除 zip 功能插件的全部用户入口：
  主菜单「插件管理」、工具栏扩展按钮、设置页「受信任插件白名单」开关。
- THE app SHALL 保留独立内核包（.zbk）安装与切换能力（内核管理页）。
- THE 插件管理页 SHALL 变更为占位说明页。
- 约束：内核加载机制（FFI 加载器 / PluginManager 内部协作）保留——
  独立内核包与集成测试（ffi_kernel_integration_test）依赖它。

### R3 文字识别（OCR）
- WHEN 用户在菜单选择「文字识别（图片取字）」并选择本地图片时，
  THE app SHALL 输出图中文字并支持一键复制。
- Android 上 SHALL 使用内置离线识别（ML Kit 中文脚本），图片不上传。
- WHEN 平台无内置识别（Windows / Linux）且用户已配置 AI 接口时，
  THE app SHALL 通过 OpenAI 兼容多模态接口识别。
- WHEN 平台无内置识别且 AI 未配置时，THE app SHALL 给出可照做的配置指引。

### R4 优化二级菜单
- THE 桌面主菜单 SHALL 按「标签页 / 页面 / 数据 / 显示 / 工具 / 系统」
  分组呈现二级菜单，开关项带勾选状态，快捷键提示保留。
- THE 窄屏底部面板 SHALL 沿用扁平分组并与桌面共用动作处理函数。

### R5 Android 4 / 4.4 支持尝试
- THE 项目 SHALL 明确尝试并记录 Android 4.x 的支持结论。
- 结果：不可行（Flutter 3.22 引擎要求 minSdk 21；KitKat WebView 停更于
  Chromium 33/37），minSdk 钉死 21，结论沉淀到 docs/ANDROID_COMPAT.md。

### R6 已有能力确认（本批次仅复核）
- 内置莫奈引擎（ZbMonetEngine，material_color_utilities HCT）✓
- 液态玻璃（ZbGlassBox）✓
- AI 解读网页（AiService.extractPageText + chat）✓
- 翻译（TranslateService，Google gtx + MyMemory 回落）✓
- 检查更新（UpdateService + UpdateCheckHelper）✓
- 用户数据导出（DataExportService JSON 快照）✓
- 开发者工具箱（DevToolsPage）✓
- 无内核 / 单内核 / 完整版三风味（BuildFlavor + CI matrix）✓

## 3. 验收标准

1. `grep` 全仓不再出现插件功能入口（PluginsPage 仅存占位说明）。
2. `python3 tool/patch_android_gradle.py` 在 flutter create 产物上可注入
   minSdk 21 与 ML Kit 中文识别依赖（幂等）。
3. build-windows.yml 的 ISCC 参数与 installer.iss 的 `#ifndef Flavor` 对齐。
4. 仓库 `python3 tool/verify_all.py` 通过（无 Flutter 工具链时相关项 SKIP）。
