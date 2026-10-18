# Zip Browser v0.10.0 —— Chrome 风格 UI

UI 全面转向 Chrome 设计语言：标签条与工具栏无缝融合、圆形按钮反馈、
扁平底部导航、大圆角 Omnibox 与 Chrome 式新标签页。

## 🎨 界面风格（Chrome 化）

- **标签条 Chrome 化**：标签条使用窗口底色；活动标签与下方工具栏同色
  "切入"融合（顶部大圆角、底部直角、无边框无浮起阴影），非活动标签透明、
  悬停才显色——与 Chrome 桌面的标签结构一致；
- **圆形按钮反馈**：工具栏按钮与底部导航按钮的 hover/按下反馈统一为圆形
  （Chrome 风格），按压带回弹动画；
- **底部导航扁平化**：从 Firefox 悬浮 dock 改为 Chrome 移动端扁平工具条
  （贴底、顶部细分隔线、无阴影）；
- **Omnibox 大圆角**：地址栏与首页搜索框升级为大圆角胶囊（24px）；
- **新标签页**：延续 Chrome 式居中搜索胶囊 + 快捷磁贴宫格 + 最近访问。

## 🚀 其它

- 沿用 v0.9 的广告拦截、性能优化与标签上限保护；
- 功能零删减：二级工具栏、阅读/滤镜、嗅探、扫一扫、插件与内核体系全部保留。

## 📦 构建产物

- Android：按 ABI 拆包（armeabi-v7a / arm64-v8a / x86_64）+ 通用包；
- Windows：setup.exe 安装器 + zip；
- Linux：deb（amd64 / arm64）+ tar.gz（amd64 / arm64）；
- 独立内核包：chromium / gecko / lite 按平台拆分 .zbk。

## 🙏 关于

作者 ssbtt114514，主页 https://ssbtt114514.github.io
