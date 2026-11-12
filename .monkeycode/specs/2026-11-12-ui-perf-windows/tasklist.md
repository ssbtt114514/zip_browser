# 任务清单：UI 风格、网页体验与 Windows 平台能力

## 阶段一：Windows 莫奈取色

- [x] 1.1 扩展 Windows 原生插件：`readSystemTheme`（强调色 / 深色 / 壁纸路径）
- [x] 1.2 新增 `windows_system_theme.dart` 与 `wallpaper_color.dart`（含纯函数与单测）
- [x] 1.3 `AppearanceSettings` 增加 `MonetSource.wallpaper` 与运行期种子覆盖
- [x] 1.4 `ThemeEngine` 按新优先级合成配色
- [x] 1.5 启动引导 `windows_theme_bootstrap.dart` + 设置页取色源选项
- [x] 1.6 单元测试：壁纸主色提取、配色优先级

## 阶段二：Windows 开发者工具

- [x] 2.1 调试注入脚本（console / error / network hook）与 JsBridge 通道
- [x] 2.2 内置 DevTools 面板（控制台 / 执行 JS / 页面信息 / 网络）
- [x] 2.3 原生 DevTools 窗口入口（webview_windows）+ 设置开关 + F12
- [x] 2.4 单元测试：注入脚本生成与消息解析

## 阶段三：界面 Google 风格

- [x] 3.1 盘点并统一 Material 3 组件用法（按钮/Switch/对话框/列表）
- [x] 3.2 统一间距与圆角 token，补 M3 动效
- [x] 3.3 回归：Cupertino 风格开关仍可用

## 阶段四：网页访问 / 字体 / 内存

- [x] 4.1 `WebViewTuningService`：预连接与脚本注入收敛、可开关
- [x] 4.2 字体渲染：界面字体与网页字体分离，设置项与注入 CSS
- [x] 4.3 后台标签内存策略（阈值 + 快照恢复 + 开关）
- [x] 4.4 性能与内存相关单测

## 阶段五：更多功能（待用户补充清单）
