# Requirements Document

## Introduction

Zip Browser 目前的界面按竖屏手机优先设计：屏幕方向完全跟随系统，横屏下顶栏堆叠挤压内容区；内核能力只存在于底层（`KernelRegistry` / `KernelManager`），设置页仅展示当前内核，用户无法通过界面切换、安装或卸载内核包。本特性补齐横屏适配、内核选择界面，并追加三项用户可感知的增强能力（护眼调光、底栏滑动切换标签、标签中键关闭）。

## Glossary

- **系统**：Zip Browser 浏览器应用本体。
- **宿主平台**：运行浏览器的操作系统与设备形态（Android、Windows、Linux）。
- **内核**：提供网页渲染与页面能力的组件，包含系统内核、独立内核包（`.zbk`）与插件携带内核。
- **内核包**：以 `.zbk` 归档分发、安装到 `AppPaths.kernelsDir` 的独立内核。
- **紧凑布局**：屏幕宽度小于 720 逻辑像素，或横屏且高度小于 560 逻辑像素时的界面形态。
- **侧边导航栏**：横屏且启用底部导航栏时，替代底部导航栏的竖排图标导航条。
- **方向锁定**：设置项，取值为跟随系统、锁定竖屏、锁定横屏。
- **护眼调光**：在全界面之上叠加可调黑色遮罩的显示效果，用于降低夜间亮度。
- **候选内核**：`KernelRegistry.describe()` 返回的内核描述列表。

## Requirements

### Requirement 1

**User Story:** 作为使用横屏设备的用户，我希望界面在横屏下自动重排，以便内容区保留足够的可视高度。

#### Acceptance Criteria

1. WHEN 屏幕宽度小于 720 逻辑像素，THE 系统 SHALL 采用紧凑布局。
2. WHILE 屏幕处于横屏且高度小于 560 逻辑像素，THE 系统 SHALL 采用紧凑布局。
3. WHEN 屏幕处于横屏且用户启用底部导航栏，THE 系统 SHALL 以侧边导航栏替代底部导航栏。
4. WHILE 侧边导航栏显示，THE 系统 SHALL 提供后退、前进、主页、工具箱、主菜单五个入口。
5. WHEN 屏幕宽度大于等于 780 逻辑像素，THE 设置在设置页与内核管理页中的内容 SHALL 以最大 780 逻辑像素宽度居中显示。

### Requirement 2

**User Story:** 作为用户，我希望能够锁定屏幕方向，以便在床上或固定支架场景下获得稳定的浏览体验。

#### Acceptance Criteria

1. THE 系统 SHALL 提供跟随系统、锁定竖屏、锁定横屏三种方向模式。
2. WHEN 用户选择锁定竖屏，THE 系统 SHALL 仅允许竖屏方向。
3. WHEN 用户选择锁定横屏，THE 系统 SHALL 仅允许横屏方向。
4. WHEN 用户选择跟随系统，THE 系统 SHALL 允许全部方向。
5. WHEN 用户重启应用，THE 系统 SHALL 恢复上次选择的方向模式。

### Requirement 3

**User Story:** 作为用户，我希望在设置中查看、切换、安装和卸载内核，以便按需选择渲染引擎。

#### Acceptance Criteria

1. THE 系统 SHALL 在内核管理页列出平台默认内核与全部候选内核。
2. WHILE 候选内核不可用，THE 系统 SHALL 显示不可用原因并禁止选中该内核。
3. WHEN 用户选中一个可用内核，THE 系统 SHALL 持久化该选择并提示新标签页生效。
4. WHEN 用户选择平台默认，THE 系统 SHALL 清除已保存的内核选择。
5. WHEN 用户安装 `.zbk` 内核包，THE 系统 SHALL 完成安装并刷新内核列表。
6. WHEN 用户卸载独立内核包，THE 系统 SHALL 删除该包目录；若该包为当前选中内核，THE 系统 SHALL 恢复为平台默认。
7. IF 安装目录被篡改，THE 系统 SHALL 在页面上展示告警且不提供选中入口。

### Requirement 4

**User Story:** 作为夜间用户，我希望调节全界面亮度，以便在暗环境中减少刺眼。

#### Acceptance Criteria

1. THE 系统 SHALL 提供 0 至 0.6 的护眼调光强度设置。
2. WHEN 调光强度大于 0，THE 系统 SHALL 在应用界面之上叠加对应不透明度的黑色遮罩且不拦截触摸事件。
3. WHEN 用户从主菜单触发护眼调光，THE 系统 SHALL 在强度为 0 时切换到 0.35，在强度大于 0 时切换为 0。

### Requirement 5

**User Story:** 作为触屏用户，我希望在底部导航栏滑动切换标签页，以便单手快速切换。

#### Acceptance Criteria

1. WHEN 用户在底部导航栏区域向左滑动，THE 系统 SHALL 激活下一个标签页。
2. WHEN 用户在底部导航栏区域向右滑动，THE 系统 SHALL 激活上一个标签页。

### Requirement 6

**User Story:** 作为桌面用户，我希望用鼠标中键关闭标签页，以便获得与桌面浏览器一致的效率。

#### Acceptance Criteria

1. WHEN 用户在标签块上按下鼠标中键，THE 系统 SHALL 关闭该标签页。
