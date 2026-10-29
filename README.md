# beauty_wall（macOS 菜单栏自动壁纸 - MVP）

`beauty_wall` 是一个 macOS 菜单栏应用，用于从壁纸来源平台拉取图片并设置为系统壁纸。  
当前阶段以 **MVP 基础功能** 为主：先把“可用、可配、可稳定切换”做扎实。

## 当前已实现

- 菜单栏后台运行（`LSUIElement = YES`，不主动弹主窗口）
- 来源切换（基于预设，激活项互斥单选）
- 手动刷新壁纸
- 自动定时刷新（支持 `按间隔` 与 `按时间` 两种模式）
- 分辨率适配（自动主屏检测 / 手动预设 / 仅4K+）
- 设置页三分区：`通用 / 凭证 / 来源`
- 设置页 `凭证` 新增 `Pro 激活` 卡片：
  - 软件内 `购买 Pro`（跳转爱发电）
  - 订单号查询取码（`/orders/:orderNo`）
  - 输入激活码并调用 `/activate`
  - 手动校验授权（`/validate`）+ 启动自动校验
  - 显示激活时间与最近校验时间
- Pro 门控：
  - 未激活 Pro 时，BYOK 私有图源（Wallhaven / Unsplash）不可设为生效来源
  - 未激活 Pro 时，高级参数区域只读
- 已接入来源：
  - `Wallhaven`
  - `Unsplash`
- 平台参数分层：
  - 常用参数
  - 高级参数
- 数据持久化：
  - 凭证：本地配置（临时方案，后续回归 Keychain）
  - 非敏感配置：UserDefaults

## MVP 范围外（暂未做）

- 自动刷新高级策略（如工作日规则、节假日例外）
- 云同步
- 复杂重试/回退策略
- 开机自启与缓存治理

## 运行方式

### 1) 用 Xcode 运行

1. 打开 `/Users/wang/Space/beauty_wall/beauty_wall.xcodeproj`
2. 选择 scheme：`beauty_wall`
3. `Run` 启动后，在菜单栏图标中操作

### 2) 命令行构建（可选）

```bash
xcodebuild -project beauty_wall.xcodeproj -scheme beauty_wall -configuration Debug -sdk macosx build
```

## 使用步骤（首次）

1. 点击菜单栏图标 -> `设置页`
2. 在 `凭证` 填写平台密钥
   - Wallhaven：`API Key`
   - Unsplash：当前 MVP 仅使用 `Access Key`
3. 点击 `保存凭证`
4. 在 `通用` 选择当前来源
5. 在 `通用` 选择刷新策略：
   - 按间隔：常用项 + 自定义
   - 按时间：每天固定时刻（如 08:00）
6. 可在菜单栏手动点击 `手动刷新壁纸`
7. Pro 最小闭环：
   - 在 `凭证 -> Pro 激活` 点击购买
   - 支付后填写订单号查询并自动填入激活码
   - 点击 `激活 Pro`

## 配置与存储说明

### UserDefaults（当前配置存储）

- `app.config.sourcePresets`
- `app.config.activeSourceId`
- `app.config.selectedSource`（兼容旧版本迁移）
- `app.config.autoRefreshMode`
- `app.config.autoRefreshInterval`
- `app.config.enableAutoResolutionFit`
- `app.config.manualResolutionPreset`
- `app.config.customManualResolution`
- `app.config.prefer4KPlus`
- `app.config.wallhaven`（兼容旧版本迁移）
- `app.config.unsplash`（兼容旧版本迁移）
- `app.credentials.wallhaven.apiKey.plain`（临时）
- `app.credentials.unsplash.accessKey.plain`（临时）
- `app.pro.licenseKey`
- `app.pro.isActivated`
- `app.pro.activatedAt`
- `app.pro.deviceId`
- `app.pro.licenseServiceBaseURL`

## 项目结构

```text
beauty_wall/
├── beauty_wallApp.swift        # App 入口（MenuBarExtra + Settings）
├── MenuBarView.swift           # 菜单栏菜单
├── SettingsView.swift          # 设置页
├── Core/
│   ├── AppSettingsStore.swift  # 配置中心（当前为 UserDefaults 临时方案）
│   ├── KeychainStore.swift
│   ├── WallpaperRefreshController.swift
│   └── WallpaperProviderFactory.swift
├── Models/
│   └── AppConfig.swift         # 来源与平台配置模型
└── Providers/
    ├── WallhavenProvider.swift
    └── UnsplashProvider.swift
```

## 任务与规划文档

- 当前执行清单：`/Users/wang/Space/beauty_wall/todo.md`
- 任务拆解：`/Users/wang/Space/beauty_wall/task.md`
- 实施计划：`/Users/wang/Space/beauty_wall/implementation_plan.md`
- UI 规范：`/Users/wang/Space/beauty_wall/UI_GUIDELINES.md`

## 商业版后端（全容器化，本地可跑）

已新增目录：`/Users/wang/Space/beauty_wall/backend`

### 一键启动

```bash
docker compose up -d --build
```

### 服务端口

- License API: `http://127.0.0.1:8080`
- PostgreSQL: `127.0.0.1:55432`（容器内仍为 `5432`）
- Redis: 仅容器内可见（未暴露宿主机端口）

### 关键环境变量

- `PROJECT_CODE`：当前服务所属项目（默认 `beauty_wall`）
- `PROJECT_A_FORWARD_URL`：`project_a` 转发目标地址
- `AFDIAN_WEBHOOK_TOKEN`：爱发电 Webhook 鉴权（可选，建议生产开启）
- `FORWARD_AUTH_TOKEN`：转发到其他项目时附带的服务间鉴权 token（可选）
- `ADMIN_API_TOKEN`：管理接口 token（可选，建议生产开启）

### 核心接口（V1）

- `GET /health`
- `POST /seed/dev-license`（本地生成测试码）
- `POST /admin/plan-mappings/seed-defaults`（导入默认 `plan_id` 映射）
- `GET /admin/plan-mappings`
- `POST /admin/plan-mappings`
- `PATCH /admin/plan-mappings/:planId`
- `POST /webhooks/afdian`（爱发电支付回调）
- `POST /admin/license/generate`（后台手动发码）
- `POST /admin/orders/:orderNo/issue-license`（手动给订单补发码）
- `GET /admin/orders`
- `GET /admin/licenses`
- `POST /activate`
- `POST /validate`
- `POST /unbind`
- `GET /license/status?licenseKey=...`
- `GET /orders/:orderNo`

### 本地联调示例

```bash
curl -sS http://127.0.0.1:8080/health
curl -sS -X POST http://127.0.0.1:8080/admin/plan-mappings/seed-defaults
curl -sS -X POST http://127.0.0.1:8080/seed/dev-license
curl -sS -X POST http://127.0.0.1:8080/activate \
  -H 'content-type: application/json' \
  -d '{"licenseKey":"BW-PRO-DEV-0001","deviceId":"device-mac-a","deviceName":"Mac A"}'
```

### 爱发电回调联调示例

```bash
curl -sS -X POST http://127.0.0.1:8080/webhooks/afdian \
  -H 'content-type: application/json' \
  -d '{"orderNo":"AFD-ORDER-1001","plan_id":"8d5707fa16e211f188e552540025c377","status":"paid","amount":"19.90","currency":"CNY","user_id":"u_123","plan_title":"Pro 月付"}'
```

### 管理接口（最小后台能力）

```bash
# 导入默认 plan_id 映射
curl -sS -X POST http://127.0.0.1:8080/admin/plan-mappings/seed-defaults

# 查看订单列表
curl -sS 'http://127.0.0.1:8080/admin/orders?limit=20'

# 查看 License 列表
curl -sS 'http://127.0.0.1:8080/admin/licenses?limit=20'
```

## 安全提示

- 请使用用户自己的平台密钥，不要在代码中硬编码。
- 不要把真实密钥提交到 Git 仓库或截图外发。
- 若密钥已泄露，请在平台后台立即轮换。
