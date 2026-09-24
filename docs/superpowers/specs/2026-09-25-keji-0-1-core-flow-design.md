# 刻迹 0.1 · 核心流程跑通 — 设计

日期：2026-09-25 · 状态：待用户审阅 · 范围：iOS（`ios/`）、CLI Runner（`cli/`）、Valley 后端（`../Valley/internal/apps/timetrace`）

## 1. 目标

0.1 的定义只有一条：**用户用自己的 iPhone 和 Mac，把下面三条流程走通。**

1. 手机与 Mac 上的 `keji agent` 完成配对；手机能看到 Mac 上 Codex 与 Claude Code 的**套餐等级、用量、重置时刻**。
2. 手机下发一条指令，指定 Mac 上的某个工具执行，并在手机上看到执行状态与结果。
3. 手机为一条指令**手动指定一个执行时间**，到点后由 Mac 执行。

保留现有界面（项目 / 任务 / 时间线 / 报告 / Plan），不砍、不藏；0.1 的验收只看上述三条。

### 非目标

- Cursor、Gemini 的任何支持（0.2 再议）。
- 把 Runner 做成 Claude Code / Codex / Cursor 内部的插件；电脑端继续是独立守护进程 `keji agent`。
- App 内解绑 Runner；仍按现有提示在电脑上退出。
- 自动取「额度重置时刻」作为执行时间；0.1 时间一律由用户手动选。
- 唤醒睡眠中的 Mac；文档说明用 `pmset` / `caffeinate`。
- 手机端实时日志流；只回传结果摘要与输出尾巴。
- 推送通知客户端。

## 2. 现状与根因（2026-09-24 代码勘查）

三条流程的骨架都已实现，但被下列缺陷卡死，真机上一条也走不通：

| # | 缺陷 | 位置 | 后果 |
|---|---|---|---|
| R1 | Runner 上报的额度样本从不标记为「权威」（`_default_pool_binding` 返回二元组，`authoritative` 恒为 false） | `cli/keji/agent.py:20-22, 431-434` | 后端把整个池降级为 `unknown`，手机永远显示「待核验」 |
| R2 | 注册工具 id 为 `<provider>-default`，上报样本却用 `<provider>-personal` | `cli/keji/cli.py:144-148` vs `cli/keji/agent.py:20-22` | 派发闸门找不到对应池，永远读到 `unknown` |
| R3 | 闸门把 `unknown` 视为禁止，探测放行又要求样本权威且已过重置 | `Valley plans.go:825-832`, `remote.go:712-748`, `quota.go:163-211` | 派下去的任务一直排队，7 天后过期 |
| R4 | 批准 Runner 要求手机会话「10 分钟内登录过」，而 token 刷新不续 `authenticated_at` | `Valley remote.go:154`, `repository.go:203-249, 386` | 登录超过 10 分钟后配对一律 401 |
| R5 | Claude Code 无主动读额度通道；成功运行的限流样本被丢弃；`--once` 不上报 | `cli/keji/adapters/claude.py:131`, `agent.py:348-351, 394-399, 458-461` | Claude 额度基本为空 |
| R6 | 套餐等级完全没采集 | `cli/keji/models.py:32-40`, `quota.py:121-141` | 手机无法显示套餐 |
| R7 | Runner `status=online` 只在启动时写一次，从不写 offline | `Valley remote.go:209, 418` | 关机的 Mac 在手机上永远在线 |
| R8 | 手机端窗口 scope 映射漏掉 `seven_day` / `secondary` | `ios/.../QuotaPresentation.swift:32-39, 60-69` | Claude 7 天窗、Codex 周窗不显示 |
| R9 | 没有任何「到某时刻执行」的字段与逻辑；「保存并安排时间」按钮只是跳转 | `TaskCreateView.swift:132, 185-187`；后端无 `not_before` | 流程 3 不存在 |
| R10 | 手机上看到的「Codex 80% / Claude 待核验」是 `--sample-data` 夹具 | `ios/.../SampleData.swift:19-34` | 造成「有数据」的错觉 |

## 3. 方案取舍

- **A（选定）**：让真实数据流起来，并把闸门改为「只拦已耗尽」。零付费由 Runner 启动前的账单校验单独保证（`cli/keji/billing.py`），额度未知时最坏结果是跑到限流后进入等待，正好落回现有续跑逻辑。改动横跨三端但每处都小。
- B：只修 R1/R2，闸门不动。任何一次样本缺失都会让派发重新卡死；Claude 长期 `unknown`。否决。
- C：手机直连 Mac 绕开 Valley。重构量大，丢掉加密入库、租约、断点续跑。否决。

## 4. 设计

### 4.1 配对与在线状态

配对流程不变：Mac `keji cloud login` 打印 8 位码；手机「你的 AI」页输码 → 检查 → 批准；Mac 换取 Runner 令牌。

改动：

1. **删除 10 分钟规则（R4）。** `recentFormalUser` 只保留「非游客」检查，不再比较 `authenticated_at`。补测试：登录 1 小时后仍可 inspect / approve。
2. **手机错误可读。** 未登录 → 直接引导到账号页；后端为「码不存在 / 已过期 / 已使用 / 无权限」返回稳定错误码，iOS 映射为中文提示，不再展示原始错误串。
3. **在线状态改为心跳判定（R7）。** Runner 的领活轮询（`POST /runner/jobs/claim`，每 30 秒）即心跳；后端删除持久化的 `status` 字段语义，`GET /runners` 按 `last_seen_at` 是否在 2 分钟内实时计算 `online`，与派发闸门的 `runnerLivenessTTL` 同一口径。iOS 不改字段名，只改数据来源。
4. **配对成功后立即上报。** CLI 在 `cloud login` 拿到 Runner 令牌后，立刻推送工具清单并采集上报一次额度，手机批准后几秒内可见。

### 4.2 额度与套餐采集

**来源**

| | Codex | Claude Code |
|---|---|---|
| 套餐等级 | `~/.codex/auth.json` 中 ID token 的 plan 类型声明（plus / pro / team …） | `~/.claude/.credentials.json` 中 `claudeAiOauth.subscriptionType`（pro / max …） |
| 用量与重置 | 现有 `codex app-server` `account/rateLimits/read`（5 小时窗 + 周窗） | 用同一凭据文件里的 OAuth 访问令牌调用 Claude Code `/usage` 命令所用的用量接口，得到 `five_hour` / `seven_day` 的利用率与 `resets_at` |

**风险与退路**：Claude 用量接口未在用户机器上验证过。实施第一步即在用户 Mac 上做一次探测（记录请求形态与响应字段）。若不可用，退路是把 `keji statusline` 已采到本地 SQLite 的 Claude 样本上传，并把成功运行中出现的 `rate_limit_event` 样本也上报（不再只在被限流时上报）。两条路都保证 Claude 不是空白。

**Runner 端**

1. 修 R1：直接读取（Codex app-server、Claude 用量接口）的样本一律 `pool_authoritative=true, confidence=exact`。
2. 修 R2：上报 `profile_id` 与注册 `tools[].id` 一致，统一为 `<provider>-default`。
3. 上报时机：配对成功后；`agent run` 启动时；空闲时每 5 分钟；每个任务结束后；被限流时；`--once` 结束前。
4. 修 R6：工具清单增加 `plan_tier`（字符串，来源原文，如 `max`、`plus`），随 `UpdateRunnerInventory` 上报，不随样本。

**后端**

- `runner_tools` 增列 `plan_tier`；`GET /runners` 的 `tools[]` 与 `GET /quota` 的 `pools[]` 一并返回。
- 可用性三态保留：`available` / `exhausted` / `unknown`。`exhausted` 的定义收窄为「存在权威样本 `used_percent >= 100` 且其 `reset_at > now`」；其余为 `available` 或 `unknown`。

**手机「你的 AI」页**

- 每个工具一张卡：工具名、套餐等级、每个窗口的剩余百分比、**绝对重置时刻**（「周三 14:00 重置」，同时保留相对时间）、样本采集距今时间。
- 修 R8：scope 映射补 `seven_day`、`secondary`；窗口标识改为 `(limit_id, scope, kind, window_mins)`，与服务端一致。
- 夹具数据只在 `--sample-data` 下出现（R10 本身不改，只在文档与验收里明确）。

### 4.3 派发与定时执行

**派发**

1. **闸门只拦 `exhausted`（R3）。** `evaluateExecutionEligibility` 仅在 `exhausted` 时加 `quota_exhausted` 原因；`unknown` 不再阻塞；`reserveQuotaProbe` 保留但只用于 `exhausted` 且 `reset_at` 已过的探测放行。零付费校验（`billing_unverified`）不变。
2. 电脑、工具选择器的数据来源改为 4.1 的心跳在线与随心跳刷新的工具清单：CLI 每次 claim 若发现工具登录状态变化即重推清单。
3. **输出尾巴。** 任务终态事件增加 `output_tail`（UTF-8，最多 8 KB，取日志末尾）；后端入库并随 `GET /remote-jobs/:id` 返回；iOS 执行记录里可展开查看。`result_summary` 1000 字上限不变。
4. 派发入口不变：Plan 详情「派发执行」；新建任务「AI 来做」→「保存并开始」。

**定时执行（R9）**

1. `POST /remote-jobs` 增加可选 `not_before`（RFC 3339，服务端要求 `> now`，上限 30 天）。
2. claim 查询排除 `not_before > now` 的任务；任务状态仍为 `queued`，`GET` 返回 `not_before`，iOS 据此显示「已安排 · 9月27日 14:00」。到点后自然被领取，走 4.3 同一闸门。
3. iOS 派发面板（`PlanDispatchSheet` 与 TaskCreate 的派发段）增加「执行时间」：默认「立即」，可切到日期时间选择器。取消沿用现有 `commands` 取消；改时间 = 取消后重派。
4. 「保存并安排时间」按钮改为打开同一派发面板并默认展开时间选择，不再是空跳转。
5. Mac 睡眠时任务留在队列，唤醒后执行；`docs/remote-runner-operations.md` 增加保持唤醒的说明。

### 4.4 数据契约变更汇总

| 接口 / 表 | 变更 |
|---|---|
| `POST /device-authorizations/approve`、`/inspect` | 去掉 10 分钟限制；错误码 `code_not_found` / `code_expired` / `code_used` / `forbidden_guest` |
| `GET /runners` | `online` 由 `last_seen_at` 实时计算；`tools[].plan_tier` |
| 工具清单上报接口（`UpdateRunnerInventory`，现有路由不改） | `tools[].plan_tier` |
| `POST /runner/quota/samples` | 无字段变更；语义上直接读取的样本 `pool_authoritative=true` |
| `GET /quota` | `pools[].plan_tier`；`exhausted` 定义收窄 |
| `POST /remote-jobs` | 可选 `not_before` |
| `GET /remote-jobs/:id` | `not_before`、`output_tail` |
| `POST /runner/attempts/:id/events` | 终态事件可带 `output_tail` |
| `remote_jobs` 表 | 增列 `not_before timestamptz null`、`output_tail text null` |
| `runner_tools` 表 | 增列 `plan_tier text null` |

### 4.5 错误处理

- 配对：所有失败在手机上都有中文一句话 + 下一步动作（去登录 / 让电脑重出码）。
- 额度采集失败：不上报假样本；该工具卡片显示「未知 · 上次成功采集 X 前」，派发不受阻。
- Claude 令牌过期：读取失败即跳过本轮，等 Claude Code 自己刷新；不主动刷新令牌。
- 心跳中断：手机 2 分钟后显示离线；派发面板隐藏该电脑；已排队任务不受影响，电脑回来后继续领。
- `not_before` 非法（过去时刻 / 超 30 天）：服务端 400，手机在选择器上直接拦截。

## 5. 测试

**先写测试再改代码。**

- **CLI（pytest）**：套餐等级解析（Codex JWT、Claude 凭据）；Claude 用量响应解析；样本 `authoritative` 与 `profile_id` 一致；各上报时机（配对后、启动、空闲 5 分钟、任务后、限流、`--once`）；`output_tail` 截取。
- **Valley（go test）**：approve 不受 10 分钟限制；`online` 由心跳推导；闸门「unknown 放行、exhausted 等待」；`not_before` 未到不被 claim、到点被 claim；`plan_tier` / `output_tail` 的入库与返回；`not_before` 校验。
- **iOS（XCTest）**：QuotaPresentation 的 scope 映射、绝对重置时刻、套餐显示；带 `not_before` 的派发请求编码；「已安排」状态文案；UI 测试覆盖派发面板时间选择与「保存并安排时间」入口。
- **跨仓库集成**（`tests/integration/test_workspace_flow.py` + Valley `TestWorkspacePythonIntegration`）：新增「未知额度可领取」「到点才领取」「终态带 output_tail」三个场景。

## 6. 真机验收脚本

全部通过才算 0.1 完成。用户的 iPhone 与 Mac；Mac 端由 Claude 配合操作。

1. Mac 安装 CLI，`keji cloud login`；手机验证码登录，输码批准。**10 秒内**「你的 AI」页出现这台 Mac、Codex 与 Claude Code 两张卡，各带套餐等级、用量、重置时刻。
2. 手机新建任务「在 README 末尾加一行今天的日期」→ AI 来做 → 选这台 Mac、一个测试仓库、Codex → 保存并开始。**2 分钟内**状态走完 云端排队 → 电脑已领取 → AI 执行中 → 结果待确认；能展开输出尾巴；验收通过。
3. 同一任务换 Claude Code 再跑一遍，同样标准。
4. 派发时选 3 分钟后的时间，手机显示「已安排 · 时刻」；到点自动执行完成。
5. 合上 Mac 盖子，**2 分钟内**手机显示离线，派发面板选不到它；打开盖子后恢复在线。

## 7. 发布

- Valley：`release/timetrace-ai-workspace` 推送后 `gh workflow run publish.yml -f deploy=true` 部署生产（gh 切 `underestimatedme`）。
- CLI：从仓库安装到用户 Mac；`keji agent install` 常驻。
- iOS：TestFlight 构建，`MARKETING_VERSION` 仍为 `0.1.0`，`CURRENT_PROJECT_VERSION` 从 `2026092501` 起按日期编号。
- 文档：更新 `docs/remote-runner-operations.md`（保持唤醒、上报时机）、`keji-ios-release-checklist.md`。

## 8. 实施顺序（供实施计划展开）

1. 在用户 Mac 上探测 Claude 用量接口与两个套餐字段（半天内出结论，决定 4.2 走主路还是退路）。
2. Valley：R4 → 心跳在线 → 闸门收窄 → `plan_tier` → `not_before` → `output_tail`，每步带测试。
3. CLI：R1/R2 → 套餐采集 → Claude 用量 → 上报时机 → `output_tail`。
4. iOS：错误提示 → 额度卡片 → 派发面板时间选择 → 执行记录输出尾巴 → 「已安排」状态。
5. 跨仓库集成测试；部署 Valley；装 CLI；出 TestFlight。
6. 按第 6 节跑真机验收。
