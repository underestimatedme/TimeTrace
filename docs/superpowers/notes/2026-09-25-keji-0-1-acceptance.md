# 刻迹 0.1 真机验收记录

验收脚本见 `docs/superpowers/specs/2026-09-25-keji-0-1-core-flow-design.md` §6。设备：用户 iPhone（TestFlight 0.1.0 (2026092503)）+ Joeys-MacBook-Air（`keji agent` LaunchAgent）。后端：Valley `release/timetrace-ai-workspace` 生产（2026-09-25 两次部署）。

| 步骤 | 结果 | 时间 | 备注 |
|---|---|---|---|
| 1 配对可见性 | **通过** | 2026-09-25 10:3x | 输码 DFB369E3 批准后 Mac 立即上报；首版显示 Codex 周额度错窗（选到 gpt-reserve 备用限额），2026092503 修复后显示 Codex prolite 本周剩余 89%、9 月 30 日 23:00 重置，Claude team 两窗。Runner 需要在跑（心跳）才显示在线，仅配对时显示离线是预期 |
| 2 Codex 派发 | 待做 | | 任务「在 README 末尾加一行今天的日期」→ acceptance 仓库 → Codex |
| 3 Claude Code 派发 | 待做 | | 同一任务换 Claude Code |
| 4 定时派发 | 待做 | | 选 3 分钟后，显示「已安排 · 时刻」，到点执行 |
| 5 合盖离线 | 待做 | | 2 分钟内显示离线且派发面板不列出；打开后恢复 |

## 验收中发现并修复的问题

- Codex prolite 套餐只有一个放在 `primary` 槽位的 7 天窗；按槽位名分类会当成短时窗，且周额度行可能选到备用限额。改为按窗口时长分类、优先主限额、卡片脚注显示重置时刻（CLI + iOS，2026092503）。
- 底部标签栏背景没有延伸到屏幕底边，留一条页面底色（iOS，2026092503）。
- `keji cloud login` 通过 Python 缓冲把配对码憋在 stdout 里；用 `PYTHONUNBUFFERED=1` 运行即可看到（未改代码，已记录）。
- `keji agent doctor` 现在打印套餐与实时额度，和手机应显示的一致，用于现场对照。
