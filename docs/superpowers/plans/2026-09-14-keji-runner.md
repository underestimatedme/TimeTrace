# 刻迹工具端 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本机 CLI 按可验证额度与计费边界，安全恢复同一个 Plan。

**Architecture:** 扩展已有 Python adapters、SQLite、scheduler 和 cloud Agent；统一进程启动门禁。订阅登录仍来自本机 profile，Valley 只接收绑定 ID、能力和去敏后的额度样本。

**Tech Stack:** Python 标准库 unittest、SQLite、现有 Claude/Codex CLI adapters；路径相对 TimeTrace 仓库。

**Spec:** [产品设计](../specs/2026-09-14-keji-ai-timeline-product-design.md)；[总计划与契约](2026-09-14-keji-ai-workspace.md)。

## Global Constraints

- 自动续杯指订阅额度自然恢复后自动续跑暂停的 Plan，不额外付费。
- 未知额度不等于满额；公共信号不能直接解除个人额度阻塞。
- 已经开始的 Plan 默认保持原工具/会话；取消后不得被旧的恢复定时器唤醒。
- 首版每台 Runner 单个编码进程；同一 Plan/工作目录不能并发写入。
- 没有可验证的新增计费限制，不开放无人值守续跑。
- 总计划 Global Constraints 全部适用；本轮不启动真实 AI 任务。

## 文件结构

沿用 `cli/keji/adapters/` 定义厂商边界；新增 `quota.py` 负责语义，`dispatch.py` 负责唯一启动门禁，`checkpoints.py` 负责恢复数据。不要在 iOS 和 scheduler 各自复制另一套恢复策略。所有测试从 `cli/` 目录运行。

### R1：额度 tri-state 与账号能力

**Files:** Create `cli/keji/quota.py`、`cli/tests/test_quota.py`；Modify `cli/keji/models.py`、`limits.py`、`db.py`、`adapters/base.py`、`adapters/claude.py`、`adapters/codex.py`、`cloud.py`。

**Interfaces:** `Window(used_percent: float | None, reset_at: float | None, observed_at: float, expires_at: float)`；`availability(windows: list[Window], now: float) -> str` 返回 available / blocked / unknown。厂商采样包装为总计划 QuotaWindow，增加 opaque pool/profile ID、来源/适用窗口和 adapter version；未知 window 列表不代表无限额度。

- [ ] 写过期样本与周额度测试。

```python
import unittest
from keji.quota import Window, availability

class QuotaTest(unittest.TestCase):
    def test_unknown_and_multi_window(self):
        self.assertEqual(availability([], 200), "unknown")
        self.assertEqual(availability([Window(100, 100, 50, 150)], 200), "unknown")
        windows = [Window(0, 300, 190, 250), Window(100, 900, 190, 250)]
        self.assertEqual(availability(windows, 200), "blocked")
```

- [ ] `python3 -m unittest tests.test_quota -v` 应因未实现模块失败。
- [ ] 实现纯函数，将 legacy `tool_exhausted` 保留给旧路径，不把其 false 投影为“已确认满额”。移除新路径 `_most_remaining` 中 unknown=100 的排序方式。

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Window:
    used_percent: float | None
    reset_at: float | None
    observed_at: float
    expires_at: float

def availability(windows: list[Window], now: float) -> str:
    fresh = [w for w in windows if w.observed_at <= now < w.expires_at]
    if any(w.used_percent is not None and w.used_percent >= 100 for w in fresh):
        return "blocked"
    if not windows or len(fresh) != len(windows) or any(w.used_percent is None for w in fresh):
        return "unknown"
    return "available"
```

输入解析拒绝 NaN、负数、>100；expires_at 不能晚于可信 reset_at。已知耗尽但无可信 reset 的窗口保留阻塞证据，失效后状态可变 unknown，但不满足“可靠 reset 已到”条件，不能触发试跑。新增五项 capability 默认 false，只由 adapter 实测/本机配置核验提升；来源手工输入不能授予自动执行。
- [ ] `python3 -m unittest tests.test_quota tests.test_limits tests.test_cloud -v`；回归旧采样展示并检查 payload 无 token、邮箱、环境变量。
- [ ] 提交 `feat(cli): model quota uncertainty and verified capabilities`。

### R2：统一启动门禁与本机互斥

**Files:** Create `cli/keji/dispatch.py`、`cli/tests/test_dispatch.py`；Modify `scheduler.py`、`agent.py`、`process.py`、`worktree.py`、`db.py`、`config.py`（均在 cli/keji）。

**Interfaces:** `DispatchGate(cancelled: bool, lease_valid: bool, runner_online: bool, dependencies_ready: bool, zero_spend_verified: bool)`；`deny_reason(gate: DispatchGate) -> str | None`。云端 Plan 只由 agent 领取；本地 scheduler 可提交队列或执行明确 local-only 任务，不能同时拥有同 Plan。

- [ ] 创建 cancel、过期 lease、计费未知必须阻断测试。

```python
import unittest
from keji.dispatch import DispatchGate, deny_reason

class DispatchTest(unittest.TestCase):
    def test_no_billing_guarantee(self):
        gate = DispatchGate(False, True, True, True, False)
        self.assertEqual(deny_reason(gate), "billing_unverified")
    def test_cancel_wins(self):
        gate = DispatchGate(True, True, True, True, True)
        self.assertEqual(deny_reason(gate), "cancelled")
```

- [ ] `python3 -m unittest tests.test_dispatch -v` 确认失败。
- [ ] 实现纯门禁，再把所有 `start/resume` 调用汇入此入口，不能只给远程路径加锁。

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class DispatchGate:
    cancelled: bool
    lease_valid: bool
    runner_online: bool
    dependencies_ready: bool
    zero_spend_verified: bool

def deny_reason(gate: DispatchGate) -> str | None:
    checks = [(gate.cancelled, "cancelled"), (not gate.lease_valid, "lease_expired"),
              (not gate.runner_online, "runner_offline"),
              (not gate.dependencies_ready, "dependencies_pending"),
              (not gate.zero_spend_verified, "billing_unverified")]
    return next((reason for blocked, reason in checks if blocked), None)
```

启动前获 runner-wide 编码槽文件锁与 canonical workspace 文件锁；SQLite `BEGIN IMMEDIATE` 保存 dispatch owner/attempt/lease/child PID。领取后、真正 spawn 前再查取消/租约；失去 lease 不再启动新命令，已有进程按现有受控停止路径中止并留 checkpoint。重启先 reconcile PID 与 attempt，不盲目再启动。文件锁而非仅 DB 布尔值抵御两个 CLI 进程。
- [ ] 增加两个独立进程竞争同一 temp workspace 的集成测试，mock adapter 计数必须=1；local scheduler + cloud agent 竞争也=1；运行 `python3 -m unittest tests.test_dispatch tests.test_scheduler tests.test_agent tests.test_process tests.test_worktree -v`。
- [ ] 提交 `feat(cli): fence local and remote dispatch through one gate`。

### R3：checkpoint 与自然恢复状态机

**Files:** Create `cli/keji/checkpoints.py`、`cli/tests/test_checkpoints.py`；Modify `agent.py`、`scheduler.py`、`db.py`、`adapters/base.py`、`adapters/claude.py`、`adapters/codex.py`。

**Interfaces:** `Checkpoint` 含 plan_id、attempt_id、tool_profile_id、provider_session_id、canonical_workspace、git_head、dirty_paths_digest、last_output_offset、completed_criteria、side_effect_summary、reason、schema_version；`resume_allowed(original_profile: str, requested_profile: str, native_resume: bool) -> bool`。checkpoint 以原子写/SQLite事务保存，不保存秘密或整段 CLI 环境。

- [ ] 写跨工具续跑拒绝测试。

```python
import unittest
from keji.checkpoints import resume_allowed

class CheckpointTest(unittest.TestCase):
    def test_resume_keeps_tool(self):
        self.assertTrue(resume_allowed("claude-personal", "claude-personal", True))
        self.assertFalse(resume_allowed("claude-personal", "codex-personal", True))
        self.assertFalse(resume_allowed("claude-personal", "claude-personal", False))
```

- [ ] `python3 -m unittest tests.test_checkpoints -v` 确认失败。
- [ ] 实现函数，并串联现有 adapter resume。所有权限/计费/依赖/工作目录校验在 R2 门禁处执行。

```python
def resume_allowed(original_profile: str, requested_profile: str, native_resume: bool) -> bool:
    return bool(original_profile) and original_profile == requested_profile and native_resume
```

```text
quota-limited → checkpoint durable → waiting_quota event acknowledged
due → fresh sample → available → cloud claim + local gate → native resume
unknown + reliable reset + enforced zero spend + one pool/window probe → resume probe
blocked / second failed probe → retain checkpoint + next_wake_at + jittered backoff
missing session / workspace diverged / auth failed → waiting_input/local_auth
cancelled → invalidate wake generation; no future resume
```

自动续跑关闭时可刷新额度但不能 start；人工继续也受全部门禁限制。原生 session 不存在时，不自动新建“假续跑”。重试事件使用 `(job_id,attempt_id,seq)`；网络补报 outbox 要先去重，不重复累积时间或成果。短时重置但周阻塞、auto-refill 已开启但不可验证禁用、API key 回退可用，都不允许自动执行。
- [ ] 用 fake clock/fake adapter 覆盖上述状态、断网/重启、取消与唤醒并发、连续 quota 错误熔断；运行 `python3 -m unittest discover -s tests -v`。真实工具 smoke 使用专用临时仓库、无发布权限、有限任务，在确认零新增计费且用户批准执行阶段后分别验证 Claude/Codex；不为触发限额故意耗光账号。
- [ ] 提交 `feat(cli): resume quota-blocked plans from durable checkpoints`。

### R4：Cursor / Gemini 能力分级与账号绑定

**Files:** Create `cli/keji/adapters/cursor.py`、`gemini.py`、`cli/tests/test_capabilities.py`；Modify `cli/keji/adapters/__init__.py`、`cli.py`、`credentials.py`、`cloud.py`、`cli/README.md`。

**Interfaces:** adapter 输出总计划 Capabilities；`safe_capabilities() -> dict[str,bool]` 提供管理模式默认值。用户在本机明确选择 profile，将其绑定到 Valley 用户下 opaque account pool；同账号多机器绑定需用户确认，不凭邮箱字符串自动合并。

- [ ] 测试默认不能宣称派发或付费保障。

```python
import unittest
from keji.adapters.cursor import safe_capabilities

class CapabilitiesTest(unittest.TestCase):
    def test_management_only_default(self):
        result = safe_capabilities()
        self.assertTrue(result["can_record"])
        self.assertFalse(result["can_dispatch"])
        self.assertFalse(result["can_enforce_zero_spend"])
```

- [ ] `python3 -m unittest tests.test_capabilities -v` 确认失败。
- [ ] 为两个 adapter 分别提供同样保守默认；运行路径根据真实能力开放，不伪造 start/resume 命令。

```python
def safe_capabilities() -> dict[str, bool]:
    return {"can_record": True, "can_read_quota": False, "can_dispatch": False,
            "can_resume": False, "can_enforce_zero_spend": False}
```

适配阶段逐工具检查官方接口/已安装 CLI 的 help、版本及认证方式，保存去敏 fixture 和验证日期；月/日/模型池不折算五小时。无法证明恢复或计费安全则交付“记录/提醒”能力，页面明确待适配。不要求自动登录、不读取整机无关凭据。
- [ ] `python3 -m unittest tests.test_capabilities tests.test_credentials tests.test_cloud -v`；再完整跑 unittest discover；核对 capability unknown/offline/stale 三种投影。
- [ ] 提交 `feat(cli): expose capability-tiered multi-tool profiles`。

## 完成门

真实自动续跑能力需 R1–R3 + Valley V3 的端到端证据，单纯 adapter 有 resume 方法不等于支持。Cursor/Gemini 的管理模式可以先交付，不阻塞 Claude/Codex 闭环；未验证项必须保持 false。
