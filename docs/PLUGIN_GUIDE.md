# 功能插件开发指南

Zip Browser 的「功能插件」是一个 zip 包（可改后缀为 `.zip`），通过
**设置 → 插件管理 → 安装插件**载入。它可以注入网页脚本、常驻后台、
声明工具栏按钮与菜单，甚至携带一个浏览器内核。

> 想做的是「替换浏览器内核」而不是加功能？请看
> [KERNEL_PACK.md](KERNEL_PACK.md)（独立内核包 `.zbk`）与
> [KERNEL_ABI.md](KERNEL_ABI.md)（原生内核 ABI）。

## 三种扩展机制

由于 Flutter release（AOT）无法在运行时动态执行新的 Dart 代码，插件只能
通过以下三种方式扩展：

| 机制 | 能力 | 适用 |
|---|---|---|
| **JS / content script** | 操作网页 DOM、调用宿主桥 API | 绝大多数功能（去广告、改样式、自动化） |
| **原生库（C ABI）** | dart:ffi 调用 `.dll/.so/.dylib` | 编解码、算法、自带渲染内核 |
| **声明式 UI** | 清单里声明工具栏按钮 / 菜单项 | 简单入口、弹窗页面 |

## 包结构

```
my_plugin.zip
├── plugin.json          必需：插件清单
├── content/             内容脚本
│   └── inject.js
├── background.js        可选：后台常驻脚本
├── popup.html           可选：工具栏弹窗页面
├── icons/
│   └── icon.png
└── README.md            可选
```

## plugin.json 字段

```json
{
  "manifest_version": 1,
  "id": "com.example.darkmode",
  "name": "深色模式",
  "version": "1.0.0",
  "description": "为所有网页强制启用深色配色",
  "author": "your name",
  "homepage": "https://example.com",
  "min_host_version": "0.4.0",
  "permissions": ["storage", "tabs", "downloads", "cookies", "notifications"],
  "host_permissions": ["*://*/*"],
  "web_accessible_resources": ["icons/*.png"],
  "content_scripts": [
    {
      "matches": ["*://*/*"],
      "js": ["content/inject.js"],
      "run_at": "document_end"
    }
  ],
  "background": { "js": ["background.js"] },
  "ui": {
    "toolbar_button": {
      "icon": "icons/icon.png",
      "title": "深色模式",
      "popup": "popup.html"
    },
    "menu_items": [
      { "id": "toggle", "title": "切换深色", "action": "darkmode.toggle" }
    ]
  }
}
```

字段说明：

| 字段 | 必需 | 说明 |
|---|---|---|
| `manifest_version` | 是 | 当前固定为 `1` |
| `id` | 是 | 反向域名格式，如 `com.example.xxx` |
| `name` / `version` | 是 | 名称与语义化版本号 |
| `description` / `author` / `homepage` | 否 | 元信息 |
| `min_host_version` | 否 | 要求的最低宿主版本 |
| `permissions` | 否 | 申请的宿主能力，见下 |
| `host_permissions` | 否 | 允许注入 / 访问的站点匹配 |
| `web_accessible_resources` | 否 | 网页可访问的包内资源 |
| `content_scripts` | 否 | 注入网页的脚本规则 |
| `background` | 否 | 后台常驻脚本（隐藏扩展页面） |
| `ui` | 否 | 声明式工具栏按钮 / 菜单项 |
| `kernel` | 否 | 携带浏览器内核，见 [PLUGIN_KERNEL_GUIDE.md](PLUGIN_KERNEL_GUIDE.md) |

`content_scripts` 规则：`matches`（站点匹配，`<all_urls>` 表示全部）、
`js`（脚本列表，按序注入）、`run_at`（`document_start` / `document_end`）。

## 在脚本中调用宿主能力

宿主在每个页面注入全局对象 **`window.zipBrowser`**。它的 `call` 方法返回
Promise：

```js
// 打开新标签页
const tab = await zipBrowser.call('tabs.create', { url: 'https://example.com' });

// 读写插件本地存储（KV）
await zipBrowser.call('storage.set', { key: 'enabled', value: true });
const v = await zipBrowser.call('storage.get', { key: 'enabled' });

// 监听宿主事件
zipBrowser.on('tabs.updated', (data) => console.log(data));
```

### 宿主 API 方法表

| 方法 | 参数（要点） | 说明 |
|---|---|---|
| `tabs.create` | `{ url, private? }` | 新建标签页 |
| `tabs.close` | `{ tabId? }` | 关闭标签页 |
| `tabs.update` | `{ tabId?, url? }` | 更新标签页 |
| `tabs.query` | — | 查询标签页列表 |
| `tabs.active` | — | 获取当前活动标签页 |
| `storage.get` | `{ key }` | 读取 KV |
| `storage.set` | `{ key, value }` | 写入 KV |
| `storage.remove` | `{ key }` | 删除 KV |
| `storage.keys` | — | 全部键 |
| `downloads.create` | `{ url, filename?, headers? }` | 创建下载 |
| `downloads.query` | — | 查询下载项 |
| `kernel.query` | — | 查询可用内核 |
| `kernel.switch` | `{ id }` | 切换内核 |
| `cookies.get` / `cookies.set` / `cookies.remove` | 标准 cookie 参数 | Cookie 操作（需 `cookies` 权限） |
| `notifications.create` | `{ title, message }` | 弹出通知 |
| `menus.create` / `menus.remove` / `menus.onClick` | — | 菜单 |
| `nativeMessaging.send` / `nativeMessaging.connect` | — | 与原生库通信 |
| `webNavigation.getFrame` / `getAllFrames` | — | 页面框架信息 |

> 调用受 `permissions` 与方法白名单约束；未声明权限的调用会返回错误。

## 用户脚本（Userscript）

除了打包插件，应用也支持安装单文件 **`.user.js`**（菜单 → 用户脚本）。
文件头使用标准 Greasemonkey/Tampermonkey 元数据：

```js
// ==UserScript==
// @name         示例
// @match        *://*/*
// @run-at       document-end
// ==/UserScript==
(function () {
  document.body.style.filter = 'invert(1) hue-rotate(180deg)';
})();
```

## 打包

```bash
# 在插件目录外层，确保 plugin.json 位于 zip 根：
python tool/pack_plugin.py path/to/my_plugin_dir my_plugin.zip
```

安装：**插件管理 → 安装插件**，选择该 zip。

## 示例

仓库 `example_plugins/` 下提供：

- `dark_mode.zip`：纯 JS 功能扩展示例；
- `hello_ffi_kernel`：携带原生内核的插件（含 dll/so）。
