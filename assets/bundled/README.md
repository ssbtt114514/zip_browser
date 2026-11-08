# 内置内核包目录

Gecko 风味构建时，CI 会把对应平台/架构的内核包写入本目录：

```
assets/bundled/kernel.zbk
```

应用首次启动时由 `lib/services/bundled_kernel_seeder.dart` 安装并选中该内核。
Chromium / 无内核风味不放置该文件，直接使用系统 WebView 或占位内核。

本目录必须保留（Flutter 资产声明依赖目录存在），`.zbk` 文件不纳入版本库。
