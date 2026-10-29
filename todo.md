# TODO（先做基础功能）

## P0 - Review收敛（安全 + UI规范）

- [ ] 安全：收紧 ATS 配置（禁止全局 `NSAllowsArbitraryLoads`）
  - [ ] 移除 `beauty_wall/Info.plist` 中全局 ATS 放开
  - [ ] 若确有例外，改为最小域名白名单
  - [ ] 回归：Bing / NASA / Wallhaven / Unsplash / 本地目录刷新均可用
- [ ] 安全：移除未使用的 Photos Library entitlement
  - [ ] 删除 `com.apple.security.personal-information.photos-library`
  - [ ] 回归：本地目录读取与壁纸设置不受影响
- [ ] UI架构：拆分 `SettingsView`（避免单文件多职责）
  - [ ] 提取 `GeneralSettingsView`
  - [ ] 提取 `CredentialsSettingsView`
  - [ ] 提取 `SourcesSettingsView` + 来源详情子视图
  - [ ] 验收：`SettingsView.swift` 仅保留 Tab 容器与装配逻辑
- [ ] UI模式：来源配置页改为原生 `NavigationSplitView + List(.sidebar)`
  - [ ] 左侧来源列表迁移为原生 sidebar list（保留单选与状态）
  - [ ] 删除侧栏自绘背景（不再用 `Color(NSColor.controlBackgroundColor)` 覆盖）
  - [ ] 验收：支持键盘上下选择，系统高亮与焦点行为正常
- [ ] UI可访问性：来源列表状态避免仅靠颜色表达
  - [ ] 当前“绿色/橙色圆点”改为“图标 + 简短文本”或补充次级说明行
  - [ ] 验收：在灰度/低色差场景下仍可区分“生效中/需配置”
- [ ] 菜单栏 UX：限制来源菜单文本长度（建议 <= 30 字符）
  - [ ] 菜单项标题做截断或摘要
  - [ ] 完整名称仅在设置页详情显示
  - [ ] 验收：长预设名不撑坏菜单可读性
- [ ] 桌面交互：补齐核心动作的 commands/快捷键入口
  - [ ] 为“立即刷新壁纸”“打开设置”提供 `commands` 层入口
  - [ ] 验收：除菜单点击外，可通过键盘快捷键触达核心动作
- [ ] 场景一致性：清理未接入场景树的 `ContentView` 重复刷新流
  - [ ] 删除或改为纯 Preview 用示例
  - [ ] 统一只保留 `MenuBarView + WallpaperRefreshController` 作为主路径

## P0 - 立即确认（基础）

- [ ] 首次打开设置页默认定位到「通用」页（已实现，需你回归确认）
- [ ] 凭证重启后不丢失（Keychain 持久化）
  - [ ] 本地验证：填入 Wallhaven/Unsplash Key 后重启应用，确认仍存在
  - [ ] 若出现丢失，补充最小排查（保存失败日志）
- [ ] 菜单来源保持二级结构且互斥单选
  - [ ] `切换来源 -> Wallhaven/Unsplash`
  - [ ] 任意时刻仅一个来源被勾选

## P1 - 稳定性（仍属基础）

- [ ] 处理历史 Keychain 数据兼容（旧 service -> 新 service 自动迁移）
- [ ] 若 Keychain 写入失败，在设置页给出可见错误提示（短文案）
- [ ] 菜单栏支持“打开当前壁纸原页面”（跳转来源详情页）
- [ ] 所有平台补齐参数配置（常用参数 + 高级参数，统一交互结构）
- [ ] 壁纸缓存管理（防止磁盘持续增长）
  - [ ] 增加缓存上限策略（按文件数或总大小）
  - [ ] 超限后自动删除最早文件
  - [ ] 设置页可配置并展示当前缓存占用

## P2 - 云同步（后续，不阻塞 MVP）

- [ ] 明确同步边界：
  - [ ] 非敏感配置（来源、参数、偏好）可同步
  - [ ] 敏感凭证（API Key）默认仅本地 Keychain
- [ ] 技术路线评估（选一）：
  - [ ] Apple 优先：CloudKit + Keychain
  - [ ] 跨平台优先：Supabase（Mac 可用）
- [ ] 输出一版同步设计文档（字段、冲突策略、开关策略）
