# 刻迹 CLI（keji）设计文档

日期：2026-09-04
依据：`cli/刻迹-CLI-MVP规划.md`（需求）、`cli/探针验证记录-2026-09-02.md`（三个探针的实测结论）。
范围：v0.1 只读仪表 + v0.2 队列与阻塞恢复 + v0.3 后继任务，一次交付。

## 1. 目标与非目标

**目标**：一个自用的命令行工具，在无人值守时把编码任务排成队列，交给 Claude Code 或 Codex 无头执行；撞到限额就睡到重置时间再用原会话续接；同时把两个工具各个限额桶的余量采样进 SQLite，作为后续 App 的数据底座。

**非目标**（照 MVP 文档第 3 节）：不做 TUI/Web、不做单文件二进制、不解析会话 JSONL、不算美元成本、不做手动打卡、不支持 Cursor/Gemini。

## 2. 技术选型

- Python 3.9 标准库，零第三方依赖。用到 `argparse`、`sqlite3`、`subprocess`、`json`、`uuid`、`threading`。
- 代码在 `cli/keji/` 包内，入口 `cli/bin/keji`（一行 shell 包装，调 `python3 -m keji`）。
- 数据目录 `~/.keji/`：`keji.db`、`config.json`、`logs/<run_id>.log`、`inbox/`（v0.3 待摄入的任务 JSON）、`inbox/done/`、`worktrees/<task_id>/`。
- 守护进程就是 `keji run` 前台常驻，用 launchd 拉起。仓库里放一份 plist 样例。

## 3. 命令

```
keji status [--json]            各桶余量、重置倒计时、当前绑定约束
keji add "<prompt>" --repo <path> [--tool claude|codex] [--any-tool]
         [--after <task_id>] [--priority N] [--on-success "<prompt>"]
keji ls [--all]                 任务表（默认隐藏 done）
keji run [--once] [--interval N]  守护循环；--once 只跑一轮，用于测试
keji logs <task_id> [-f]        最近一次 run 的日志
keji retry <task_id>            failed → runnable
keji rm <task_id>               删除未运行的任务
keji events [--limit N]         最近事件（复盘用）
```

## 4. 数据模型

五张表，字段取 MVP 文档为基础，按探针结论调整。所有时间存 Unix epoch 秒（整数）。

**task**：id, prompt, repo, tool（`claude`/`codex`/NULL）, any_tool（0/1）, session_id, state, depends_on（task id，可空）, on_success（prompt 文本，可空）, priority（默认 0，大者先）, generation（0 = 人写的，1 = 钩子生成的）, parent_id, worktree, branch, blocked_until, last_error, created_at, updated_at。

状态：`pending → runnable → running → blocked → done / failed`。`pending` 表示依赖未完成；依赖 done 后转 `runnable`；依赖 failed 则本任务也 failed（写 last_error）。

**run**：id, task_id, tool, started_at, ended_at, exit_code, blocked（0/1）, session_id, log_path, summary。一个任务多次 run。

**bucket**：id, tool, bucket_key, window_mins, is_representative。`bucket_key` 约定：
- Claude：`claude:five_hour`、`claude:seven_day`，以及未来出现的任何 `rateLimitType` 值原样入库（如 `claude:seven_day_opus`）。
- Codex：`codex:<limit_id>:primary` / `codex:<limit_id>:secondary`，如 `codex:codex:primary`、`codex:base_model_inference:primary`。
桶集合是服务端下发的，代码里不写死清单，见到新桶自动 upsert。

**sample**：id, bucket_id, at, used_pct（0–100 浮点，统一从 Claude 的 utilization×100 / used_percentage 与 Codex 的 usedPercent 归一），reset_at, source（`run` / `live` / `statusline`）。

**event**：id, type, tool, bucket_id, at, payload（JSON 文本）。type 至少有：`rate_limit`、`window_reset`、`sample_failure`、`task_blocked`、`task_resumed`、`tool_switched`、`task_done`、`task_failed`、`circuit_open`、`hook_generated`、`hook_rejected`。

「还剩多少」= 各桶最新 sample 的 `100 - used_pct` 取最小值。

## 5. 工具适配器

同一接口，两个实现。接口先按两个工具一起设计（MVP 文档第 3 节的要求）。

```python
class ToolAdapter:
    name: str
    def read_limits(self) -> Optional[List[Sample]]   # 按需读；Claude 返回 None（没有按需通道）
    def start(self, prompt, cwd, session_id, log) -> RunResult   # 新会话无头执行
    def resume(self, prompt, cwd, session_id, log) -> RunResult  # 用 session_id 续接
```

`RunResult`：exit_code, session_id, ok（正常完成）, blocked（撞限额）, reset_at（可空）, samples（本次运行顺带拿到的桶样本）, error（文本）, output（最终回复文本）。

**Claude 适配器**（`adapters/claude.py`）
- 命令：`claude -p --output-format stream-json --verbose --session-id <uuid> --permission-mode <cfg> --disallowedTools "Bash(git push*)" ... --append-system-prompt <安全规则> <prompt>`，`cwd` 为 worktree，stdin 重定向 `/dev/null`。续接把 `--session-id` 换成 `--resume <sid>`。
- 逐行解析 stream-json：
  - `rate_limit_event.rate_limit_info`：`unifiedWindows` 每个键一份 sample；`rateLimitType` 标记 representative；`status == "rejected"` 判为 blocked，`resetsAt` 为 reset_at。
  - `result`：`is_error`、`subtype`、`api_error_status`（429 判 blocked）、`result` 文本。文本含 "hit your limit" / "usage limit" 也判 blocked（兜底）。
- 会话 id 在启动前由 keji 生成并写进 `run`，进程被杀也能续接。

**Codex 适配器**（`adapters/codex.py`）
- 读限额：起 `codex app-server`（stdio），发 `initialize` → `initialized` → `account/rateLimits/read`，解析 `rateLimitsByLimitId`（没有则退回 `rateLimits`），每个 limit_id 的 primary/secondary 各一份 sample，10 秒超时后杀进程。
- 执行：`codex exec --json -s <cfg sandbox> -C <worktree> --skip-git-repo-check -o <last_msg_file> <安全规则 + prompt>`。解析 `thread.started.thread_id` 为 session_id；`error`/`turn.failed` 且 message 含 "usage limit" 判 blocked，reset_at **不从文本解析**，而是紧接着调一次 `read_limits` 取 `codex` 桶 primary 的 `resetsAt`（取不到则退到配置的默认睡眠）。
- 续接：`codex exec resume <thread_id> --json -o <file> <prompt>`。

## 6. 守护循环（`keji run`）

每一轮：

1. 摄入 `~/.keji/inbox/*.json`（v0.3），校验后入库，文件移到 `inbox/done/`。
2. 依赖推进：`pending` 任务的依赖已 done → `runnable`；依赖 failed → failed。
3. 阻塞唤醒：`blocked` 且 `blocked_until <= now` → `runnable`，写 `window_reset` 事件。
4. 熔断：最近 `circuit_window_mins` 内 failed 的 run 数 ≥ `circuit_breaker_failures` → 写 `circuit_open` 事件，本轮不派工，睡一个 interval。
5. 取任务：`runnable` 按 priority 降序、id 升序取第一个。
6. 选工具：
   - 任务已有 session_id → 只能用原工具（上下文带不过去），且不做降级。
   - 否则 task.tool 指定则用它；仅当该工具最新样本 used_pct ≥ 100 且 `any_tool` 为 1 时，换另一个 used_pct < 100 的工具，写 `tool_switched` 事件。
   - 两个工具都为 100 → 跳过本轮。**百分比只在 100 时才拦，其余一律试**。
7. 建 worktree（首次运行时）：`git -C <repo> worktree add -b keji/<task_id> ~/.keji/worktrees/<task_id> HEAD`，并 `git config remote.<每个远端>.pushurl no_push://blocked`。
8. 执行或续接，写 run 行，stdout/stderr 全量落到 `logs/<run_id>.log`。
9. 收尾：
   - blocked → task.state = blocked，`blocked_until = reset_at + random(0, jitter_sec)`，写 `task_blocked`、`rate_limit` 事件；
   - ok → done，写 `task_done`；有 `on_success` 则跑钩子（第 7 节）；
   - 其它 → failed，`last_error` 记 error，写 `task_failed`。
10. 采样：本次 run 带回的 samples 入库（source=run）；Codex 侧再 `read_limits` 一次（source=live）。
11. 无事可做则 `sleep interval`。

`--once` 只跑一轮就退出，`keji run` 的所有决策都写 event，方便复盘。

## 7. 后继任务钩子（v0.3）

- `task.on_success` 是一段 prompt。任务 done 后，用同一工具 `resume` 原会话，发送：`on_success` 文本 + 固定的输出约束「只输出一个 JSON 数组，每个元素 {"prompt": str, "tool": "claude"|"codex"|null, "any_tool": bool}，不要输出其他内容」。
- keji 从最终回复里抽出 JSON，原样写到 `~/.keji/inbox/<parent_id>-<ts>.json`，写 `hook_generated` 事件。**不执行模型给出的任何命令**。
- 摄入时校验：必须是数组、每项有非空 prompt、条数 ≤ `hook_max_tasks`（默认 5）；`generation = parent.generation + 1`；父任务 `generation ≥ 1` 的钩子在生成阶段就直接跳过并写 `hook_rejected`（链深度上限 1）。生成的任务继承父任务的 repo，`depends_on` 指向父任务。
- 校验失败的文件移到 `inbox/rejected/`，写 `hook_rejected`。

## 8. 安全约束（对应 MVP 文档第 4 节）

- 每个任务独立 worktree，分支 `keji/<task_id>`，永不在主工作区跑。
- 所有远端的 pushurl 改为 `no_push://blocked`；Claude 追加 `--disallowedTools "Bash(git push*)"`；两边的系统提示都写明禁止 push、禁止改远端分支、禁止改 CI 配置、只提交到当前分支。
- 权限模式可配：Claude 默认 `--permission-mode acceptEdits`，Codex 默认 `-s workspace-write`；用户可在 config 里改成更宽松的模式，工具不替用户决定。
- `allowed_repos` 白名单：非空时 `keji add --repo` 必须落在其中某个目录之下；空时不限制。
- 熔断：见第 6 节第 4 步，默认 5 小时内 3 次失败停机。

## 9. 配置（`~/.keji/config.json`，缺省值）

```json
{
  "interval_sec": 30,
  "jitter_sec": 300,
  "default_block_sleep_sec": 3600,
  "circuit_breaker_failures": 3,
  "circuit_window_mins": 300,
  "allowed_repos": [],
  "hook_max_tasks": 5,
  "claude": {"bin": "claude", "permission_mode": "acceptEdits", "model": null, "extra_args": []},
  "codex":  {"bin": "codex",  "sandbox": "workspace-write", "model": null, "extra_args": []}
}
```

## 10. 模块划分

```
cli/keji/
  __main__.py      入口，调 cli.main
  cli.py           argparse，把子命令分发到各模块
  config.py        读取/合并 config.json
  db.py            schema、连接、所有 SQL（其它模块不写 SQL）
  models.py        Task/Run/Sample/RunResult 数据类与状态常量
  limits.py        样本入库、余量计算、绑定约束、status 渲染数据
  adapters/base.py ToolAdapter 接口、RunResult、安全规则文本
  adapters/claude.py
  adapters/codex.py
  worktree.py      建/查 worktree，封 pushurl
  scheduler.py     第 6 节的一轮循环，纯函数式接收 adapters 与 db，便于测试
  hooks.py         第 7 节：钩子调用、inbox 写入、摄入校验
  render.py        status/ls/events 的表格输出
cli/bin/keji
cli/tests/         unittest；适配器解析用探针录下的真实输出做夹具
cli/launchd/com.keji.run.plist
cli/README.md
```

## 11. 测试

- `db`：建表、upsert 桶、最新样本查询。
- `limits`：归一化、绑定约束取最小余量、Claude representative 标记。
- `adapters/claude`：用探针录下的 stream-json 行做夹具，测 sample 抽取、blocked 判定（rejected / 429 / 文本）。
- `adapters/codex`：用探针录下的 `account/rateLimits/read` 返回和限流 JSONL 做夹具。
- `scheduler`：假适配器（返回预设 RunResult），测状态机全路径：done、failed、blocked→唤醒→resume、any_tool 降级、有 session 不降级、熔断、依赖推进。
- `hooks`：JSON 抽取、校验、深度上限、条数上限。
- 手工验收：`keji add` 一个真实小任务到本仓库的 `cli/` 之外的测试仓库，`keji run --once` 跑通。

## 12. 未决与留待

- Claude 撞限流时 `-p` 的真实输出尚未抓到，判定逻辑按三重兜底写，等窗口自然耗尽时用 `keji events` 核对。
- Codex 独立 code review 桶未见，桶集合动态入库即可覆盖。
