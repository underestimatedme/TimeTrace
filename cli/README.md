# keji（刻迹 CLI）

给 Claude Code 和 Codex 排任务的无人值守队列。撞到限额就睡到重置时间，再用原会话续接；顺手把两个工具每个限额桶的余量采样进 SQLite。

- 规划：`刻迹-CLI-MVP规划.md`
- 探针实测：`探针验证记录-2026-09-02.md`
- 设计：`../docs/superpowers/specs/2026-09-04-keji-cli-design.md`

零依赖，Python 3.9+ 标准库。

## 手机远程派发（Valley Runner）

Claude/Codex 的登录凭据不会上传：iPhone 只把任务发给 Valley，本机 `keji agent` 通过出站 HTTPS 领取任务，再调用当前 macOS 用户已经登录的 CLI。

```sh
keji cloud login                    # 显示 8 位码，在 iPhone「AI 工具管理」批准
keji workspace add ~/code/TimeTrace # 只显式开放这个仓库
keji agent doctor                   # 检查配对、CLI 和工作区
keji agent run --once               # 联调一轮
keji agent install                  # 安装并启动登录用户的 LaunchAgent
```

Runner refresh token 存在 macOS 登录 Keychain（service `com.atlaspaces.keji.runner`）；access token 15 分钟轮换。每个远程任务仍进入独立 worktree，且 push 被禁用。电脑关机、休眠或未登录时，Valley 只保留排队任务，不会在云端接管本地代码或账号。

## 安装

```sh
ln -s "$(pwd)/bin/keji" /usr/local/bin/keji      # 或任何在 PATH 里的目录
keji --version
```

数据目录默认 `~/.keji/`（可用环境变量 `KEJI_HOME` 覆盖）：`keji.db`、`config.json`、`logs/`、`inbox/`、`worktrees/`。

## 用法

```sh
keji status                      # 各桶余量、重置倒计时、绑定约束（Codex 实时读，Claude 取最近采样）
keji add "重构 payment 模块的错误处理" --repo ~/code/paycore --tool claude
keji add "给上一步写单测" --repo ~/code/paycore --after 1 --any-tool
keji add "..." --repo ~/code/x --on-success "列出还需要补的重构点，每条一个任务"
keji ls [--all]
keji run [--once]                # 守护循环；--once 只跑一轮
keji logs 1 [-f]
keji retry 1 [--fresh]           # failed/blocked → runnable；--fresh 丢弃会话重来
keji rm 1
keji events [--type task_blocked]
```

任务状态：`pending → runnable → running → blocked → done / failed`。`blocked` 会自动恢复，`failed` 需要人看。

## 守护进程

前台：`keji run`。后台用 launchd：

```sh
sed -e "s#__KEJI_BIN__#$(pwd)/bin/keji#g" -e "s#__HOME__#$HOME#g" \
    launchd/com.keji.run.plist > ~/Library/LaunchAgents/com.keji.run.plist
launchctl load ~/Library/LaunchAgents/com.keji.run.plist
tail -f ~/.keji/daemon.log
```

## 配置 `~/.keji/config.json`（都是可选项，下面是缺省值）

```json
{
  "cloud_base_url": "https://apis.atlaspaces.com/timetrace/api/v1",
  "interval_sec": 30,
  "jitter_sec": 300,
  "default_block_sleep_sec": 3600,
  "circuit_breaker_failures": 3,
  "circuit_window_mins": 300,
  "allowed_repos": [],
  "hook_max_tasks": 5,
  "claude": {"bin": "claude", "permission_mode": "acceptEdits",
             "allowed_tools": ["Bash(git add:*)", "Bash(git commit:*)", "Bash(git status:*)",
                               "Bash(git diff:*)", "Bash(git log:*)"],
             "model": null, "extra_args": []},
  "codex":  {"bin": "codex",  "sandbox": "workspace-write", "model": null, "extra_args": []}
}
```

- `allowed_repos` 非空时，`keji add --repo` 必须落在其中某个目录之下。
- `permission_mode` 决定 Claude 无头运行时能做什么。`acceptEdits` 允许改文件，命令只放行 `allowed_tools` 里的（缺省是本地 git 提交相关的几条）；要让它跑构建和测试，往 `allowed_tools` 加规则（如 `"Bash(npm test:*)"`）或把模式改成 `bypassPermissions`。这是你的决定，工具不替你做。
- Codex 的 `sandbox` 对应 `codex exec -s`；`workspace-write` 只允许写 worktree 内的文件。

## 安全约束

- 每个任务在独立的 git worktree（`~/.keji/worktrees/<id>`，分支 `keji/<id>`）里运行，从不碰主工作区。
- worktree 内所有远端的 pushurl 被改成 `no_push://blocked`，`git push` 立即失败；Claude 另加 `--disallowedTools "Bash(git push*)"`；两个工具的提示词都写明禁止 push、禁止改远端分支和 CI 配置。
- 熔断：默认 5 小时内 3 次失败就停止派工，直到窗口过去或你 `keji retry`。
- v0.3 的 on_success 钩子只产出一份声明式 JSON 到 `~/.keji/inbox/`，由守护进程下一轮校验后入库；钩子生成的任务不能再生成任务。

## 零付费核验（派发门禁的计费项）

Runner 只在「运行任务不可能产生新增费用」时才派发。这不是配置项，而是每次派发前的实测：

| 工具 | 通过条件 | 实现 |
| --- | --- | --- |
| Claude Code | `claude auth status` 报告 `loggedIn=true`、`authMethod=claude.ai`、`apiProvider=firstParty` 且有 `subscriptionType` | `keji/billing.py: verify_claude` |
| Codex | `codex login status` 报告 `Logged in using ChatGPT`，且 `~/.codex/auth.json` 的 `auth_mode=chatgpt`、无 `OPENAI_API_KEY` | `keji/billing.py: verify_codex` |

另外两条对两个工具都生效：

- 环境里不能有 API key 或替代端点（`ANTHROPIC_API_KEY`、`ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_BASE_URL`、`CLAUDE_CODE_USE_BEDROCK/VERTEX/FOUNDRY`、`OPENAI_API_KEY`、`CODEX_API_KEY`、`OPENAI_BASE_URL`），
  Claude 的 `settings.json` 里不能有 `apiKeyHelper` 或上述 `env`。
- 无论核验结果如何，启动工具进程时这些变量都会从子进程环境中剔除，订阅工具不可能悄悄切到按量计费。

核验通过时 adapter 的 `can_enforce_zero_spend` 为 true；否则为 false 并带机器可读原因
（`not_logged_in`、`auth_method_not_subscription:<x>`、`api_key_fallback_in_env:<VAR>` 等），
统一门禁返回 `billing_unverified`，该工具不会收到任务。结论缓存 5 分钟，但真正 spawn 前会强制重新核验。
`keji agent doctor` 会逐工具打印核验结论。核验只读登录状态，不会启动模型、不消耗额度。

## 限额消耗的两部分覆盖：终端 + 软件

限额是账号级的，不管你在终端里跑还是在软件里点，烧的都是同一个窗口。keji 的到期判断和续接时机必须两边都看得到：

| 消耗来源 | Codex | Claude Code |
|---|---|---|
| 终端（keji 无头运行） | `codex exec` 结束后立刻 `account/rateLimits/read` | 每次 `claude -p` 的 `rate_limit_event` |
| 软件（你自己在 Codex 应用 / Claude Code 里用） | 同一接口，服务端真值，天然包含应用内消耗 | **`keji statusline`**：挂进 Claude Code 状态栏，每次刷新把 `rate_limits` 写进库 |

装 Claude Code 状态栏钩子（会往 `~/.claude/settings.json` 写 `statusLine`，已有别的状态栏脚本时不覆盖）：

```sh
keji statusline --install
```

之后 Claude Code 的状态栏会显示 `keji · 5h 86% · 7d 97% · codex 35% · ⏳ 3h12m`，同时你交互会话里撞到的限流（100%）会让守护进程停止往 Claude 派工，直到 `resets_at` 过去或有新样本。

判断规则：任一桶最新样本 `used == 100%` 且 `resets_at` 还没到 → 该工具耗尽；`resets_at` 已过而没有新样本 → 视为已重置，照常派工，由真实运行结果说话。

## 两个工具的差别

| | Claude Code | Codex |
|---|---|---|
| 限额读取 | 无按需接口；每次运行的 `rate_limit_event` 顺带给出 | `codex app-server` 的 `account/rateLimits/read`，随时读、不耗额度 |
| 执行 | `claude -p --output-format stream-json --session-id <uuid>` | `codex exec --json -s workspace-write -C <worktree>` |
| 续接 | `claude -p --resume <session_id>` | `codex exec resume <thread_id>` |
| 撞限流 | `rate_limit_info.status == rejected` 或 HTTP 429 | JSONL `error` 事件含 "usage limit"，退出码 1；重置时间取自 app-server |

## 开发

```sh
cd cli && python3 -m unittest discover -s tests -v
```

## Report occurrence timestamps

Runner phase events include an `observed_at` UTC RFC 3339 timestamp captured
at the actual adapter start/resume call and its return/exception boundary.
Preflight renewal, running-event transport, quota upload and checkpoint/git IO
do not define the execution interval. The worker captures times; the owning
thread durably enqueues running without a blocking flush, then flushes events
in sequence after terminal handling. Claim/Plan identity is durable before any
execution; event payloads are durable before any send. Lease heartbeats and
spawn/cancellation fences remain active while the adapter runs. A killed or
lease-fenced attempt without a trustworthy terminal remains unknown.
Outbox retries, including after restart, retain the
original timestamp and event sequence. The server separately records receipt
time, validates observation order and lease/clock bounds, and uses occurrence
time for report day slicing. Keep the runner clock synchronized; deploy the
Valley nullable `observed_at` migration before this runner update. Legacy outbox
events without this field remain unknown report measurements, not zero-duration
execution. Existing expired-lease reporting restrictions remain in force.

Pending events for each `(job_id, attempt_id, lease_epoch)` are sent together,
ordered by sequence, then acknowledged in one atomic SQLite update. Attempt
groups follow durable enqueue order, not UUID lexical order. A lost response or
failed local acknowledgment retries the whole unchanged batch; a 409 is never
silently discarded. No schema migration is needed for existing outboxes.
See `tests/integration/README.md` for the real Valley/PostgreSQL cancellation
regression, including lost-response recovery and the next job claim.
