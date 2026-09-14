# 刻迹 AI 工作台 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将刻迹升级为围绕版本目标、个人时间和多 AI 执行的工作台；本文件是待用户 review 的实施计划，不是执行授权。

**Architecture:** 保留 SwiftUI → Valley Go API → 本机 Python Agent。Valley 保存权威计划、额度协调和执行状态；工具凭据与代码留在电脑；iOS 负责规划、解释与验收。独立 Plan 连接现有 Task 和 RemoteJob，复用 RemoteAttempt，避免新旧调度同时启动进程。

**Tech Stack:** iOS 17+ / SwiftUI / Swift 5；Go / GORM / PostgreSQL；Python CLI；React 19 / TypeScript / Vite 设计原型。

**Spec:** [产品设计](../specs/2026-09-14-keji-ai-timeline-product-design.md)。执行前阅读本文、产品设计和对应子计划。

## Global Constraints

- 业务层级固定为项目 → 任务 → Plan；目标是项目的版本/里程碑属性与任务分组，不增加第四级目录。
- 用户确认：自动续杯指订阅额度自然恢复后自动续跑暂停的 Plan，不额外付费。
- 工具与模型分开；未知额度不等于满额；不把所有工具写成固定五小时。
- 优先级 P0–P3 可人工固定；硬阻塞不能被评分越过。
- 已经开始的 Plan 默认保持原工具/会话；取消后不得被旧的恢复定时器唤醒。
- 首版每台 Runner 单个编码进程；同一 Plan/工作目录不能并发写入。
- 没有可验证的新增计费限制，不开放无人值守续跑；不自动兑换、购买、充值或使用付费 API 回退。
- 日报默认私有草稿；不自动修改仓库 CHANGELOG.md、创建 release 或发布报告。
- 生产力按预先确认的范围与工作量计分，不按 Plan 数、tokens 或代码行数奖励。
- 保留用户最终 Logo、历史记录、旧客户端读取能力和当前发布流水线；本次不改变生产环境。

## 1. Review 入口与当前范围

- [交互原型](http://127.0.0.1:5194/review)：今日、项目、时间线、AI、报告；全部数据为演示。
- 最新原型：`design/src/review/GlassWorkspace.tsx`、`AccountCenter.tsx`、`GlassUI.tsx`、`glassModel.ts`、`preferences.ts`、`glass.css`；入口 `design/src/App.tsx`。旧WorkspaceReview保留在 `/review-v1`。
- 最新 Logo 复用 `design/logo.png`；旧版入口 `/legacy` 保留。
- 本次实现的是设计原型。生产 iOS、Valley 和 CLI 没有实施本计划的新功能。
- 原型覆盖三级创建、代表性日/周视图、验收、额度恢复和完整个人中心；真实认证、持久化、完整编辑、历史、多轨折叠与推送仍待生产实现。默认视觉已按最后附图改为浅色玻璃。

## 2. 子计划与依赖

| 门 | 子计划 | 独立可验收的结果 | 前置 |
| --- | --- | --- | --- |
| A | [Valley：领域、执行与报告](2026-09-14-keji-valley.md) V1–V2 | 旧记录迁移、Plan API、旧同步隔离 | 产品 review |
| B | [iOS：工作台](2026-09-14-keji-ios.md) I1–I2 | 五入口、三级结构、时间线，fixture 可验收 | API 契约固定；可先离线 |
| C | [工具端：额度与恢复](2026-09-14-keji-runner.md) R1–R3 + Valley V3 | 一个真实 Plan 限额→等待→原会话恢复→验收 | A；计费能力实测 |
| D | Valley V4 + iOS I3 | 可解释优先级、推荐、可追溯日报 | A、事件链 |
| E | Valley V5 + Runner R4 | 公共信号独立接入、Cursor/Gemini 能力分级 | C 不依赖 E |
| F | iOS I4 + Valley V6 | 账号、隐私、偏好、设备撤销与反馈闭环 | 既有认证审计 |

每个任务走测试先失败→最小实现→通过→独立提交→review。跨仓库变更分别提交，并在同一验收记录中引用版本。不在当前发布分支直接堆叠所有改动。

## 3. 文件归属

TimeTrace 根目录：`/opt/coding/planb/github/.worktrees/timetrace-remote-runner`。
Valley 根目录：`/opt/coding/planb/github/.worktrees/valley-timetrace-remote-runner`。
子计划内路径均相对其标注仓库；`Create` 表示计划新建，不代表当前存在。

| 边界 | 权威数据 / 责任 | 不负责 |
| --- | --- | --- |
| Valley | Plan revision、依赖、账号额度池、job lease、日报事实 | 读取电脑 CLI 凭据、直接执行本机代码 |
| Runner | 工具能力核验、原生 start/resume、本地互斥、日志与证据 | 覆盖已取消计划、决定用户验收通过 |
| iOS | 项目目标、编辑和审批、展示来源与阻塞原因 | 手机后台定时唤醒电脑、将倒计时当真实额度 |

## 4. 固定 API / 状态契约

仍使用 `/timetrace/api/v1`，新增端点采用 additive schema；响应包含 `schema_version:2`。Plan 的执行状态由服务端投影，不接受快照覆盖。

```json
{
  "id":"plan-01", "task_id":"task-01", "revision":1,
  "title":"统一额度窗口", "priority":1, "status":"ready",
  "criteria":["未知额度显示未知"], "depends_on":[],
  "estimated_human_minutes":10, "estimated_ai_minutes":35,
  "work_weight":1, "risk":2,
  "execution_policy":{"mode":"balanced","preferred_profile_id":null,
    "allow_auto_resume":true,"max_additional_spend_minor":0}
}
```

`status`：draft / ready / queued / running / waiting_quota / waiting_local_auth / waiting_input / awaiting_review / accepted / failed / cancelled。Runner 离线作为阻塞原因，不丢失原状态。`priority` 为 0–3；risk 为 1–5；work_weight > 0，任务范围内归一化，冻结基线后变更留审计。

`QuotaWindow`：pool_id、scope、kind、used_percent nullable、reset_at nullable、observed_at、expires_at、source、confidence。UTC RFC3339 传输；展示和日报使用用户 IANA 时区。账号池 ID 为用户域内 opaque ID；本机 profile 通过明确绑定引用，不上传令牌、完整账号邮箱或命令行环境。

`Capabilities`：can_record、can_read_quota、can_dispatch、can_resume、can_enforce_zero_spend；另带 adapter_version、verified_at、unsupported_reason。五项不能由一个 connected 布尔量替代。

`DispatchDecision`：plan_id、plan_revision、eligible、reason_codes、preferred_profile_id、alternatives、score_version、sample_count、created_at。工具推荐是解释，不是绕过 dispatch 门禁的凭据。

## 5. 发布与兼容门禁（执行阶段）

- [ ] 导出迁移前行数/归属/活跃 job 清单，在隔离数据库验证可恢复备份；不要以生产 DSN 跑测试。
- [ ] Valley 先发布 additive schema + legacy task→default Plan 映射，开关默认关闭；旧 Runner 继续单任务兼容路径。
- [ ] 发布 Runner 能力上报与统一启动门禁，未升级版本不能领取 Plan 原生任务。
- [ ] 发布 iOS 新数据解码与离线迁移，再按用户开启 `plan_workspace`、`quota_resume_v2`、`daily_reports`；公共信号另开 `public_reset_signals`。
- [ ] 唯一约束切换时所有 Valley 实例必须先移除旧的按 task 去重启动逻辑；不能滚回会重新建立旧索引的旧 binary。
- [ ] 关闭功能开关回退 UI/新领取，不删除 Plan 或事件；已运行作业继续保留 lease/取消控制。数据库回滚仅在维护窗口按演练方案执行。
- [ ] 必须实际通过下列矩阵后，另请用户决定上线、App Store 上传或审核提交。

| 验收场景 | 预期 |
| --- | --- |
| 旧任务/重复迁移/旧 iOS 同步 | 默认 Plan 恰好一份；历史时长不双计；新状态不回退 |
| 两个 Plan 属于同 Task | 可以排队；单 Runner 仍串行；不同合法工作区可跨机执行 |
| 同一 Plan 两台机器竞争 | 一个 lease、一个有效启动；过期 attempt 事件被拒绝 |
| 短时恢复、周窗口耗尽 | 等待周窗口，不派发 |
| 陈旧/未知样本、可能公告 | 显示待核验；不显示 100%；不直接解锁 |
| 自动续跑关闭、取消、授权失效、电脑离线 | 分别显示原因；不意外续跑 |
| 断网补报/重复事件/跨时区午夜 | 幂等、日报修订、事实不重复 |
| 无新增计费保障 | 仅管理/人工处理，不自动执行 |

## 6. Review 建议

先看今日是否明确“我现在该做什么”，再进入项目→任务→Plan，最后检查 AI 页的额度恢复策略与报告依据。确认导航、层级、零付费边界后，再按 A→C 主链推进生产代码；I2 的静态 UI 可以在契约固定后独立推进。

当前等待用户 review。后续可选择逐项在本任务实施，或明确授权子代理分工；本轮不启动实现工作。
