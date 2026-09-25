# 刻迹 0.1 真机验收记录

验收脚本见 `docs/superpowers/specs/2026-09-25-keji-0-1-core-flow-design.md` §6。设备：用户 iPhone（TestFlight 0.1.0 (2026092503)）+ Joeys-MacBook-Air（`keji agent` LaunchAgent）。后端：Valley `release/timetrace-ai-workspace` 生产（2026-09-25 两次部署）。

| 步骤 | 结果 | 时间 | 备注 |
|---|---|---|---|
| 1 配对可见性 | **通过** | 2026-09-25 10:3x | 输码 DFB369E3 批准后 Mac 立即上报；首版显示 Codex 周额度错窗（选到 gpt-reserve 备用限额），2026092503 修复后显示 Codex prolite 本周剩余 89%、9 月 30 日 23:00 重置，Claude team 两窗。Runner 需要在跑（心跳）才显示在线，仅配对时显示离线是预期 |
| 2 Codex 派发 | **通过** | 2026-09-25 20:00 | 第一次因服务端写 `todo` 状态导致同步失败（已修）；第二次链路通但 `git commit` 被沙箱拦（已修 `--add-dir`）；第三次「hello task」在 worktree 提交 `647f96c`，手机看到输出并验收 |
| 3 Claude Code 派发 | **通过** | 2026-09-25 19:58 | Claude 追加 `2026-09-25 19:58:13` 并提交 `41cde6d` |
| 4 定时派发 | **定时通过，执行待重跑** | 2026-09-25 20:05 | 「保存并安排时间」后到点被领取；但 Codex 读到硬规则「只能读写当前目录」，发现 worktree 的 git 元数据在目录外而主动停手，未改文件。已把规则改为明确允许在本 worktree add/commit，待再跑一次定时任务确认 |
| 5 合盖离线 | **通过** | 2026-09-25 20:1x | 合盖后手机显示离线；开盖恢复 |

## 验收中发现并修复的问题

- Codex prolite 套餐只有一个放在 `primary` 槽位的 7 天窗；按槽位名分类会当成短时窗，且周额度行可能选到备用限额。改为按窗口时长分类、优先主限额、卡片脚注显示重置时刻（CLI + iOS，2026092503）。
- 底部标签栏背景没有延伸到屏幕底边，留一条页面底色（iOS，2026092503）。
- `keji cloud login` 通过 Python 缓冲把配对码憋在 stdout 里；用 `PYTHONUNBUFFERED=1` 运行即可看到（未改代码，已记录）。
- `keji agent doctor` 现在打印套餐与实时额度，和手机应显示的一致，用于现场对照。
- 服务端任务状态投影写出 `todo` / `in_progress`，手机枚举没有，导致派发后整份同步失败（Valley 第四次部署 + iOS 2026092504）。这类问题以后靠「手机模型对服务端真实响应的契约测试」兜底：服务端每个投影状态都应出现在 iOS 的 `WorkspaceContractTests` 里。
- Codex 的 workspace-write 沙箱只允许写工作目录，linked worktree 的 `.git` 在主仓库里，`git commit` 被拒。CLI 现在把 `git rev-parse --git-common-dir` 作为 `--add-dir` 传给 Codex。
- 给无人值守运行的硬规则第 3 条「只读写当前目录」让 Codex 在 linked worktree 里拒绝提交（元数据在主仓库 `.git`）。规则文字改为明确允许本 worktree 的 `git add` / `git commit`。
