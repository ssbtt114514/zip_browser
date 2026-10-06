# 示例插件：夜间模式（JS 扩展）

演示内容：

1. `content_scripts` 在每个页面 `document_end` 注入 `extension.js`
2. 注入样式，把网页反相为深色
3. 通过 bridge 以 `storage` 权限统计注入次数

## 打包

```bash
# 在工程根目录
python tool/pack_plugin.py example_plugins/dark_mode
# 生成 dark_mode.zip
```

## 安装

浏览器 → 菜单 → 插件管理 → 安装 .zip → 选择 `dark_mode.zip`。
启用后打开任意网页即可看到深色效果。
