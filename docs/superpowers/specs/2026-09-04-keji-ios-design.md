# 刻迹（KeJi / TimeTrace）iOS 版 + Valley 后端模块 设计规格

日期：2026-09-04
状态：已按自主执行模式采纳（用户要求端到端完成：代码、提交、GitHub Actions 发布到 SealOS、验证）。

## 1. 目标

把 `design/`（React + Vite 原型，暗色优先、四套主题、15 个页面）忠实实现为原生 iOS App，
并在 `../Valley` 中新增 `timetrace` 业务模块作为其后端：账号（游客 + 验证码升级）、
全量状态引导（bootstrap）、批量变更同步（sync）。后端沿用 Valley 现有 GitHub Actions
（test → GHCR → SealOS）发布，与 ieltsbuddy / continenttrail 共用同一 Deployment。

不在范围：真实 AI 工具接入（原型即"模拟连接"）、推送通知、TestFlight 签名分发、
多设备冲突合并以外的复杂 CRDT。

## 2. 总体架构

```
iOS (SwiftUI, iOS 17+)                      Valley (Go / Gin / GORM / Postgres)
┌──────────────────────────────┐            ┌──────────────────────────────────┐
│ Features/* (15 个页面)        │            │ internal/apps/timetrace          │
│   ↕ 观察                      │            │   app.go        路由 + envelope   │
│ AppStore (@Observable)        │  HTTPS     │   model.go      tt_* 表           │
│   reducers = zustand 语义移植  │◀────────▶ │   repository.go 会话/同步/LWW     │
│ Persistence (JSON 文件)        │ /timetrace │   admin: GET /admin/timetrace/stats│
│ SyncEngine (脏标记→POST /sync) │  /api/v1   │ 复用: registry.Platform, SMS,     │
│ APIClient + Keychain 会话      │            │      RateLimit, RequestID        │
└──────────────────────────────┘            └──────────────────────────────────┘
```

**离线优先**：本地状态是唯一真相源（与原型的 zustand + localStorage 一致）。
每次 mutation 立即写本地并标记脏实体；SyncEngine 去抖 2s 后 `POST /sync` 推送脏实体
与删除列表，服务端按 `updated_at` 最后写入者胜（LWW）合并后返回完整快照，客户端用快照
覆盖本地（保留仍在飞行中的脏实体）。冷启动 / 回前台时 `GET /bootstrap` 拉取。

**身份**：首次完成 Onboarding 时自动 `POST /auth/guest` 建立游客会话（Keychain 保存
access/refresh）。"我的 → 账号" 可用手机号/邮箱验证码把游客升级为正式账号（合并数据），
复刻 continenttrail 的会话族（hash 存储、15 分钟 access / 30 天 refresh、复用检测）。

## 3. 后端模块 `internal/apps/timetrace`

- 注册名 `timetrace`，数据库 `valley_timetrace`（`APP_DSN_TIMETRACE`），表前缀 `tt_`。
- 实现 `registry.App` + `registry.PublicRouter`；`RegisterRoutes` 留空（避免与 pub 组重复注册）。
  对外路径：`/timetrace/api/v1/*`（iOS 使用）与 `/api/timetrace/v1/*`。
- 响应包裹沿用 continenttrail：`{"code":0,"message":"ok","data":...,"request_id":"..."}`；
  错误 `{"code":40100,"message":"..."}`，HTTP 状态与整数码同 continenttrail 语义。
- 请求解码：`DisallowUnknownFields` 不启用（同步负载会随版本增长，未知字段忽略），
  但限制 body 4 MiB，单文档。
- 时间统一 RFC3339（UTC 或带时区）字符串；ID 为客户端生成的 ≤32 字符串（UUID 去连字符）。

### 3.1 路由

| 方法 | 路径 | 鉴权 | 说明 |
|---|---|---|---|
| GET | `/content/version` | 无 | `{"service":"timetrace","version":1}`，作为部署冒烟 |
| POST | `/auth/guest` | 无 | 201 `Session` |
| POST | `/auth/send-code` | 无 | `{identifier}` → `{expires_in,retry_after}`；非生产固定码 `246810` |
| POST | `/auth/login` | 可带 bearer | `{identifier,code}` → `Session`；若 bearer 是游客则把游客数据并入该身份 |
| POST | `/auth/refresh` | 无 | `{refresh_token}` → `Session` |
| POST | `/auth/logout` | bearer | `{"revoked":true}` |
| DELETE | `/account` | bearer | 删除用户及全部数据 `{"deleted":true}` |
| GET | `/bootstrap` | bearer | `Bootstrap{user, state, server_time}` |
| POST | `/sync` | bearer | `SyncRequest` → `Bootstrap`（合并后的全量快照） |
| GET | `/admin/timetrace/stats` | 网关 admin | 用户/任务/会话计数 |

`Session = {access_token, refresh_token, expires_in}`；
`user = {id, nickname, is_guest, account_label}`。

### 3.2 状态快照 `state`（snake_case）

```
projects[]      {id, name, description, icon, color, status, created_at, updated_at}
goals[]         {id, project_id, title, description, target_date, progress, status, updated_at}
tasks[]         {id, project_id, goal_id?, title, description, executor_type, ai_provider?,
                 collaboration_mode?, status, priority, estimated_minutes, due_date?,
                 scheduled_start?, scheduled_end?, created_at, completed_at?, result_summary?, updated_at}
time_sessions[] {id, task_id, type, executor, started_at, ended_at?, duration_seconds,
                 source, confidence, note?, updated_at}
ai_executions[] {id, task_id, provider, model, status, started_at, ended_at?, active_seconds,
                 elapsed_seconds, waiting_human_seconds, token_input, token_output,
                 estimated_cost, tool_call_count, files_changed, result_summary?,
                 error_message?, logs[{time,message}], current_step?, updated_at}
experiments[]   {id, title, description, start_date, duration_days, status,
                 before_metric, after_metric?, effective?, updated_at}
settings        {name, weekly_time_goal_hours, work_start_hour, work_end_hour,
                 default_focus_minutes, streak_days, theme, updated_at}
ai_tools[]      {provider, name, connected, last_sync?}
active_focus?   {task_id, started_at, accumulated_seconds}
```

枚举值与 `design/src/types/index.ts` 完全一致（字符串，varchar(24) + index 存储）。

### 3.3 `POST /sync`

```
SyncRequest {
  client_time: RFC3339,
  upserts:  { projects[], goals[], tasks[], time_sessions[], ai_executions[], experiments[] },
  deletes:  { projects[], goals[], tasks[], time_sessions[], ai_executions[], experiments[] }  // id 列表
  settings?: Settings,
  active_focus?: ActiveFocus | null,   // 显式 null = 清除；缺省 = 不变
  ai_tools?: AITool[]
}
```

合并规则：每条 upsert 与库中同 (user_id, id) 比较 `updated_at`，仅当新 ≥ 旧才写；
删除记录到 `tt_tombstones(user_id, entity, id, deleted_at)`，被墓碑覆盖且 `updated_at`
早于墓碑的 upsert 忽略；settings / active_focus / ai_tools 存于 `tt_profiles` 一行（JSONB）。
整个 sync 在一个事务内；返回合并后的完整 `Bootstrap`。

### 3.4 表

`tt_users, tt_identities, tt_session_families, tt_verification_challenges`（照搬 continenttrail 语义），
`tt_profiles(user_id PK, settings jsonb, active_focus jsonb, ai_tools jsonb, updated_at)`，
`tt_projects, tt_goals, tt_tasks, tt_time_sessions, tt_ai_executions, tt_experiments`
（复合主键 `(user_id, id)`，所有用户 FK `OnDelete:CASCADE`，`updated_at` 索引），
`tt_tombstones`。`logs` 用 `datatypes.JSON`。

### 3.5 测试

- 纯单元：LWW 合并、墓碑规则、标识符归一化。
- 集成（`APP_DSN_TIMETRACE_TEST`，缺省跳过）：guest → sync 推送 → bootstrap 读回 →
  删除 → 再 sync 旧版本被忽略 → 验证码登录合并游客 → 刷新令牌复用被拒 → 删除账号级联。
- `go vet ./... && go test ./...` 必须通过。

## 4. 部署（Valley）

- `cmd/server/main.go` 注册 `timetrace.New()`。
- `deploy/sealos/ieltsbuddy.yaml`：`VALLEY_ENABLED_APPS` 追加 `timetrace`；Ingress
  `apis.atlaspaces.com` 新增 path `/timetrace/api/v1`。
- `.github/workflows/publish.yml`：
  - 触发：`push` 增加 `branches: [main, 'release/**']`；`deploy-sealos` 门禁增加
    `startsWith(github.ref, 'refs/heads/release/')`（Valley 已有 `release/*` 惯例；本机无
    GitHub token 无法 `workflow_dispatch`）。
  - 密钥：新增 `APP_DSN_TIMETRACE`（若 secret 缺省，从 `APP_DSN_IELTSBUDDY` 替换库名派生，
    与 continenttrail 相同）。
  - 数据库引导 Pod：追加 `CREATE DATABASE valley_timetrace OWNER valley_ieltsbuddy`。
  - 冒烟：追加 `https://apis.atlaspaces.com/timetrace/api/v1/content/version`。
- 分支：`release/timetrace`，从 `codex/continenttrail-backend`（当前最新、已含部署修复）拉出。

## 5. iOS App（`ios/`，TimeTrace 仓库）

- 工具：Xcode 26.5，`xcodegen`（`project.yml`），SwiftUI，Swift Charts，deployment target iOS 17.0，
  Bundle ID `com.atlaspaces.keji`，显示名"刻迹"。零第三方依赖。
- 目录：
  ```
  ios/project.yml
  ios/KeJi/App            KeJiApp.swift, RootView (Splash→Onboarding→Tabs), AppRouter
  ios/KeJi/Models         Domain types（与 types/index.ts 一一对应，Codable, snake_case）
  ios/KeJi/Store          AppStore（@Observable，reducers 移植 useStore.ts）、SampleData（移植 mockData.ts）
  ios/KeJi/Stats          Stats.swift（移植 stats.ts）、Format.swift（移植 format.ts）
  ios/KeJi/Persistence    StateStore（JSON 文件，Application Support）
  ios/KeJi/Networking     APIClient、Endpoints、Session、Keychain、SyncEngine
  ios/KeJi/Theme          Theme（4 套色板）、ThemeEnvironment
  ios/KeJi/Components     Card, Badge(Status/Executor/Priority), Button styles, MetricCard,
                          SectionTitle, ProgressBar, EmptyState, SubPageScaffold, TaskCard
  ios/KeJi/Features       Splash, Onboarding, Today, Tasks, TaskCreate, TaskDetail, Focus,
                          AIExecution, Timeline, Insights, Profile, Projects(+Detail, GoalDetail),
                          AITools, Appearance, Account
  ios/KeJiTests           StatsTests, StoreReducerTests, SyncMergeTests, APIDecodingTests
  ios/.github (根仓库)     .github/workflows/ios.yml：xcodegen + build + test（macos-15）
  ```
- 主题：`Theme` 提供与 `index.css` 完全相同的 16 个色值；`ThemeName` 存于 settings 并同步。
- 视觉：圆角 16/12、边框 1px、字体 SF Pro + mono 数字、暗色背景，按原型逐页复刻。
- 底部 Tab：今日 / 任务 / 时间流 / 洞察 / 我的（SF Symbols: calendar, checklist,
  arrow.triangle.branch, chart.bar, person）。
- AI 执行模拟：与原型一致（每秒 tick，30s 一步，>120s 且整分完成→ waiting_human）。
- 调试入口：启动参数 `--sample-data`（直接载入示例数据并跳过 Onboarding）、
  `--screen <route>`（直达指定页面），供自动截图验证使用。
- API Base URL：`KEJI_API_BASE_URL`（Info.plist，默认
  `https://apis.atlaspaces.com/timetrace/api/v1`），可用同名环境变量覆盖。

## 6. 验证

1. 后端：`go vet`、`go test`（含 Postgres 集成测试，本机 PG17）、本地起服务 curl 走通
   guest → sync → bootstrap。
2. 发布：推送 `release/timetrace` 触发 Actions；本机轮询
   `https://apis.atlaspaces.com/timetrace/api/v1/content/version` 直至 200，并用 curl 完成
   guest/sync/bootstrap 生产冒烟。
3. iOS：`xcodebuild test`（模拟器 iPhone 17 Pro）；安装到已启动模拟器，按 `--screen`
   逐页截图；把截图汇总为一页 Artifact 供查看。
4. 端到端：模拟器 App 指向生产后端，创建任务→开始专注→完成，再用 curl bootstrap
   确认服务端已有该任务。

## 7. 实施顺序

1. 后端模块 + 测试 + 部署改动（Valley，`release/timetrace`）。
2. iOS：Models/Store/Stats/Theme/Components → 各页面 → Networking/Sync → Tests → 调试入口。
3. 提交推送两仓库分支；后端触发发布；等待并冒烟。
4. iOS 构建、测试、截图、端到端验证；产出报告。
