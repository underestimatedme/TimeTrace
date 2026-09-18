# 接口备忘 · Forge → Valley `/admin/timetrace/*`（Forge 侧提案，待后端 02- 拍板）

> 来自 Forge 运营后台会话（分支 `codex/timetrace-console`）。
> Forge 已按下述形状用 fixture 先行开发完成（页面、null 渲染、三级下钻、反馈写操作均已跑通）。
> 后端（`02-Valley-backend.md`）落地时请对照本备忘确认字段名与 **null 位置**；有出入以后端为准，但请回填本文件并通知 Forge / iOS。

信封（`makeValleyDataProvider` 依赖）：
- 列表 `{ "code":"OK", "data":{ "list":[...], "total":N } }`
- 单条 / 对象 `{ "code":"OK", "data":{...} }`
- 统一支持 `page` / `pageSize` / `orderBy` / `order` + 扁平化 filter 字段（`user_id` / `project_id` / `task_id` / 时间范围）

Forge 侧的 Refine 资源名 → 后端路径映射：
`timetrace-users→users`、`-projects→projects`、`-tasks→tasks`、`-plans→plans`、
`-runners→runners`、`-remote-jobs→remote-jobs`、`-reports→reports`、`-feedback→feedback`。
`dashboard` / `quota` 由页面直接 `http.get`，不作为 Refine 资源。

---

## 端点与字段（标 ⚠️ 的是 admin 层需 join / 需确认的字段）

### GET /admin/timetrace/dashboard  （对象）
```jsonc
{ "users":128, "active_projects":34, "running_plans":7, "quota_alerts":2,
  "trend":[ { "date":"2026-09-16", "human_seconds":10800, "ai_seconds":3600, "waiting_seconds":null } ] }
```
⚠️ `trend[].*_seconds` 每个都可能为 `null`（当日该轨道有 unknown 区间）。图表在 null 处断线。

### GET /admin/timetrace/users , /users/:id
行：`{ id, nickname, is_guest, identities_masked[], runner_count, created_at }`
详情追加：`runners: AdminRunner[]`
⚠️ `identities_masked` 必须脱敏（如 `"phone:+86138****8000"`）。⚠️ `runner_count` 为 join。

### GET /admin/timetrace/projects , /:id
`{ id, name, description, icon, color, status, created_at, updated_at }`
⚠️ + `user_id, user_nickname, task_count`（join）。

### GET /admin/timetrace/tasks , /:id
`{ id, project_id, goal_id|null, title, description, executor_type, ai_provider|null,
   collaboration_mode|null, status, priority, estimated_minutes, due_date|null,
   completed_at|null, result_summary|null, created_at, updated_at }`
⚠️ + `user_nickname`。null：`goal_id / ai_provider / collaboration_mode / due_date / completed_at / result_summary`。

### GET /admin/timetrace/plans , /:id
`{ id, task_id, revision, title, priority, status, criteria[], depends_on[],
   execution_policy{}, estimated_human_minutes, estimated_ai_minutes, work_weight, risk,
   created_at, updated_at }`
- `status` ∈ `draft|ready|running|awaiting_review|accepted|completed|failed|cancelled`；`awaiting_review` = 前端「结果待确认」。
- `criteria[]` = `{ id, text, done }`（验收条件勾选态）；`depends_on[]` = 前置 plan id 列表。
- ⚠️ **`provider`（所选 AI 工具）**：设计稿要求 Plan 展示所选工具，但 `plan_model.go` 无该列——请确认是加列、放进 `execution_policy`，还是取自 task。Forge 暂用 `provider|null`。⚠️ + `user_nickname`。

### GET /admin/timetrace/runners , /:id
行：`{ id, name, platform, client_version, status, last_seen_at|null, revoked_at|null, created_at, updated_at }`
详情（RunnerInventory）追加：`lease_healthy(bool), workspaces[]{id,name,default_branch,enabled,updated_at}, tools[]{id,provider,version,status,updated_at}`
⚠️ + `user_nickname`。null：`last_seen_at / revoked_at`。⚠️ `lease_healthy` 需从租约推导。

### GET /admin/timetrace/remote-jobs , /:id
行：`{ id, task_id, plan_id|null, runner_id, workspace_id, tool_profile_id, provider|null,
   status, revision, result_summary, created_at, updated_at }`
详情追加：`attempts[]{id,job_id,runner_id,lease_epoch,lease_expires_at,last_sequence,started_at,ended_at|null},
   events[]{seq,type,message,created_at}`
- ⚠️ **绝不返回 prompt 明文**（后端存 ciphertext）。⚠️ + `user_nickname`。null：`plan_id / provider / attempts[].ended_at`。

### GET /admin/timetrace/quota  （对象）
`{ observed_at, pools[]{ pool_id, provider, tier, availability, windows[]{ limit_id, window_mins, used_percent|null, reset_at|null, observed_at, source, confidence } } }`
- ⚠️ **`used_percent` / `reset_at` 为 null**（`quota_model.go` 本就是 `*float64` / `*time.Time`）——前端显示「未知」，不是 0%。
- ⚠️ `provider` + `tier`（四层级能力分层）：`tier` 命名请与 App 端对齐。是否需按 user 过滤？

### GET /admin/timetrace/reports  （+详情？）
`{ local_date, revision, status, coverage, human_seconds|null, ai_seconds|null, waiting_seconds|null,
   total_score|null, estimated_value_minor|null, actual_spend_minor|null, baseline_version, generated_at }`
⚠️ + `user_id, user_nickname`。null 契约（照 `report_model.go` MarshalJSON）：
- 三轨 `*_seconds` 有 unknown 区间 → null；`total_score` 覆盖不足 → null；两个 `*_minor` **恒 null**。
- ❓ 是否提供 `/reports/:id` + `breakdown`（phase facts 区间）供详情页三轨时间轴？列表主键 `(user, local_date, revision)` —— 按 user 过滤 + 默认取最新 revision？

### GET /admin/timetrace/feedback , PATCH /admin/timetrace/feedback/:id  （唯一写操作）
`{ id, user_nickname, category, content, status, note|null, created_at, updated_at }`
PATCH body `{ status?, note? }`。❓ `status` 合法流转值？Forge 暂用 `open|processing|resolved`。

---

## 需后端确认的 5 点（阻塞项已用 fixture 绕过，但最终要对齐）
1. 各 admin DTO 的最终字段名（尤其 `user_nickname` / `task_count` / `runner_count` 等 join 字段）。
2. 报告详情 + `breakdown` 是否提供；列表按 user 过滤 + 默认 revision 策略。
3. Quota 的 `provider` / `tier`（四层级）字段与命名；是否按 user 过滤。
4. Plan 的所选 AI 工具字段来源（新列 / execution_policy / task）。
5. 反馈 `status` 合法流转值集合。

## RBAC（accessControlProvider 已按此占位，待后端权限码）
`timetrace:<resource>:list` / `:view`；反馈写为 `timetrace:feedback:edit`。
