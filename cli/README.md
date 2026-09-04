# keji（刻迹 CLI）

给 Claude Code 和 Codex 排任务的无人值守队列。撞到限额就睡到重置时间，再用原会话续接；顺手把两个工具每个限额桶的余量采样进 SQLite。

- 规划：`刻迹-CLI-MVP规划.md`
- 探针实测：`探针验证记录-2026-09-02.md`
- 设计：`../docs/superpowers/specs/2026-09-04-keji-cli-design.md`

零依赖，Python 3.9+ 标准库。

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
