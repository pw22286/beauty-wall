# 自动壁纸更换器 (macOS 原生版) - 项目计划

本项目旨在开发一款 macOS 原生应用，能够自动从多个壁纸源平台（如 Wallhaven、Unsplash 等）获取高质量壁纸，并定时后台更换为系统桌面背景。

## 1. 核心功能需求
- **多壁纸源对接**：支持无缝切换不同的壁纸来源（最初计划支持 Wallhaven 和 Unsplash）。
- **壁纸下载与管理**：将选定的壁纸图片下载存储到本地指定路径。
- **自动更换引擎**：根据设置的频率（每小时、每天等）定时或自动触发更换。
- **macOS 系统集成**：通过 macOS 系统 API (`NSWorkspace`) 将下载的图片设置为桌面背景。
- **灵活配置面板**：
  - **全局配置**：存储路径、基础更换频率、开机自启等。
  - **按源独立配置**：
    - **Wallhaven**: 搜索条件（标签、分辨率、宽高比、颜色、SFW/NSFW级别）
    - **Unsplash**: 搜索关键字、分类 (Collections)、特定贡献者、定向方向 (横屏/竖屏) 等。
- **用户凭证自助配置**：每个壁纸源由用户填写自己的 API Token / Key，避免所有用户共用开发者 Token 触发平台限流。
- **手动控制与预览**：提供手动触发“更换下一张”的选项以及当前/即将更换壁纸的来源信息及预览。
- **健壮性保障**：完善的网络请求重试、API 限流处理和文件系统异常处理。

## 2. 拟定技术栈 (Apple Native)
- **编程语言**：Swift
- **UI 框架**：SwiftUI (主干，现代且高效，用于构建多源设置面板和菜单栏界面)
- **网络通信**：`URLSession` (Swift 原生请求) + `Codable` (JSON 解析)
- **系统集成**：`AppKit` / `NSWorkspace` API (处理壁纸设置与系统级交互)
- **数据持久化**：`UserDefaults` (轻量配置) 或 `AppStorage` / `Codable` 存档保存多数据源独立配置。
- **定时调度**：`Timer` 或 `DispatchSourceTimer` (用于后台运行时的定时任务)

## 3. 架构设计与开发阶段建议

### 阶段一：基础架构与抽象设计 (Architecture & Protocols)
- 定义壁纸数据模型抽象（整合不同平台返回的数据以适配统一 UI）。
- 定义 `WallpaperProvider` 协议，抽象 `fetchRandomWallpaper()` 等方法。
- 实现 `WallhavenProvider` 以及 `UnsplashProvider` 两个具体实现。
- 打通通过 `NSWorkspace` 设定本地图片为系统壁纸的 API 流程。
- **里程碑**：实现一个可以通过切换实例来从不同平台获取图片并设置为壁纸的底层逻辑。

### 阶段二：多源独立配置与数据持久化
- 定义全局配置模型。
- 定义遵循各源特点的独立配置数据模型（如 `WallhavenConfig` 和 `UnsplashConfig`）。
- 定义 Provider 凭证模型（如 `WallhavenCredential`, `UnsplashCredential`），并采用 Keychain 保存敏感 Token。
- 实现配置存储服务的序列化封装，以支持复杂的层级设置项（非敏感配置存 `UserDefaults/AppStorage`，敏感凭证存 `Keychain`）。

### 阶段三：UI/UX 设计与实现 (User Interface)
- 遵循 Apple Human Interface Guidelines 搭建界面。
- 实现 macOS 状态栏 (Menu Bar) 应用入口。
- 构建 SwiftUI 偏好设置面板：
  - **General Tab**: 全局设置，以及当前启用哪个壁纸源的下拉框菜单。
  - **Sources Tab**: 壁纸源总览（启用/禁用、连接状态、是否已配置 Token、当前速率限制状态）。
  - **Wallhaven Tab**: Wallhaven 的 Token 输入区 + 专属标签/SFW 等高级过滤配置。
  - **Unsplash Tab**: Unsplash 的 Access Key 输入区 + 专属搜索参数配置。
- 实现桌面状态信息展示与手动刷新按钮。

### 阶段四：自动化队列与后台运行 (Automation)
- 实现定时器逻辑，依据**当前选中的壁纸源**及其设定的频率或全局频率触发拉取请求。
- 确保应用能够静默后台运行，不干扰用户正常工作流。

### 阶段五：异常处理与打磨完善 (Polish)
- 全面处理无网络、API 达限(Rate Limit)、图片下载失败及文件写入权限等异常。
- 增加日志记录系统，便于排查运行中的多源异构 API 问题。
- (可选) 增加资源清理机制，定期清理过期缓存的壁纸。

## 4. 凭证与多平台配置补充设计（重点）

- **凭证策略**：
  - 默认不内置任何平台 Token；首次使用某平台时，引导用户填写自己的 Token。
  - Token 仅本地保存到 Keychain，不写入日志、不进入崩溃上报、不提交到仓库。
  - 若 Token 缺失或失效，仅禁用对应 Provider，不影响其它 Provider 运行。

- **多平台差异化配置策略**：
  - 使用 `WallpaperSourceType` + 关联配置模型（枚举/协议）统一管理来源类型。
  - 每个平台维护独立配置结构和校验规则（例如 Wallhaven 有 purity/categories，Unsplash 有 query/collection/orientation）。
  - UI 层按“公共配置 + 平台专属配置”分组渲染，避免不同平台参数混杂。

- **设置页呈现建议**：
  - 左侧：`Sources` 列表（Wallhaven/Unsplash/后续扩展）。
  - 右侧：选中源的配置表单（顶部是 Token 状态卡，下面是该平台专属参数）。
  - 在列表中展示每个源的状态徽标：`未配置` / `可用` / `限流中` / `凭证失效`。

- **限流与回退策略**：
  - 当前源触发 rate limit 时，显示友好提示并进入冷却时间。
  - 若用户启用“自动回退”，可切换到下一个“已启用且凭证有效”的源继续拉图。

## 5. 后续方案审查需确认事项

> [!NOTE]  
> 目前方案已调整为**基于协议 (Protocol-Oriented) 结构设计**，以支持随时低成本接入新的壁纸服务商。UI 各个 Source 的独立 Tab 面板也做了初步规划。
> 如果该增强版的规划符合您的期望，我们将初始化 Xcode 工程，着手 `WallpaperProvider` 接口协议和第一批平台的实装。
