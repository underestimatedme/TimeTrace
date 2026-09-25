# 使用习惯记录（匿名使用统计）

自建，不接第三方 SDK。手机端 `UsageEvents`（`ios/KeJi/Analytics/UsageEvents.swift`）缓冲事件，
批量发到 Valley `POST /timetrace/api/v1/events`，落在 `tt_usage_events`。

## 开关与边界

- 「我的 → 数据与隐私 → 帮助改进刻迹（匿名使用统计）」，默认开启；关闭后立即停止记录并清空本机缓冲。
- 离线模式（`--offline` / `KEJI_OFFLINE=1`）一律不记录。
- 手机端对每个事件只保留白名单字段（见下表），字符串截到 64 个 Unicode 标量；任务标题、提示词、
  仓库路径、账号标识这类字段不在白名单里，传进来也会被丢掉。
- 缓冲：内存 + Application Support 下的 JSON 文件，最多 500 条（满了丢最旧的）。
  满 20 条、App 回到前台、进入后台时上报；网络失败保留下次再发，被服务端判为非法（4xx）的批次直接丢弃。

## 服务端契约（Valley `internal/apps/timetrace/usage_events.go`）

请求：

```json
{"app_version": "0.2.0 (2026092601)",
 "events": [{"name": "dispatch_started", "at": "2026-09-26T08:00:00.000Z",
             "props": {"tool": "codex", "scheduled": true, "source": "report"}}]}
```

- 需要登录会话（游客可以）；没有会话返回 401。
- 每次最多 100 条；事件名必须在字典里；每个事件最多 8 个属性，键匹配 `[a-z_]{1,32}`，
  值只能是字符串（≤ 64 字符）、有限数字或布尔。任何一条不合规 → **整批 422**，一条都不存（让客户端的 bug 暴露出来）。
- `at` 早于 30 天前或晚于 24 小时后的事件丢弃并计数；每个用户每个 UTC 自然日最多 2000 条，超出丢弃并计数。
  返回 `200 {"accepted": n, "dropped": m}`。
- 表 `tt_usage_events`：`id, user_id, name, props(jsonb), occurred_at, received_at, app_version`。
  随账号注销级联删除；游客登录合并时跟着迁到正式账号。
- 保留 30 天：写入路径上每个进程每小时最多清理一次 `received_at` 超过 30 天的行。

## 事件字典

| 事件 | 触发时机 | 属性 |
| --- | --- | --- |
| `app_open` | 进程启动 | — |
| `screen_view` | 主标签页切换（`today` / `projects` / `timeline` / `mine`）、AI 页（`ai_tools`）、报告（`report`）、Plan 详情（`plan_detail`） | `screen` |
| `dispatch_started` | 手机发起派发（Plan 详情、新建任务「保存并开始 / 安排时间」或报告页） | `tool`（codex / claude / …）、`scheduled`（是否定时）、`source`（plan / task_create / report） |
| `dispatch_succeeded` | 服务端接受派发 | 同上 |
| `dispatch_failed` | 派发请求失败 | 同上 + `error_code`（Valley 业务码，传输失败为负数） |
| `schedule_created` | 定时派发成功（带 `not_before`） | `tool`、`source` |
| `pairing_step` | 绑定电脑的每一步 | `step`（inspect / approve / scan / link）、`result`（ok / error / cancelled / received） |
| `plan_accepted` | Plan 验收成功 | `criteria`（验收项数） |
| `report_opened` | 打开报告 | `scope`（all / project） |
| `report_action` | 报告页上的操作 | `action`（review / schedule / create） |
| `quota_viewed` | AI 页加载完额度 | `pools`（额度池个数）、`source`（ai_tools） |

新增事件或属性时三处一起改：Valley `usageEventNames`、手机端 `UsageEventName` + `UsageSanitizer.allowedKeys`、这张表；
隐私问卷见 `keji-ios-release-checklist.md`（产品交互）。

## 漏斗查询示例（PostgreSQL）

以「首个 `app_open`」近似安装时间。以下都只看 30 天内的数据（更早的已被清理）。

### 1. 配对完成率

发起配对（扫码或打开链接或手动核对）→ 核对成功 → 批准成功，按用户去重：

```sql
WITH steps AS (
  SELECT user_id,
         bool_or(props->>'step' IN ('scan', 'link', 'inspect'))                    AS started,
         bool_or(props->>'step' = 'inspect' AND props->>'result' = 'ok')           AS inspected,
         bool_or(props->>'step' = 'approve' AND props->>'result' = 'ok')           AS approved
  FROM tt_usage_events
  WHERE name = 'pairing_step' AND occurred_at > now() - interval '30 days'
  GROUP BY user_id
)
SELECT count(*) FILTER (WHERE started)                                AS started_users,
       count(*) FILTER (WHERE inspected)                              AS inspected_users,
       count(*) FILTER (WHERE approved)                               AS approved_users,
       round(100.0 * count(*) FILTER (WHERE approved)
             / nullif(count(*) FILTER (WHERE started), 0), 1)         AS completion_pct
FROM steps;
```

### 2. 安装后多久第一次派发成功

```sql
WITH firsts AS (
  SELECT user_id,
         min(occurred_at) FILTER (WHERE name = 'app_open')           AS installed_at,
         min(occurred_at) FILTER (WHERE name = 'dispatch_succeeded') AS first_dispatch_at
  FROM tt_usage_events
  GROUP BY user_id
)
SELECT count(*)                                                         AS users,
       count(first_dispatch_at)                                         AS dispatched_users,
       percentile_cont(0.5) WITHIN GROUP (
         ORDER BY extract(epoch FROM first_dispatch_at - installed_at) / 3600
       ) FILTER (WHERE first_dispatch_at IS NOT NULL)                   AS median_hours_to_first_dispatch
FROM firsts
WHERE installed_at IS NOT NULL;
```

### 3. 派发成功率（按天、工具、入口）

```sql
SELECT date_trunc('day', occurred_at)                                   AS day,
       props->>'tool'                                                   AS tool,
       props->>'source'                                                 AS source,
       count(*) FILTER (WHERE name = 'dispatch_started')                AS started,
       count(*) FILTER (WHERE name = 'dispatch_succeeded')              AS succeeded,
       count(*) FILTER (WHERE name = 'dispatch_failed')                 AS failed,
       round(100.0 * count(*) FILTER (WHERE name = 'dispatch_succeeded')
             / nullif(count(*) FILTER (WHERE name = 'dispatch_started'), 0), 1) AS success_pct
FROM tt_usage_events
WHERE name IN ('dispatch_started', 'dispatch_succeeded', 'dispatch_failed')
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 4 DESC;
```

### 4. 报告打开率（打开过 App 的用户里，当天打开报告的比例）

```sql
SELECT date_trunc('day', occurred_at)                                        AS day,
       count(DISTINCT user_id) FILTER (WHERE name = 'app_open')              AS active_users,
       count(DISTINCT user_id) FILTER (WHERE name = 'report_opened')         AS report_users,
       round(100.0 * count(DISTINCT user_id) FILTER (WHERE name = 'report_opened')
             / nullif(count(DISTINCT user_id) FILTER (WHERE name = 'app_open'), 0), 1) AS report_open_pct,
       count(*) FILTER (WHERE name = 'report_action' AND props->>'action' = 'schedule') AS schedules_from_report
FROM tt_usage_events
WHERE name IN ('app_open', 'report_opened', 'report_action')
GROUP BY 1
ORDER BY 1 DESC;
```
