# 刻迹 0.1 核心流程 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 iPhone ↔ Valley ↔ Mac `keji agent` 的三条流程在真机上跑通：配对后看到套餐/用量/重置时刻，手机派发指令到指定工具并看到结果，手机为指令指定执行时间。

**Architecture:** 三端各改一层，契约以 spec §4.4 为准。Valley 去掉配对的 10 分钟规则、按心跳算在线、闸门只拦 `blocked`、任务加 `not_before` 与 `output_tail`、工具清单加 `plan_tier`。CLI 修样本权威标记与工具 id、采集套餐等级与 Claude 用量、按固定节奏上报、回传输出尾巴。iOS 解码新字段、把额度卡片改成「套餐 + 绝对重置时刻」、派发面板加执行时间、执行记录显示输出尾巴、配对错误可读。

**Tech Stack:** Go 1.22 + gin + gorm + PostgreSQL（Valley，`make test`）；Python 3.9 标准库（CLI，`python3 -m unittest discover -s tests`）；SwiftUI iOS 17 零依赖（`xcodegen generate` + `xcodebuild test`）。

**Spec:** `docs/superpowers/specs/2026-09-25-keji-0-1-core-flow-design.md`

## Global Constraints

- 仓库：TimeTrace 在 `/opt/coding/planb/github/TimeTrace`（分支 `feature/ios-app`），Valley 在 `/opt/coding/planb/github/Valley`（分支 `codex/keji-ai-workspace-fixes`；发布走 `release/timetrace-ai-workspace`）。Valley 模块目录 `internal/apps/timetrace/`，API 前缀 `/timetrace/api/v1`。
- CLI 只能用 Python 3.9 标准库；不得引入第三方包。凭据文件只读取需要的字段，**任何日志、样本、清单、异常信息里都不得出现 token、邮箱、环境变量**。
- iOS：SwiftUI，iOS 17+，零第三方依赖；改完 `project.yml` 或新增文件后必须 `xcodegen generate`。用户可见文案一律简体中文。
- Valley：schema 变更靠 `AutoMigrate`（`repository.go:40`），新增列必须带 `default`，让老行可读。错误码沿用 `app.go:435-452`（40100 / 40300 / 40400 / 40900 / 41000 / 42200）。
- 可用性三态在服务端和 CLI 的值是 `available` / `blocked` / `unknown`（spec 里的「已耗尽」= `blocked`，不改值名）。
- 零付费校验（`billing_unverified`、`can_enforce_zero_spend`）一律不动。
- 构建号：iOS `CURRENT_PROJECT_VERSION` 从 `2026092501` 起按 `yyyyMMdd` + 两位序号编；`MARKETING_VERSION` 保持 `0.1.0`。
- 每个任务：先写失败测试，跑红，再实现，跑绿，提交。提交信息结尾加 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`。

## Review Focus

1. **Claude 访问令牌过期或用量接口 401** — 期望：本轮跳过，不上报任何样本，工具卡片显示「未知 · 上次成功采集 X 前」，派发不受阻。测试在 Task 11。
2. **`~/.codex/auth.json` 缺失或 id_token 不是合法 JWT** — 期望：`plan_tier` 为空字符串，工具仍正常注册和派发。测试在 Task 10。
3. **`not_before` 因网络延迟到达时已略早于服务器时间** — 期望：2 分钟内的「过去」视为立即执行而不是 422；早于 2 分钟或晚于 30 天才拒绝。测试在 Task 6。
4. **输出尾巴含非 UTF-8 字节或超长** — 期望：CLI 截到 8000 字节内并用替换字符解码，服务端校验 ≤ 8192 字节且是合法 UTF-8，超出返回 422 而不是 500。测试在 Task 7 和 Task 13。
5. **Mac 心跳停了但队列里还有任务** — 期望：手机 2 分钟后显示离线、派发面板选不到它，已排队任务保持 `queued`，Mac 回来后第一次轮询即被领取。测试在 Task 3（心跳恢复后 claim 成功即覆盖「回来后被领取」）。

---

## Phase 0 · 探测

### Task 1: 在用户 Mac 上探测 Claude 用量接口与两个套餐字段

**Files:**
- Create: `docs/superpowers/notes/2026-09-25-claude-usage-probe.md`

**Interfaces:**
- Produces: 探测结论文档，决定 Task 11 走 11A（用量接口）还是 11B（statusline 回退）；确认 Task 10 两个字段名。

- [ ] **Step 1: 只读探测 Codex 套餐字段**

```sh
python3 - <<'EOF'
import json, base64, pathlib
doc = json.loads(pathlib.Path.home().joinpath(".codex/auth.json").read_text())
tok = (doc.get("tokens") or {}).get("id_token") or ""
p = tok.split(".")[1]; p += "=" * (-len(p) % 4)
claims = json.loads(base64.urlsafe_b64decode(p))
print("keys:", sorted(claims.keys()))
print("plan:", (claims.get("https://api.openai.com/auth") or {}).get("chatgpt_plan_type"))
EOF
```
只打印字段名与 plan 值，不打印 token。

- [ ] **Step 2: 只读探测 Claude 套餐字段与用量接口**

```sh
python3 - <<'EOF'
import json, pathlib, urllib.request
doc = json.loads(pathlib.Path.home().joinpath(".claude/.credentials.json").read_text())
oauth = doc.get("claudeAiOauth") or {}
print("oauth keys:", sorted(oauth.keys()))
print("subscriptionType:", oauth.get("subscriptionType"))
req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage")
req.add_header("Authorization", "Bearer " + oauth["accessToken"])
req.add_header("anthropic-beta", "oauth-2025-04-20")
req.add_header("Accept", "application/json")
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        body = json.loads(r.read())
        print("status 200; top-level keys:", sorted(body.keys()))
        for k, v in body.items():
            if isinstance(v, dict): print(k, "->", {kk: vv for kk, vv in v.items()})
except urllib.error.HTTPError as e:
    print("HTTP", e.code, e.read()[:300])
EOF
```

- [ ] **Step 3: 记录结论**

在 `docs/superpowers/notes/2026-09-25-claude-usage-probe.md` 写下：Codex plan 字段路径与示例值；Claude `subscriptionType` 示例值；用量接口的 HTTP 状态、顶层键、每个窗口的字段名（`utilization` 是 0–1 还是 0–100、`resets_at` 格式）。结论一行：「Task 11 走 11A」或「走 11B」。

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/notes/2026-09-25-claude-usage-probe.md
git commit -m "docs: record the Claude usage endpoint and plan tier probe"
```

---

## Phase A · Valley

所有 Go 测试用 `cd /opt/coding/planb/github/Valley && make test`（或 `go test ./internal/apps/timetrace/ -run <Name> -count=1`）。集成测试需要本地 PostgreSQL（`docker compose up -d`，见 Valley `CLAUDE.md`）。测试助手：`newTestApp`、`loginUser`（`plan_integration_test.go:615`）、`seedRunnerSession`（`quota_integration_test.go:14`）、`requestJSON`、`decodeEnvelopeData`。

### Task 2: 批准 Runner 不再要求 10 分钟内登录，配对错误码稳定

**Files:**
- Modify: `internal/apps/timetrace/remote.go:144-158`（`recentFormalUser`）、`remote.go:90-142`（Approve / Inspect 的错误分支）
- Test: `internal/apps/timetrace/remote_integration_test.go`

**Interfaces:**
- Produces: `POST /device-authorizations/approve|inspect` 对未知码 404（40400）、过期码 410（41000）、已用过的码 409（40900）、游客 403（40300）；登录任意时长后仍可批准。

- [ ] **Step 1: 写失败测试**

```go
func TestPairingWorksLongAfterLoginAndReportsStableErrors(t *testing.T) {
	h := newTestApp(t)
	sess, _ := loginUser(t, h, "pair.later@example.com")
	// 登录已经过去一小时：以前这里会 401。
	if err := h.db.Model(&SessionFamily{}).Where("access_hash = ?", hash(sess.AccessToken)).
		Update("authenticated_at", time.Now().UTC().Add(-time.Hour)).Error; err != nil {
		t.Fatal(err)
	}
	created := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/device-authorizations",
		map[string]any{"device_name": "Late Mac", "platform": "darwin", "client_version": "0.5.0"}, "")
	var auth DeviceAuthorizationResponse
	decodeEnvelopeData(t, created, &auth)
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/device-authorizations/inspect", map[string]string{"user_code": auth.UserCode}, sess.AccessToken); got.Code != http.StatusOK {
		t.Fatalf("inspect after 1h: %d %s", got.Code, got.Body.String())
	}
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/device-authorizations/approve", map[string]string{"user_code": auth.UserCode}, sess.AccessToken); got.Code != http.StatusOK {
		t.Fatalf("approve after 1h: %d %s", got.Code, got.Body.String())
	}
	// 同一个码再批一次：已使用 → 409。
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/device-authorizations/approve", map[string]string{"user_code": auth.UserCode}, sess.AccessToken); got.Code != http.StatusConflict {
		t.Fatalf("reuse: %d %s", got.Code, got.Body.String())
	}
	// 不存在的码 → 404。
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/device-authorizations/inspect", map[string]string{"user_code": "ZZZZZZZZ"}, sess.AccessToken); got.Code != http.StatusNotFound {
		t.Fatalf("unknown code: %d %s", got.Code, got.Body.String())
	}
	// 过期的码 → 410。
	expired := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/device-authorizations",
		map[string]any{"device_name": "Old Mac", "platform": "darwin", "client_version": "0.5.0"}, "")
	var old DeviceAuthorizationResponse
	decodeEnvelopeData(t, expired, &old)
	if err := h.db.Model(&DeviceAuthorization{}).Where("user_code_hash = ?", h.app.repository.pairingCodeHash(old.UserCode)).
		Update("expires_at", time.Now().UTC().Add(-time.Minute)).Error; err != nil {
		t.Fatal(err)
	}
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/device-authorizations/approve", map[string]string{"user_code": old.UserCode}, sess.AccessToken); got.Code != http.StatusGone {
		t.Fatalf("expired code: %d %s", got.Code, got.Body.String())
	}
	// 游客 → 403。
	var guest Session
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodPost, apiPrefix+"/auth/guest", nil, ""), &guest)
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/device-authorizations/approve", map[string]string{"user_code": old.UserCode}, guest.AccessToken); got.Code != http.StatusForbidden {
		t.Fatalf("guest: %d %s", got.Code, got.Body.String())
	}
}
```
若 `pairingCodeHash` 不是 user code 的哈希函数，读 `remote.go:61-87` 找出建码时用的哈希并替换。

- [ ] **Step 2: 跑红** — `go test ./internal/apps/timetrace/ -run TestPairingWorksLongAfterLogin -count=1`，期望 inspect after 1h 返回 401。

- [ ] **Step 3: 实现**

`recentFormalUser` 改为：
```go
// formalUser: any logged-in (non-guest) session may approve a Runner. The
// former "authenticated within 10 minutes" rule blocked every real pairing
// because token refresh never renewed authenticated_at.
func (r *Repository) formalUser(ctx context.Context, access string) (User, error) {
	user, err := userForAccess(r.db.WithContext(ctx), access)
	if err != nil {
		return User{}, err
	}
	if user.IsGuest {
		return User{}, ErrForbidden
	}
	return user, nil
}
```
把 Approve / Inspect 里对 `recentFormalUser` 的调用改成 `formalUser`。然后读 `remote.go:90-142`，保证错误分支为：码查不到 → `ErrNotFound`；`now.After(row.ExpiresAt)` → `ErrExpired`；`row.Status != "pending"` → `ErrConflict`。缺哪个补哪个。

- [ ] **Step 4: 跑绿** — 同上命令，PASS；再跑 `go test ./internal/apps/timetrace/ -count=1` 确认现有配对测试仍过。

- [ ] **Step 5: Commit**

```bash
git add internal/apps/timetrace/remote.go internal/apps/timetrace/remote_integration_test.go
git commit -m "fix(timetrace): approve runners from any logged-in session and return stable pairing errors"
```

### Task 3: Runner 在线状态由心跳推导

**Files:**
- Modify: `internal/apps/timetrace/remote.go:423-446`（`ListRunners`）、`plans.go:773-836`（`evaluateExecutionEligibility` 的 `runner_offline` 判断）
- Create: helper `runnerPresence` in `remote.go`
- Test: `internal/apps/timetrace/remote_integration_test.go`

**Interfaces:**
- Produces: `GET /runners` 的 `runner.status` 为 `online` 当且仅当 `last_seen_at` 在 `runnerLivenessTTL`（2 分钟）内且未撤销；闸门用同一函数。

- [ ] **Step 1: 写失败测试**

```go
func TestRunnerPresenceFollowsHeartbeat(t *testing.T) {
	h := newTestApp(t)
	sess, user := loginUser(t, h, "presence@example.com")
	seedRunnerSession(t, h, user, "r-hb", "runner-token-hb")
	stale := time.Now().UTC().Add(-3 * time.Minute)
	if err := h.db.Model(&Runner{}).Where("id = ?", "r-hb").Updates(map[string]any{"status": "online", "last_seen_at": stale}).Error; err != nil {
		t.Fatal(err)
	}
	var runners []RunnerInventory
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodGet, apiPrefix+"/runners", nil, sess.AccessToken), &runners)
	if len(runners) != 1 || runners[0].Runner.Status != "offline" {
		t.Fatalf("stale heartbeat must read offline: %+v", runners)
	}
	// 一次领活轮询就是一次心跳。
	requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/jobs/claim", map[string]any{"wait_seconds": 0}, "runner-token-hb")
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodGet, apiPrefix+"/runners", nil, sess.AccessToken), &runners)
	if runners[0].Runner.Status != "online" {
		t.Fatalf("fresh heartbeat must read online: %+v", runners[0].Runner)
	}
}
```

- [ ] **Step 2: 跑红** — `-run TestRunnerPresenceFollowsHeartbeat`，期望第一段断言失败（读到 `online`）。

- [ ] **Step 3: 实现**

`remote.go` 新增：
```go
// runnerPresence derives online/offline from the heartbeat that claim polling
// and inventory uploads leave in last_seen_at. Nothing persists "offline".
func runnerPresence(r Runner, now time.Time) string {
	if r.RevokedAt != nil || r.LastSeenAt == nil || !r.LastSeenAt.After(now.Add(-runnerLivenessTTL)) {
		return "offline"
	}
	return "online"
}
```
`ListRunners` 取到 `runners` 后：
```go
now := time.Now().UTC()
for i := range runners {
	runners[i].Status = runnerPresence(runners[i], now)
}
```
`evaluateExecutionEligibility` 里把
```go
if runner.ID == "" || runner.RevokedAt != nil || runner.Status != "online" || runner.LastSeenAt == nil || !runner.LastSeenAt.After(now.Add(-runnerLivenessTTL)) {
```
改为
```go
if runner.ID == "" || runnerPresence(runner, now) != "online" {
```

- [ ] **Step 4: 跑绿** — 目标测试 PASS；全模块测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add internal/apps/timetrace/remote.go internal/apps/timetrace/plans.go internal/apps/timetrace/remote_integration_test.go
git commit -m "fix(timetrace): derive runner presence from heartbeat instead of a sticky status"
```

### Task 4: 工具清单与额度池带套餐等级 `plan_tier`

**Files:**
- Modify: `internal/apps/timetrace/remote_model.go`（`RunnerTool`）、`remote.go:374-421`（`UpdateRunnerInventory` 校验）、`quota_model.go`（`AccountQuotaPool`）、`quota.go:292-337`（`accountQuotaForUser`）
- Test: `internal/apps/timetrace/quota_integration_test.go`

**Interfaces:**
- Produces: `RunnerTool.PlanTier string json:"plan_tier"`（≤ 40 字符，可空）；`AccountQuotaPool.PlanTier string json:"plan_tier"`。

- [ ] **Step 1: 写失败测试**

```go
func TestPlanTierFlowsFromInventoryToQuotaPools(t *testing.T) {
	h := newTestApp(t)
	ctx := context.Background()
	sess, user := loginUser(t, h, "tier@example.com")
	seedRunnerSession(t, h, user, "r-tier", "runner-token-tier")
	inventory := map[string]any{
		"workspaces": []map[string]any{{"id": "ws1", "name": "Repo", "default_branch": "main"}},
		"tools": []map[string]any{{"id": "claude-default", "provider": "claude", "version": "local", "status": "available", "can_enforce_zero_spend": true, "plan_tier": "max"}},
	}
	if got := requestJSON(t, h.router, http.MethodPut, apiPrefix+"/runner/inventory", inventory, "runner-token-tier"); got.Code != http.StatusOK {
		t.Fatalf("inventory: %d %s", got.Code, got.Body.String())
	}
	var runners []RunnerInventory
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodGet, apiPrefix+"/runners", nil, sess.AccessToken), &runners)
	if runners[0].Tools[0].PlanTier != "max" {
		t.Fatalf("plan_tier not stored: %+v", runners[0].Tools)
	}
	now := time.Now().UTC()
	used := 12.0
	if _, err := h.app.repository.IngestQuotaSamples(ctx, "runner-token-tier", []QuotaSampleInput{{
		SampleID: "t1", PoolID: "pool-claude", ProfileID: "claude-default", LimitID: "claude", WindowMins: 300,
		PoolAuthoritative: true, Scope: "five_hour", Kind: "claude", UsedPercent: &used,
		ObservedAt: now, ExpiresAt: now.Add(time.Hour), Source: "runner", Confidence: "exact"}}); err != nil {
		t.Fatal(err)
	}
	var quota AccountQuotaResponse
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodGet, apiPrefix+"/quota", nil, sess.AccessToken), &quota)
	if len(quota.Pools) != 1 || quota.Pools[0].PlanTier != "max" {
		t.Fatalf("pool must carry plan_tier: %+v", quota.Pools)
	}
	// 超长套餐名 → 422。
	inventory["tools"].([]map[string]any)[0]["plan_tier"] = strings.Repeat("x", 41)
	if got := requestJSON(t, h.router, http.MethodPut, apiPrefix+"/runner/inventory", inventory, "runner-token-tier"); got.Code != http.StatusUnprocessableEntity {
		t.Fatalf("long plan_tier accepted: %d", got.Code)
	}
}
```

- [ ] **Step 2: 跑红** — 编译失败（`PlanTier` 未定义）即为红。

- [ ] **Step 3: 实现**

`RunnerTool` 加字段（放在 `Status` 后）：
```go
PlanTier string `gorm:"type:varchar(40);not null;default:''" json:"plan_tier"`
```
`UpdateRunnerInventory` 的 tools 循环里加：
```go
tools[i].PlanTier = strings.ToLower(strings.TrimSpace(tools[i].PlanTier))
if len(tools[i].PlanTier) > 40 {
	return ErrInvalidInput
}
```
`AccountQuotaPool` 加 `PlanTier string `json:"plan_tier"``。读 `accountQuotaForUser`（`quota.go:292-337`）：它按 pool 聚合 `QuotaSample`。在函数内先建映射：
```go
var tools []RunnerTool
if err := r.db.WithContext(ctx).Joins("JOIN tt_runners r ON r.id = tt_runner_tools.runner_id").
	Where("r.user_id = ? AND r.revoked_at IS NULL", userID).Find(&tools).Error; err != nil {
	return AccountQuotaResponse{}, err
}
tier := map[string]string{}
for _, tool := range tools {
	tier[tool.RunnerID+"|"+tool.ID] = tool.PlanTier
}
```
每个 pool 用其最新样本（`latestQuotaSamples` 里 `ObservedAt` 最大的那条）的 `RunnerID+"|"+ProfileID` 查 `tier`，赋给 `pool.PlanTier`。

- [ ] **Step 4: 跑绿**；全模块 PASS。

- [ ] **Step 5: Commit**

```bash
git add internal/apps/timetrace/remote_model.go internal/apps/timetrace/remote.go internal/apps/timetrace/quota_model.go internal/apps/timetrace/quota.go internal/apps/timetrace/quota_integration_test.go
git commit -m "feat(timetrace): carry the tool's plan tier through inventory and quota pools"
```

### Task 5: 闸门只拦 `blocked`，`unknown` 放行；等待中的任务在不再 blocked 时回队列

**Files:**
- Modify: `internal/apps/timetrace/plans.go:822-834`、`remote.go:707-756`（claim 候选循环）、`remote.go:848-866`（`reconcileQuotaGates` 的 switch）
- Test: `internal/apps/timetrace/remote_integration_test.go`

**Interfaces:**
- Produces: 原因串 `quota_blocked`（不再有 `quota_unknown`）；`reserveQuotaProbe` 不再被 claim 调用（函数与表保留，后续清理）。

- [ ] **Step 1: 写失败测试**

```go
// seedDispatchableJob 建一个已登录用户、在线 Runner、可用工具与一条 queued 任务；
// 不上传任何额度样本，所以池的可用性是 unknown。
func seedDispatchableJob(t *testing.T, h *testApp, mail, runnerID, token string) (Session, User, RemoteJobResponse) {
	t.Helper()
	sess, user := loginUser(t, h, mail)
	seedRunnerSession(t, h, user, runnerID, token)
	inventory := map[string]any{
		"workspaces": []map[string]any{{"id": "ws1", "name": "Repo", "default_branch": "main"}},
		"tools":      []map[string]any{{"id": "codex-default", "provider": "codex", "version": "local", "status": "available", "can_enforce_zero_spend": true}},
	}
	if got := requestJSON(t, h.router, http.MethodPut, apiPrefix+"/runner/inventory", inventory, token); got.Code != http.StatusOK {
		t.Fatalf("inventory: %d %s", got.Code, got.Body.String())
	}
	task := seedTask(t, h, user, "task-"+runnerID)
	var job RemoteJobResponse
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodPost, apiPrefix+"/remote-jobs", map[string]any{
		"task_id": task.ID, "runner_id": runnerID, "workspace_id": "ws1", "tool_profile_id": "codex-default",
		"prompt": "hello", "idempotency_key": "k-" + runnerID, "expected_task_revision": task.UpdatedAt.UnixMilli(),
	}, sess.AccessToken), &job)
	return sess, user, job
}

func TestUnknownQuotaDoesNotBlockClaim(t *testing.T) {
	h := newTestApp(t)
	_, _, job := seedDispatchableJob(t, h, "unknown.quota@example.com", "r-unk", "runner-token-unk")
	claimed := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/jobs/claim", map[string]any{"wait_seconds": 0}, "runner-token-unk")
	if claimed.Code != http.StatusOK {
		t.Fatalf("claim with unknown quota must lease: %d %s", claimed.Code, claimed.Body.String())
	}
	var claim RemoteClaimResponse
	decodeEnvelopeData(t, claimed, &claim)
	if claim.Job.ID != job.ID || claim.Job.Status != "leased" {
		t.Fatalf("unexpected claim: %+v", claim)
	}
}

func TestBlockedQuotaParksUntilTheSampleExpires(t *testing.T) {
	h := newTestApp(t)
	ctx := context.Background()
	sess, _, job := seedDispatchableJob(t, h, "blocked.quota@example.com", "r-blk", "runner-token-blk")
	now := time.Now().UTC()
	full := 100.0
	reset := now.Add(90 * time.Second)
	if _, err := h.app.repository.IngestQuotaSamples(ctx, "runner-token-blk", []QuotaSampleInput{{
		SampleID: "b1", PoolID: "pool-codex", ProfileID: "codex-default", LimitID: "codex", WindowMins: 300,
		PoolAuthoritative: true, Scope: "primary", Kind: "codex", UsedPercent: &full, ResetAt: &reset,
		ObservedAt: now, ExpiresAt: reset, Source: "runner", Confidence: "exact"}}); err != nil {
		t.Fatal(err)
	}
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/jobs/claim", map[string]any{"wait_seconds": 0}, "runner-token-blk"); got.Code != http.StatusNotFound {
		t.Fatalf("blocked pool must not lease: %d %s", got.Code, got.Body.String())
	}
	var parked RemoteJobResponse
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodGet, apiPrefix+"/remote-jobs/"+job.ID, nil, sess.AccessToken), &parked)
	if parked.Status != "waiting_quota" {
		t.Fatalf("expected waiting_quota, got %s", parked.Status)
	}
	// 样本到了重置时刻即过期 → unknown → 回队列并可领取。
	if err := h.db.Model(&QuotaSample{}).Where("sample_id = ?", "b1").Update("expires_at", now.Add(-time.Second)).Error; err != nil {
		t.Fatal(err)
	}
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/jobs/claim", map[string]any{"wait_seconds": 0}, "runner-token-blk"); got.Code != http.StatusOK {
		t.Fatalf("expired block must lease again: %d %s", got.Code, got.Body.String())
	}
}
```
若 `seedTask` 签名不同（见 `plan_integration_test.go:632`），按其实际签名调整。

- [ ] **Step 2: 跑红** — 第一个测试期望 claim 返回 404（被 `quota_unknown` 挡住）。

- [ ] **Step 3: 实现**

`evaluateExecutionEligibility` 末尾改为：
```go
if quota.Availability == "blocked" {
	add("quota_blocked")
}
```
claim 候选循环改为：
```go
for _, candidate := range candidates {
	if candidate.DesiredAction == "cancel" || candidate.PlanID == nil {
		continue
	}
	eligibility, err := executionEligibilityForJob(tx, candidate, now)
	if err != nil {
		return err
	}
	if len(eligibility.Reasons) > 0 {
		continue
	}
	job = candidate
	break
}
```
（删除 `blocked/unknown` 双标志、`planAllowsAutoResume` 探测分支与 `reserveQuotaProbe` 调用。）
`reconcileQuotaGates` 的 switch 改为：
```go
case job.Status == "queued" && avail == "blocked":
	updates["status"] = "waiting_quota"
case job.Status == "waiting_quota" && avail != "blocked":
	if ok, err := planAllowsAutoResume(tx, job.UserID, job.PlanID); err != nil {
		return err
	} else if !ok {
		continue
	}
	updates["status"] = "queued"
	updates["probe_reset_at"] = nil
```
然后 `grep -rn "quota_unknown" internal/` 与 TimeTrace 的 `ios/`、`cli/`：Valley 内改为 `quota_blocked` 语义或删除；iOS 若把 `quota_unknown` 映射成文案，改成对 `quota_blocked` 显示「额度已用尽，等待重置」。修正因此变红的旧测试（它们断言 unknown 会阻塞，与新契约冲突，按新契约改断言）。

- [ ] **Step 4: 跑绿**；全模块 PASS。

- [ ] **Step 5: Commit**

```bash
git add internal/apps/timetrace/
git commit -m "feat(timetrace): only a blocked pool parks a job; unknown quota no longer stalls dispatch"
```

### Task 6: 任务的 `not_before`

**Files:**
- Modify: `internal/apps/timetrace/remote_model.go`（`RemoteJob`、`RemoteJobResponse`）、`remote.go:42-51`（`CreateRemoteJobRequest`）、`remote.go:447-570`（校验、摘要、过期时刻）、`remote.go:707-712`（候选查询）、`remote.go:809-878`（reconcile 跳过未到时刻）、`remote.go:1204-1215`（响应）
- Test: `internal/apps/timetrace/remote_integration_test.go`

**Interfaces:**
- Produces: 请求 `not_before`（RFC 3339，可空）；响应 `not_before`；服务端规则：`< now-2m` 或 `> now+30d` → 422；`[now-2m, now)` 视为立即；`expires_at = max(now, not_before) + 7d`。

- [ ] **Step 1: 写失败测试**

```go
func TestNotBeforeDefersClaimUntilDue(t *testing.T) {
	h := newTestApp(t)
	sess, user := loginUser(t, h, "notbefore@example.com")
	seedRunnerSession(t, h, user, "r-nb", "runner-token-nb")
	inventory := map[string]any{
		"workspaces": []map[string]any{{"id": "ws1", "name": "Repo", "default_branch": "main"}},
		"tools":      []map[string]any{{"id": "codex-default", "provider": "codex", "version": "local", "status": "available", "can_enforce_zero_spend": true}},
	}
	requestJSON(t, h.router, http.MethodPut, apiPrefix+"/runner/inventory", inventory, "runner-token-nb")
	task := seedTask(t, h, user, "task-nb")
	due := time.Now().UTC().Add(2 * time.Minute).Truncate(time.Second)
	body := map[string]any{
		"task_id": task.ID, "runner_id": "r-nb", "workspace_id": "ws1", "tool_profile_id": "codex-default",
		"prompt": "later", "idempotency_key": "k-nb", "expected_task_revision": task.UpdatedAt.UnixMilli(),
		"not_before": due.Format(time.RFC3339),
	}
	created := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/remote-jobs", body, sess.AccessToken)
	if created.Code != http.StatusCreated {
		t.Fatalf("create: %d %s", created.Code, created.Body.String())
	}
	var job RemoteJobResponse
	decodeEnvelopeData(t, created, &job)
	if job.NotBefore == nil || !job.NotBefore.Equal(due) || job.Status != "queued" {
		t.Fatalf("not_before not echoed: %+v", job)
	}
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/jobs/claim", map[string]any{"wait_seconds": 0}, "runner-token-nb"); got.Code != http.StatusNotFound {
		t.Fatalf("must not lease before due: %d %s", got.Code, got.Body.String())
	}
	// 到点：把 not_before 拨到过去。
	if err := h.db.Model(&RemoteJob{}).Where("id = ?", job.ID).Update("not_before", time.Now().UTC().Add(-time.Second)).Error; err != nil {
		t.Fatal(err)
	}
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/jobs/claim", map[string]any{"wait_seconds": 0}, "runner-token-nb"); got.Code != http.StatusOK {
		t.Fatalf("must lease once due: %d %s", got.Code, got.Body.String())
	}
	// 太早 / 太晚 → 422；略早（时钟偏差）→ 接受为立即。
	for _, tc := range []struct {
		name string
		at   time.Time
		code int
	}{
		{"too old", time.Now().UTC().Add(-3 * time.Minute), http.StatusUnprocessableEntity},
		{"too far", time.Now().UTC().Add(31 * 24 * time.Hour), http.StatusUnprocessableEntity},
		{"slightly past", time.Now().UTC().Add(-30 * time.Second), http.StatusCreated},
	} {
		other := seedTask(t, h, user, "task-nb-"+strings.ReplaceAll(tc.name, " ", ""))
		b := map[string]any{
			"task_id": other.ID, "runner_id": "r-nb", "workspace_id": "ws1", "tool_profile_id": "codex-default",
			"prompt": "x", "idempotency_key": "k-" + tc.name, "expected_task_revision": other.UpdatedAt.UnixMilli(),
			"not_before": tc.at.Format(time.RFC3339),
		}
		if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/remote-jobs", b, sess.AccessToken); got.Code != tc.code {
			t.Fatalf("%s: %d %s", tc.name, got.Code, got.Body.String())
		}
	}
}
```

- [ ] **Step 2: 跑红** — 编译失败（`NotBefore` 未定义）。

- [ ] **Step 3: 实现**

`RemoteJob` 加 `NotBefore *time.Time `gorm:"index"``；`RemoteJobResponse` 加 `NotBefore *time.Time `json:"not_before,omitempty"``；`CreateRemoteJobRequest` 加 `NotBefore *time.Time `json:"not_before"``。
`CreateRemoteJob` 在字段校验后：
```go
now := time.Now().UTC()
if req.NotBefore != nil {
	nb := req.NotBefore.UTC()
	if nb.Before(now.Add(-2*time.Minute)) || nb.After(now.Add(30*24*time.Hour)) {
		return RemoteJobResponse{}, false, ErrInvalidInput
	}
	if !nb.After(now) {
		req.NotBefore = nil // arrived late: run now
	} else {
		req.NotBefore = &nb
	}
}
```
摘要：把 `digest` 的 parts 改成切片，`if req.NotBefore != nil { parts = append(parts, req.NotBefore.Format(time.RFC3339)) }`，`legacyDigest` 不变。
建 job：`NotBefore: req.NotBefore`；`ExpiresAt`：`base := now; if req.NotBefore != nil && req.NotBefore.After(base) { base = *req.NotBefore }; ExpiresAt: base.Add(remoteJobTTL)`。（后面 `now := time.Now().UTC()` 已存在，删掉重复声明。）
候选查询加条件：
```go
"runner_id = ? AND status IN ? AND expires_at > ? AND (not_before IS NULL OR not_before <= ?)", runner.ID, []string{"queued", "waiting_quota"}, now, now,
```
`reconcileQuotaGates` 循环开头：`if job.NotBefore != nil && job.NotBefore.After(now) { continue }`。
`remoteJobResponse` 加 `NotBefore: job.NotBefore`。

- [ ] **Step 4: 跑绿**；全模块 PASS。

- [ ] **Step 5: Commit**

```bash
git add internal/apps/timetrace/
git commit -m "feat(timetrace): remote jobs accept not_before and are not leased before it"
```

### Task 7: 终态事件带 `output_tail`

**Files:**
- Modify: `internal/apps/timetrace/remote_model.go`（`RemoteJob`、`RemoteJobResponse`）、`remote.go:42-51`（`RemoteEventInput`）、`remote.go:911-1030`（`AppendRemoteEvents`）、`remote.go:1204-1215`
- Test: `internal/apps/timetrace/remote_integration_test.go`

**Interfaces:**
- Produces: 事件字段 `output_tail`（≤ 8192 字节、合法 UTF-8，否则 422）；`GET /remote-jobs/:id` 返回 `output_tail`。

- [ ] **Step 1: 写失败测试**

```go
func TestCompletedEventStoresOutputTail(t *testing.T) {
	h := newTestApp(t)
	sess, _, job := seedDispatchableJob(t, h, "tail@example.com", "r-tail", "runner-token-tail")
	var claim RemoteClaimResponse
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/jobs/claim", map[string]any{"wait_seconds": 0}, "runner-token-tail"), &claim)
	tail := "$ pytest\n3 passed\n"
	events := map[string]any{"job_id": job.ID, "lease_epoch": claim.LeaseEpoch, "events": []map[string]any{
		{"seq": 1, "type": "running", "message": "started"},
		{"seq": 2, "type": "completed", "message": "done", "result_summary": "ok", "output_tail": tail},
	}}
	if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/attempts/"+claim.AttemptID+"/events", events, "runner-token-tail"); got.Code != http.StatusOK {
		t.Fatalf("events: %d %s", got.Code, got.Body.String())
	}
	var stored RemoteJobResponse
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodGet, apiPrefix+"/remote-jobs/"+job.ID, nil, sess.AccessToken), &stored)
	if stored.OutputTail != tail || stored.Status != "awaiting_review" {
		t.Fatalf("tail not stored: %+v", stored)
	}
}

func TestOversizedOrInvalidOutputTailIsRejected(t *testing.T) {
	h := newTestApp(t)
	_, _, job := seedDispatchableJob(t, h, "tail2@example.com", "r-tail2", "runner-token-tail2")
	var claim RemoteClaimResponse
	decodeEnvelopeData(t, requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/jobs/claim", map[string]any{"wait_seconds": 0}, "runner-token-tail2"), &claim)
	for _, bad := range []string{strings.Repeat("a", 8193), "ok\xff"} {
		events := map[string]any{"job_id": job.ID, "lease_epoch": claim.LeaseEpoch, "events": []map[string]any{
			{"seq": 1, "type": "completed", "message": "done", "output_tail": bad},
		}}
		if got := requestJSON(t, h.router, http.MethodPost, apiPrefix+"/runner/attempts/"+claim.AttemptID+"/events", events, "runner-token-tail2"); got.Code != http.StatusUnprocessableEntity {
			t.Fatalf("bad tail accepted: %d %s", got.Code, got.Body.String())
		}
	}
}
```

- [ ] **Step 2: 跑红** — 编译失败。

- [ ] **Step 3: 实现**

`RemoteEventInput` 加 `OutputTail string `json:"output_tail"``；`RemoteJob` 加 `OutputTail string `gorm:"type:text;not null;default:''"``；`RemoteJobResponse` 加 `OutputTail string `json:"output_tail,omitempty"``。
`AppendRemoteEvents` 事件循环里，在 `len(input.Message) > 1000` 检查旁加：
```go
if len(input.OutputTail) > 8192 || !utf8.ValidString(input.OutputTail) {
	return ErrInvalidInput
}
```
（import `unicode/utf8`。）`case "completed"` 与 `case "failed"` 里加 `job.OutputTail = input.OutputTail`。`updates` map 加 `"output_tail": job.OutputTail`。`remoteJobResponse` 加 `OutputTail: job.OutputTail`。

- [ ] **Step 4: 跑绿**；全模块 PASS。

- [ ] **Step 5: Commit**

```bash
git add internal/apps/timetrace/
git commit -m "feat(timetrace): keep the last 8 KB of runner output on terminal events"
```

### Task 8: Valley 全量测试与跨仓库集成测试同步

**Files:**
- Modify: `TimeTrace/tests/integration/test_workspace_flow.py`（新增三个场景）
- Modify（如需）: Valley `internal/apps/timetrace/workspace_flow_integration_test.go`

**Interfaces:**
- Consumes: Task 5/6/7 的契约。

- [ ] **Step 1: 阅读现有集成用例的结构**

`sed -n 60,200p tests/integration/test_workspace_flow.py`，记下：如何登录、建 Runner、上传清单、注入额度样本（`profile_id: "codex-default"`、`pool_authoritative: True`）、创建任务与 job、跑 `Agent.run_once`。

- [ ] **Step 2: 加三个场景（按现有 helper 名改写）**

```python
def test_unknown_quota_still_dispatches(self):
    # 不注入任何额度样本；派发后 Agent 一次 run_once 就应领到并完成。
    job = self.create_job(prompt="unknown quota")
    outcome = self.agent(ExternalAI("complete")).run_once()
    self.assertTrue(outcome.startswith("job "), outcome)
    self.assertEqual(self.get_job(job["id"])["status"], "awaiting_review")

def test_not_before_holds_the_job_until_due(self):
    due = datetime.now(timezone.utc) + timedelta(minutes=5)
    job = self.create_job(prompt="later", not_before=stamp(due))
    self.assertEqual(self.agent(ExternalAI("complete")).run_once(), "idle")
    self.assertEqual(self.get_job(job["id"])["status"], "queued")
    self.assertEqual(self.get_job(job["id"])["not_before"], stamp(due.replace(microsecond=0)))

def test_completed_job_carries_output_tail(self):
    job = self.create_job(prompt="tail")
    self.agent(ExternalAI("complete")).run_once()
    self.assertTrue(self.get_job(job["id"]).get("output_tail"))
```
`create_job` / `get_job` / `agent` 若不存在，按文件里现有的请求写法补成小 helper（用 `urllib.request` 直连 `CONFIG["base_url"]`）。`create_job` 透传 `not_before`。

- [ ] **Step 3: 跑** — `VALLEY_ROOT=/opt/coding/planb/github/Valley sh tests/integration/run.sh`（需要本机 `initdb`/`pg_ctl`）。前两个场景在 CLI Task 13 之前 `output_tail` 会空，第三个场景标 `@unittest.expectedFailure` 直到 Task 13 完成后移除。

- [ ] **Step 4: Commit（两个仓库各一次）**

```bash
cd /opt/coding/planb/github/TimeTrace && git add tests/integration && git commit -m "test(integration): unknown quota dispatches, not_before holds, output_tail returns"
cd /opt/coding/planb/github/Valley && git add internal/apps/timetrace && git commit -m "test(timetrace): align the paired workspace suite with the 0.1 gate semantics"
```

---

## Phase B · CLI

测试命令：`cd /opt/coding/planb/github/TimeTrace/cli && python3 -m unittest discover -s tests -v`。测试用 `KEJI_HOME` 指向临时目录（见 `tests/test_cli.py:setUp`）。

### Task 9: 样本标为权威，工具 id 与注册一致（R1、R2）

**Files:**
- Modify: `cli/keji/agent.py:20-22`
- Test: `cli/tests/test_agent.py`

**Interfaces:**
- Produces: `_default_pool_binding(provider) -> ("pool-<provider>", "<provider>-default", True)`。

- [ ] **Step 1: 写失败测试**（放进 `AgentQuotaTest` 或新建 class）

```python
def test_default_binding_is_authoritative_and_matches_registered_tool_id(self):
    from keji.agent import _default_pool_binding
    self.assertEqual(_default_pool_binding("codex"), ("pool-codex", "codex-default", True))
    with tempfile.TemporaryDirectory() as d:
        db = Database(Path(d) / "keji.db")
        cloud = FakeCloud()
        class Reading(Adapter):
            def read_limits(self):
                return [Sample(bucket_key="codex:codex:primary", tool="codex", used_pct=42.0,
                               reset_at=2000, window_mins=300, source="live")]
        agent = Agent(db, cloud, {"codex": Reading()}, Path(d), lambda: "t")
        agent.report_quota(now=1000.0)
        payload = cloud.quota_posts[0][1][0]
        self.assertEqual(payload["profile_id"], "codex-default")
        self.assertIs(payload["pool_authoritative"], True)
        self.assertEqual(payload["confidence"], "exact")
```

- [ ] **Step 2: 跑红** — `python3 -m unittest tests.test_agent -k authoritative -v`。

- [ ] **Step 3: 实现**

```python
def _default_pool_binding(provider: str):
    """The pool a registered tool draws from. keji reads quota through the same
    login the tool executes with, so the reading identifies that pool: the
    profile id must equal the inventory tool id (`<provider>-default`)."""
    return "pool-" + provider, provider + "-default", True
```
`grep -n pool_authoritative tests/test_agent.py`：把断言「默认绑定非权威」的旧用例改为期望 `True`。

- [ ] **Step 4: 跑绿** — 全部 CLI 测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add cli/keji/agent.py cli/tests/test_agent.py
git commit -m "fix(cli): report quota samples as authoritative under the registered tool id"
```

### Task 10: 采集套餐等级并随工具清单上报

**Files:**
- Create: `cli/keji/tiers.py`
- Modify: `cli/keji/adapters/codex.py`（`CodexAdapter.plan_tier`）、`cli/keji/adapters/claude.py`（`ClaudeAdapter.plan_tier`）、`cli/keji/adapters/base.py`（默认 `plan_tier` 返回 None）、`cli/keji/config.py`（`codex.auth_path`、`claude.credentials_path` 默认 None）、`cli/keji/cli.py:133-155`（抽出 `_runner_tools`）
- Test: `cli/tests/test_tiers.py`（新）、`cli/tests/test_cli.py`

**Interfaces:**
- Produces: `tiers.codex_plan_tier(path) -> Optional[str]`、`tiers.claude_plan_tier(path) -> Optional[str]`；`ToolAdapter.plan_tier() -> Optional[str]`；`cli._runner_tools(cfg, adapters) -> list[dict]`（每项含 `plan_tier`）。

- [ ] **Step 1: 写失败测试** `cli/tests/test_tiers.py`

```python
import base64, json, tempfile, unittest
from pathlib import Path
from keji import tiers


def jwt_with(claims):
    seg = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
    return "hdr." + seg + ".sig"


class TierTest(unittest.TestCase):
    def test_codex_plan_from_id_token(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "auth.json"
            p.write_text(json.dumps({"tokens": {"id_token": jwt_with({"https://api.openai.com/auth": {"chatgpt_plan_type": "Plus"}})}}))
            self.assertEqual(tiers.codex_plan_tier(p), "plus")

    def test_codex_missing_or_malformed_is_none(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(tiers.codex_plan_tier(Path(d) / "missing.json"))
            p = Path(d) / "auth.json"
            p.write_text(json.dumps({"tokens": {"id_token": "not-a-jwt"}}))
            self.assertIsNone(tiers.codex_plan_tier(p))
            p.write_text("{not json")
            self.assertIsNone(tiers.codex_plan_tier(p))

    def test_claude_subscription_type(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / ".credentials.json"
            p.write_text(json.dumps({"claudeAiOauth": {"accessToken": "secret", "subscriptionType": "max"}}))
            self.assertEqual(tiers.claude_plan_tier(p), "max")
            self.assertIsNone(tiers.claude_plan_tier(Path(d) / "nope.json"))
```
并在 `tests/test_cli.py` 的 `test_inventory_uploads_explicit_zero_spend_capability` 旁加：
```python
def test_inventory_uploads_plan_tier(self):
    class TierAdapter:
        def capabilities(self): return {"can_enforce_zero_spend": True}
        def plan_tier(self): return "max"
    payloads = []
    def request(client, method, path, body=None, token=None):
        if path == "/runner/inventory": payloads.append(json.loads(json.dumps(body)))
        return {}
    with patch("keji.cli._adapters", return_value={"claude": TierAdapter()}), \
         patch("keji.cli.SessionManager.token", return_value="t"), \
         patch("keji.cloud.CloudClient.request", new=request), \
         patch("keji.cli.Agent.run_once", return_value="idle"), \
         patch("keji.cli.shutil.which", return_value="/test/claude"):
        code, _, err = self.run_cli("agent", "run", "--once")
    self.assertEqual(code, 0, err)
    self.assertEqual(payloads[0]["tools"][0]["plan_tier"], "max")
```

- [ ] **Step 2: 跑红** — `ModuleNotFoundError: keji.tiers`。

- [ ] **Step 3: 实现** `cli/keji/tiers.py`

```python
"""Subscription tier read from the tools' own local logins.

Only the tier string leaves this module. Tokens are parsed for one claim and
discarded; nothing here logs, returns, or raises with credential material.
"""
import base64
import json
from pathlib import Path
from typing import Any, Dict, Optional


def _jwt_claims(token: str) -> Dict[str, Any]:
    parts = token.split(".")
    if len(parts) < 2:
        return {}
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        claims = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")).decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return {}
    return claims if isinstance(claims, dict) else {}


def _load(path: Path) -> Dict[str, Any]:
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return doc if isinstance(doc, dict) else {}


def _clean(value: Any) -> Optional[str]:
    text = str(value or "").strip().lower()
    return text[:40] or None


def codex_plan_tier(auth_path: Path) -> Optional[str]:
    """`chatgpt_plan_type` from the ID token in ~/.codex/auth.json."""
    tokens = _load(auth_path).get("tokens") or {}
    claims = _jwt_claims(str(tokens.get("id_token") or ""))
    auth = claims.get("https://api.openai.com/auth") or {}
    return _clean(auth.get("chatgpt_plan_type")) if isinstance(auth, dict) else None


def claude_plan_tier(credentials_path: Path) -> Optional[str]:
    """`subscriptionType` from ~/.claude/.credentials.json."""
    oauth = _load(credentials_path).get("claudeAiOauth") or {}
    return _clean(oauth.get("subscriptionType")) if isinstance(oauth, dict) else None
```
按 Task 1 结论调整字段名。`base.py` 的 `ToolAdapter` 加：
```python
def plan_tier(self) -> Optional[str]:
    """Subscription tier for inventory display; None when unknown."""
    return None
```
`CodexAdapter`:
```python
def plan_tier(self) -> Optional[str]:
    path = self.cfg.get("auth_path") or Path.home() / ".codex" / "auth.json"
    return tiers.codex_plan_tier(Path(path))
```
`ClaudeAdapter`:
```python
def plan_tier(self) -> Optional[str]:
    path = self.cfg.get("credentials_path") or Path.home() / ".claude" / ".credentials.json"
    return tiers.claude_plan_tier(Path(path))
```
`config.DEFAULTS["codex"]["auth_path"] = None`、`DEFAULTS["claude"]["credentials_path"] = None`。
`cli.py` 抽出：
```python
def _runner_tools(cfg: Dict[str, Any], adapters: Dict[str, Any]) -> list:
    tools = []
    for name, adapter in adapters.items():
        binary = str(cfg.get(name, {}).get("bin", name))
        tier = adapter.plan_tier() if hasattr(adapter, "plan_tier") else None
        tools.append({
            "id": name + "-default", "provider": name, "version": "local",
            "can_enforce_zero_spend": adapter_capabilities(adapter).get("can_enforce_zero_spend") is True,
            "status": "available" if shutil.which(binary) else "unavailable",
            "plan_tier": tier or "",
        })
    return tools


def _runner_workspaces(db: Database) -> list:
    return [{"id": row["id"], "name": row["name"], "default_branch": row["default_branch"]}
            for row in db.list_workspaces()]
```
`cmd_agent_run` 改用这两个 helper。

- [ ] **Step 4: 跑绿** — 全部 CLI 测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add cli/keji/tiers.py cli/keji/adapters cli/keji/config.py cli/keji/cli.py cli/tests/test_tiers.py cli/tests/test_cli.py
git commit -m "feat(cli): read the Codex and Claude subscription tier and report it with the tool inventory"
```

### Task 11: Claude Code 的主动额度读取

按 Task 1 结论二选一。**11A 为主路**。

#### 11A · 用量接口

**Files:**
- Create: `cli/keji/adapters/claude_usage.py`
- Modify: `cli/keji/adapters/claude.py`（`read_limits`、`capabilities`）
- Test: `cli/tests/test_claude_usage.py`（新）

**Interfaces:**
- Produces: `claude_usage.read_usage(credentials_path, opener, now) -> Optional[List[Sample]]`；`ClaudeAdapter.read_limits()` 返回它；`capabilities()["can_read_quota"]` 在凭据文件存在时为 True。

- [ ] **Step 1: 写失败测试**

```python
import io, json, tempfile, unittest
from pathlib import Path
from urllib.error import HTTPError
from keji.adapters import claude_usage


class FakeResponse(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *a): return False


class ClaudeUsageTest(unittest.TestCase):
    def creds(self, d, expires_ms=4102444800000):
        p = Path(d) / ".credentials.json"
        p.write_text(json.dumps({"claudeAiOauth": {"accessToken": "tok-secret", "expiresAt": expires_ms, "subscriptionType": "max"}}))
        return p

    def test_parses_windows_into_samples(self):
        body = {"five_hour": {"utilization": 12.5, "resets_at": "2026-09-25T10:00:00Z"},
                "seven_day": {"utilization": 40, "resets_at": "2026-09-27T14:00:00Z"}}
        seen = {}
        def opener(request, timeout=0):
            seen["auth"] = request.get_header("Authorization")
            seen["beta"] = request.get_header("Anthropic-beta")
            return FakeResponse(json.dumps(body).encode())
        with tempfile.TemporaryDirectory() as d:
            samples = claude_usage.read_usage(self.creds(d), opener=opener, now=1000)
        self.assertEqual(seen["auth"], "Bearer tok-secret")
        self.assertEqual(seen["beta"], "oauth-2025-04-20")
        by_key = {s.bucket_key: s for s in samples}
        self.assertEqual(by_key["claude:five_hour"].used_pct, 12.5)
        self.assertEqual(by_key["claude:five_hour"].window_mins, 300)
        self.assertEqual(by_key["claude:seven_day"].window_mins, 10080)
        self.assertEqual(by_key["claude:seven_day"].reset_at, 1790517600)
        self.assertTrue(all(s.source == "live" for s in samples))

    def test_missing_credentials_or_401_yields_none_without_leaking(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(claude_usage.read_usage(Path(d) / "none.json", opener=lambda *a, **k: None, now=0))
            def unauthorized(request, timeout=0):
                raise HTTPError(request.full_url, 401, "unauthorized", {}, io.BytesIO(b"{}"))
            self.assertIsNone(claude_usage.read_usage(self.creds(d), opener=unauthorized, now=0))
            def boom(request, timeout=0):
                raise OSError("network down")
            self.assertIsNone(claude_usage.read_usage(self.creds(d), opener=boom, now=0))

    def test_expired_token_is_not_used(self):
        with tempfile.TemporaryDirectory() as d:
            called = []
            self.assertIsNone(claude_usage.read_usage(self.creds(d, expires_ms=1), opener=lambda r, timeout=0: called.append(1), now=10))
            self.assertEqual(called, [])
```
`1790517600` = 2026-09-27T14:00:00Z 的 epoch；若 Task 1 发现 `utilization` 是 0–1 小数，测试改成 `0.125 → 12.5`。

- [ ] **Step 2: 跑红**。

- [ ] **Step 3: 实现** `cli/keji/adapters/claude_usage.py`

```python
"""On-demand Claude Code quota via the OAuth usage endpoint Claude Code's own
/usage command calls. The access token is read from the local credentials file,
sent once, and never stored, logged, or returned."""
import json
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from keji.models import CLAUDE, Sample

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
WINDOWS = (("five_hour", 300), ("seven_day", 7 * 24 * 60))


def _credentials(path: Path) -> Dict[str, Any]:
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    oauth = doc.get("claudeAiOauth") if isinstance(doc, dict) else None
    return oauth if isinstance(oauth, dict) else {}


def _epoch(value: Any) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    try:
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


def read_usage(credentials_path: Path, opener: Callable = urllib.request.urlopen,
               now: Optional[float] = None) -> Optional[List[Sample]]:
    oauth = _credentials(credentials_path)
    token = str(oauth.get("accessToken") or "")
    if not token:
        return None
    expires_ms = oauth.get("expiresAt")
    if expires_ms is not None and now is not None and float(expires_ms) / 1000 <= now:
        return None  # let Claude Code refresh it; never use a stale token
    request = urllib.request.Request(USAGE_URL)
    request.add_header("Authorization", "Bearer " + token)
    request.add_header("anthropic-beta", "oauth-2025-04-20")
    request.add_header("Accept", "application/json")
    request.add_header("User-Agent", "keji-runner")
    try:
        with opener(request, timeout=15) as response:
            doc = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError):
        return None
    samples: List[Sample] = []
    for key, mins in WINDOWS:
        window = doc.get(key) if isinstance(doc, dict) else None
        if not isinstance(window, dict) or window.get("utilization") is None:
            continue
        used = float(window["utilization"])
        samples.append(Sample(bucket_key="claude:" + key, tool=CLAUDE, used_pct=used,
                              reset_at=_epoch(window.get("resets_at")), window_mins=mins,
                              is_representative=(key == "five_hour"), source="live"))
    return samples or None
```
若 Task 1 显示 `utilization` 为 0–1，用 `used = round(float(...) * 100, 2)`。`ClaudeAdapter`：
```python
def _credentials_path(self) -> Path:
    return Path(self.cfg.get("credentials_path") or Path.home() / ".claude" / ".credentials.json")

def read_limits(self) -> Optional[List[Sample]]:
    return claude_usage.read_usage(self._credentials_path(), now=time.time())
```
`capabilities()` 的 `"can_read_quota": self._credentials_path().exists()`。

- [ ] **Step 4: 跑绿**；然后在用户 Mac 上实跑一次：`cd cli && python3 -c "from keji.adapters.claude import ClaudeAdapter; from keji import config; print(ClaudeAdapter(config.load()['claude']).read_limits())"`，应打印两条 Sample。

- [ ] **Step 5: Commit**

```bash
git add cli/keji/adapters/claude_usage.py cli/keji/adapters/claude.py cli/tests/test_claude_usage.py
git commit -m "feat(cli): read Claude Code quota on demand through the OAuth usage endpoint"
```

#### 11B · 回退：上传 statusline 与运行中的样本

仅当 Task 1 判定接口不可用时执行，替代 11A。

- [ ] **Step 1: 写失败测试**（`tests/test_agent.py`）：一个 `ClaudeAdapter` 注入 `local_samples=lambda: [Sample("claude:five_hour", "claude", 30.0, 2000, 300, source="statusline")]`，`report_quota` 后 `cloud.quota_posts` 含该样本且 `source == "statusline"`、`confidence == "estimate"`。
- [ ] **Step 2: 实现**：`ClaudeAdapter.__init__(cfg, billing=None, local_samples=None)`；`read_limits` 返回 `self.local_samples()` 中 `observed` 在 6 小时内的 claude 样本；`cli._adapters` 用 `db.latest_samples()` 组装闭包；`Agent._post_samples` 对 `source == "statusline"` 传 `confidence="estimate"`。
- [ ] **Step 3: 跑绿并提交** `feat(cli): upload statusline-harvested Claude quota as an estimate`。

### Task 12: 上报节奏、成功运行也上报、配对后立即上报、清单变化重推

**Files:**
- Modify: `cli/keji/agent.py`（`Agent.__init__`、`run_once` 末尾、`run_forever`、新 `maintain`）、`cli/keji/agent.py:344-352`（样本上报移到分支之前）、`cli/keji/cli.py:57-77`（`cmd_cloud_login`）、`cli/keji/cli.py:133-155`（`cmd_agent_run`）
- Test: `cli/tests/test_agent.py`、`cli/tests/test_cli.py`

**Interfaces:**
- Produces: `Agent(..., inventory: Callable[[], Tuple[list, list]] = None, quota_interval: float = 300)`；`Agent.maintain(now=None, force=False) -> None`。

- [ ] **Step 1: 写失败测试**

```python
def test_maintain_throttles_quota_and_repushes_changed_inventory(self):
    class Cloud(FakeCloud):
        def __init__(self):
            super().__init__(); self.inventories = []
        def update_inventory(self, token, workspaces, tools):
            self.inventories.append((workspaces, tools)); return {}
    with tempfile.TemporaryDirectory() as d:
        db = Database(Path(d) / "keji.db")
        cloud = Cloud()
        tools = [{"id": "codex-default", "status": "available"}]
        agent = Agent(db, cloud, {"codex": ReadingAdapter()}, Path(d), lambda: "t",
                      inventory=lambda: ([], list(tools)), quota_interval=300)
        agent.maintain(now=1000.0, force=True)
        agent.maintain(now=1100.0)            # within interval: nothing
        agent.maintain(now=1400.0)            # interval elapsed: report again
        self.assertEqual(len(cloud.quota_posts), 2)
        self.assertEqual(len(cloud.inventories), 1)  # unchanged inventory not re-pushed
        tools[0]["status"] = "unavailable"
        agent.maintain(now=1800.0)
        self.assertEqual(len(cloud.inventories), 2)

def test_successful_run_still_uploads_rate_limit_samples(self):
    class SamplingAdapter(Adapter):
        def start(self, prompt, cwd, session_id, log_file, cancel_event=None):
            return RunResult(exit_code=0, ok=True, output="done", session_id="s",
                             samples=[Sample(bucket_key="claude:five_hour", tool="claude", used_pct=55.0, reset_at=None, window_mins=300)])
    with tempfile.TemporaryDirectory() as d:
        db = Database(Path(d) / "keji.db")
        repo = Path(d) / "repo"; init_repo(repo)
        db.upsert_workspace("ws1", "repo", str(repo), "main")
        cloud = FakeCloud()
        agent = Agent(db, cloud, {"codex": SamplingAdapter()}, Path(d), lambda: "t",
                      prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
        self.assertEqual(agent.run_once(), "job j1 → awaiting_review")
        self.assertEqual(cloud.quota_posts[0][1][0]["used_percent"], 55.0)
```
`ReadingAdapter` 用文件里已有的那个（`read_limits` 返回一条样本）。`test_cli.py` 加：`cmd_cloud_login` 在 `activate` 成功后调用了 `update_inventory` 与 `post_quota_samples`（patch `CloudClient.request` 记录路径，patch `poll_device_authorization` 直接返回 approved）。

- [ ] **Step 2: 跑红**。

- [ ] **Step 3: 实现**

`Agent.__init__` 加参数 `inventory=None, quota_interval: float = 300`，保存 `self._inventory`, `self.quota_interval`, `self._last_quota = 0.0`, `self._last_inventory = None`。新增：
```python
def maintain(self, now: float = None, force: bool = False) -> None:
    """Periodic upkeep between claims: refresh quota and re-push the tool
    inventory when it changed (a tool logged out, a workspace was added)."""
    now = now if now is not None else time.time()
    if not force and now - self._last_quota < self.quota_interval:
        return
    self._last_quota = now
    try:
        self.report_quota(now)
    except Exception:
        pass
    if self._inventory is None:
        return
    try:
        current = self._inventory()
    except Exception:
        return
    if current != self._last_inventory:
        try:
            self.cloud.update_inventory(self.access_token(), *current)
            self._last_inventory = current
        except Exception:
            pass
```
`run_once` 末尾（每个 `return "job ... → ..."` 之前）调用 `self.maintain(force=True)`；`run_forever` 的 idle 分支把 `self.report_quota()` 换成 `self.maintain()`。样本上报：把 `if result.samples: self._post_samples(...)` 从 `elif result.blocked` 分支移到 `if result.ok` 之前，对所有结果执行。
`cmd_agent_run`：`Agent(..., inventory=lambda: (_runner_workspaces(db), _runner_tools(cfg, adapters)))`；`--once` 分支在 `run_once` 后调用 `agent.maintain(force=True)`。
`cmd_cloud_login` 开头改为 `home, cfg, db = _open(args)`，在 `CredentialStore().save(credentials)` 后：
```python
try:
    adapters = _adapters(cfg)
    token = credentials["access_token"]
    cloud.update_inventory(token, _runner_workspaces(db), _runner_tools(cfg, adapters))
    Agent(db, cloud, adapters, home, lambda: token).report_quota()
    print("已上报工具清单与额度，手机上几秒内可见")
except Exception as exc:
    print("绑定成功，但首次上报失败：%s（Runner 启动后会重试）" % exc.__class__.__name__)
```

- [ ] **Step 4: 跑绿** — 全部 CLI 测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add cli/keji/agent.py cli/keji/cli.py cli/tests
git commit -m "feat(cli): report quota on a schedule, after every run and right after pairing; re-push changed inventory"
```

### Task 13: 终态事件带输出尾巴

**Files:**
- Modify: `cli/keji/process.py`（新 `tail_text`）、`cli/keji/agent.py:340-372`
- Test: `cli/tests/test_process.py`、`cli/tests/test_agent.py`

**Interfaces:**
- Produces: `process.tail_text(path, limit=8000) -> str`；completed / failed 事件含 `output_tail`。

- [ ] **Step 1: 写失败测试**

```python
# tests/test_process.py
def test_tail_text_keeps_last_bytes_and_replaces_invalid_utf8(self):
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "log"
        p.write_bytes(b"first line\n" + b"x" * 9000 + b"\nlast \xff line\n")
        tail = tail_text(p, limit=100)
        self.assertLessEqual(len(tail.encode("utf-8")), 8192)
        self.assertTrue(tail.endswith("last � line\n"))
        self.assertNotIn("first line", tail)
        self.assertEqual(tail_text(Path(d) / "missing", limit=100), "")

# tests/test_agent.py
def test_completed_event_carries_output_tail(self):
    class Writing(Adapter):
        def start(self, prompt, cwd, session_id, log_file, cancel_event=None):
            Path(log_file).write_text("step 1\nstep 2\n")
            return RunResult(exit_code=0, ok=True, output="ok", session_id="s")
    with tempfile.TemporaryDirectory() as d:
        db = Database(Path(d) / "keji.db")
        repo = Path(d) / "repo"; init_repo(repo)
        db.upsert_workspace("ws1", "repo", str(repo), "main")
        cloud = FakeCloud()
        agent = Agent(db, cloud, {"codex": Writing()}, Path(d), lambda: "t",
                      prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
        agent.run_once()
        completed = [e for e in cloud.events if e["type"] == "completed"][0]
        self.assertEqual(completed["output_tail"], "step 1\nstep 2\n")
```

- [ ] **Step 2: 跑红**。

- [ ] **Step 3: 实现** `process.py`：
```python
def tail_text(path, limit: int = 8000) -> str:
    """Last `limit` bytes of a log as text; invalid UTF-8 is replaced, and a
    partial first line is dropped so the tail starts at a line boundary."""
    try:
        with open(path, "rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            fh.seek(max(0, size - limit))
            data = fh.read()
    except OSError:
        return ""
    if size > limit and b"\n" in data:
        data = data.split(b"\n", 1)[1]
    return data.decode("utf-8", errors="replace")
```
`agent.py`：completed 事件与 failed 事件（`outcome = "failed"` 分支）加 `"output_tail": tail_text(log_file)`；`_execute` 里 `log_file` 已在作用域内。

- [ ] **Step 4: 跑绿**；把 Task 8 的 `expectedFailure` 去掉后重跑集成测试。

- [ ] **Step 5: Commit**

```bash
git add cli/keji/process.py cli/keji/agent.py cli/tests tests/integration
git commit -m "feat(cli): attach the last 8 KB of tool output to completed and failed events"
```

---

## Phase C · iOS

测试命令：`cd ios && xcodegen generate && xcodebuild test -project KeJi.xcodeproj -scheme KeJi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .derived-data -only-testing:KeJiTests`。UI 测试前先起 fixture：`python3 TestSupport/workspace_server.py &`（端口 18768；跑完 `kill`）。

### Task 14: 解码新字段（plan_tier / not_before / output_tail / limit_id / window_mins）

**Files:**
- Modify: `ios/KeJi/Models/RemoteExecutionModels.swift`（`RunnerTool.planTier`、`RemoteJob.notBefore`、`RemoteJob.outputTail`、`RemoteJobRequest.notBefore`）、`ios/KeJi/Models/QuotaModels.swift`（`QuotaWindow.limitId`、`windowMins`、`id`；`AccountQuotaPool.planTier`）
- Test: `ios/KeJiTests/WorkspaceContractTests.swift`

**Interfaces:**
- Produces: `RunnerTool.planTier: String`（缺省 ""）；`RemoteJob.notBefore: Date?`、`outputTail: String?`；`RemoteJobRequest.notBefore: Date?`；`QuotaWindow.limitId: String`、`windowMins: Int`，`id == "\(poolId)|\(limitId)|\(scope)|\(kind)|\(windowMins)"`；`AccountQuotaPool.planTier: String`。

- [ ] **Step 1: 写失败测试**

```swift
func testRunnerToolDecodesPlanTierAndToleratesItsAbsence() throws {
    let with = Data(#"{"id":"claude-default","provider":"claude","version":"local","status":"available","plan_tier":"max","updated_at":"2026-09-25T00:00:00Z"}"#.utf8)
    XCTAssertEqual(try JSONCoding.decoder.decode(RunnerTool.self, from: with).planTier, "max")
    let without = Data(#"{"id":"codex-default","provider":"codex","version":"local","status":"available","updated_at":"2026-09-25T00:00:00Z"}"#.utf8)
    XCTAssertEqual(try JSONCoding.decoder.decode(RunnerTool.self, from: without).planTier, "")
}

func testRemoteJobDecodesNotBeforeAndOutputTail() throws {
    let json = Data(#"{"id":"j","task_id":"t","runner_id":"r","workspace_id":"w","tool_profile_id":"codex-default","status":"queued","revision":1,"not_before":"2026-09-27T14:00:00Z","output_tail":"3 passed\n","created_at":"2026-09-25T00:00:00Z","updated_at":"2026-09-25T00:00:00Z"}"#.utf8)
    let job = try JSONCoding.decoder.decode(RemoteJob.self, from: json)
    XCTAssertEqual(job.notBefore, Date(timeIntervalSince1970: 1790517600))
    XCTAssertEqual(job.outputTail, "3 passed\n")
}

func testRemoteJobRequestEncodesNotBeforeInRFC3339() throws {
    let request = RemoteJobRequest(taskId: "t", runnerId: "r", workspaceId: "w", toolProfileId: "codex-default",
                                   prompt: "p", idempotencyKey: "k", expectedTaskRevision: 1, planId: "plan",
                                   notBefore: Date(timeIntervalSince1970: 1790517600))
    let body = try String(decoding: JSONCoding.encoder.encode(request), as: UTF8.self)
    XCTAssertTrue(body.contains(#""not_before":"2026-09-27T14:00:00Z""#), body)
}

func testQuotaWindowIdentityIncludesLimitAndWindow() throws {
    let json = Data(#"{"pools":[{"pool_id":"p","provider":"codex","plan_tier":"plus","availability":"available","windows":[
      {"pool_id":"p","scope":"primary","kind":"codex","limit_id":"codex","window_mins":300,"used_percent":10,"observed_at":"2026-09-25T00:00:00Z","expires_at":"2026-09-25T05:00:00Z","source":"runner","confidence":"exact"},
      {"pool_id":"p","scope":"primary","kind":"codex","limit_id":"codex-mini","window_mins":300,"used_percent":20,"observed_at":"2026-09-25T00:00:00Z","expires_at":"2026-09-25T05:00:00Z","source":"runner","confidence":"exact"}]}],
      "observed_at":"2026-09-25T00:00:00Z"}"#.utf8)
    let quota = try JSONCoding.decoder.decode(AccountQuota.self, from: json)
    XCTAssertEqual(quota.pools[0].planTier, "plus")
    XCTAssertEqual(Set(quota.pools[0].windows.map(\.id)).count, 2)
}
```
若 `JSONCoding.encoder` 的日期策略不是 RFC 3339 秒级，测试改为断言包含 `"not_before":"2026-09-27T14:00:00` 前缀。

- [ ] **Step 2: 跑红** — 编译失败。

- [ ] **Step 3: 实现**

`RunnerTool` 加 `var planTier: String = ""` 并自定义 `init(from:)`（用 `decodeIfPresent ... ?? ""`，其余字段照常解码）。`RemoteJob` 加 `var notBefore: Date? = nil`、`var outputTail: String? = nil`。`RemoteJobRequest` 加 `var notBefore: Date? = nil`（放在 `planId` 后）。`QuotaWindow` 加 `var limitId: String = ""`、`var windowMins: Int = 0`，`id` 改为 `"\(poolId)|\(limitId)|\(scope)|\(kind)|\(windowMins)"`，自定义 `init(from:)` 用 `decodeIfPresent`。`AccountQuotaPool` 加 `var planTier: String = ""`，在现有自定义 `init(from:)` 里 `decodeIfPresent ... ?? ""`，memberwise init 加参数 `planTier: String = ""`。修正因 `QuotaWindow` memberwise init 变化而不编译的测试（`QuotaPresentationTests` 的 `win` helper 传默认值即可）。

- [ ] **Step 4: 跑绿** — `KeJiTests` 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add ios/KeJi/Models ios/KeJiTests
git commit -m "feat(ios): decode plan tier, not_before, output_tail and full quota window identity"
```

### Task 15: 额度卡片：套餐、绝对重置时刻、完整窗口映射

**Files:**
- Modify: `ios/KeJi/Features/AITools/QuotaPresentation.swift`、`ios/KeJi/Features/AITools/AIToolsView.swift:110-137, 182-217`、`ios/KeJi/Stats/Format.swift`（新 `resetMoment`）
- Test: `ios/KeJiTests/QuotaPresentationTests.swift`

**Interfaces:**
- Produces: `Format.resetMoment(_ date: Date, now: Date) -> String`（今天 →「今天 14:00」，7 天内 →「周三 14:00」，更远 →「9月27日 14:00」）；`QuotaWindow.resetText(now:) -> String?`（「周三 14:00 重置」）；`ToolQuotaCard.tier: String`（「套餐 Max」/ 「套餐未知」）；scope 映射含 `seven_day`、`secondary`。

- [ ] **Step 1: 写失败测试**

```swift
func testScopeLabelsCoverClaudeAndCodexWindows() {
    XCTAssertEqual(win("p", "seven_day", used: 10, fresh: true, now: Date()).scopeLabel, "本周")
    XCTAssertEqual(win("p", "secondary", used: 10, fresh: true, now: Date()).scopeLabel, "本周")
    XCTAssertEqual(win("p", "five_hour", used: 10, fresh: true, now: Date()).scopeLabel, "短时")
}

func testResetMomentIsAbsolute() {
    let cal = Calendar(identifier: .gregorian)
    var comps = DateComponents(year: 2026, month: 9, day: 25, hour: 9, minute: 0)
    comps.timeZone = TimeZone.current
    let now = cal.date(from: comps)!
    XCTAssertEqual(Format.resetMoment(now.addingTimeInterval(5 * 3600), now: now), "今天 14:00")
    XCTAssertEqual(Format.resetMoment(now.addingTimeInterval(2 * 86400 + 5 * 3600), now: now), "周日 14:00")
    XCTAssertEqual(Format.resetMoment(now.addingTimeInterval(10 * 86400), now: now), "10月5日 09:00")
}

func testToolCardShowsTierAndWeeklyResetMoment() {
    let now = Date()
    var weekly = win("pool-claude", "seven_day", used: 45, fresh: true, now: now)
    weekly.resetAt = now.addingTimeInterval(3600)
    let pool = AccountQuotaPool(poolId: "pool-claude", provider: "claude", availability: "available",
                                windows: [win("pool-claude", "five_hour", used: 20, fresh: true, now: now), weekly], planTier: "max")
    let card = ToolQuotaCard(pool: pool, now: now)
    XCTAssertEqual(card.tier, "套餐 Max")
    XCTAssertTrue(card.detail.hasPrefix("周额度剩余 55% · "), card.detail)
    XCTAssertTrue(card.detail.hasSuffix(" 重置"), card.detail)
    let unknown = ToolQuotaCard(pool: AccountQuotaPool(poolId: "p", provider: "codex", availability: "unknown", windows: []), now: now)
    XCTAssertEqual(unknown.tier, "套餐未知")
}
```

- [ ] **Step 2: 跑红**。

- [ ] **Step 3: 实现**

`Format`：
```swift
private static let weekdayTimeFormatter = formatter("EEE HH:mm")
private static let dateTimeFormatter = formatter("M月d日 HH:mm")
/// 绝对重置时刻：今天 → 「今天 14:00」；7 天内 → 「周三 14:00」；更远 → 「9月27日 14:00」。
static func resetMoment(_ date: Date, now: Date = Date()) -> String {
    if calendar.isDate(date, inSameDayAs: now) { return "今天 " + time(date) }
    if date.timeIntervalSince(now) < 7 * 86400 { return weekdayTimeFormatter.string(from: date) }
    return dateTimeFormatter.string(from: date)
}
```
（`zh_CN` 的 `EEE` 输出「周三」。）`QuotaWindow`：
```swift
var resetText: String? { resetAt.map { Format.resetMoment($0) + " 重置" } }
func resetText(now: Date) -> String? { resetAt.map { Format.resetMoment($0, now: now) + " 重置" } }
```
`scopeLabel` 加 `"seven_day", "secondary"` 到「本周」分支；`ToolQuotaCard` 里 `short` 的匹配集不变，`weekly` 的匹配集加 `"seven_day", "secondary"`；新增 `let tier: String`，`init` 里 `tier = pool.planTier.isEmpty ? "套餐未知" : "套餐 " + pool.planTier.prefix(1).uppercased() + pool.planTier.dropFirst()`；`detail` 的周额度分支：`"周额度剩余 \(Int(remaining.rounded()))%" + (weekly.resetText(now: now).map { " · " + $0 } ?? "")`。
`AIToolsView.toolCard`：在 `card.capability` 下面再加一行 `Text(card.tier)`；`poolDetail` 的窗口行把「预计 … 后可核验」改为 `window.resetText(now: store.now)`。

- [ ] **Step 4: 跑绿**；用 `--sample-data --screen ai-tools` 截图核对卡片布局。

- [ ] **Step 5: Commit**

```bash
git add ios/KeJi/Features/AITools ios/KeJi/Stats/Format.swift ios/KeJiTests/QuotaPresentationTests.swift
git commit -m "feat(ios): show plan tier and absolute reset moments on quota cards"
```

### Task 16: 配对错误可读，未登录直达账号页

**Files:**
- Create: `ios/KeJi/Features/AITools/PairingErrors.swift`
- Modify: `ios/KeJi/Features/AITools/AIToolsView.swift:40-44, 219-241`
- Test: `ios/KeJiTests/PairingErrorsTests.swift`（新）

**Interfaces:**
- Produces: `func pairingErrorText(_ error: Error) -> String`。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import KeJi

final class PairingErrorsTests: XCTestCase {
    func testKnownCodesBecomeActionableChinese() {
        XCTAssertEqual(pairingErrorText(APIError(code: 40400, message: "resource not found")), "没有这个授权码，请核对电脑上显示的 8 位码。")
        XCTAssertEqual(pairingErrorText(APIError(code: 41000, message: "resource expired")), "授权码已过期，请在电脑上重新运行 keji cloud login。")
        XCTAssertEqual(pairingErrorText(APIError(code: 40900, message: "resource state conflict")), "这个授权码已经用过了，请在电脑上重新生成。")
        XCTAssertEqual(pairingErrorText(APIError(code: 40300, message: "operation not allowed")), "游客账号不能绑定电脑，请先登录。")
        XCTAssertEqual(pairingErrorText(APIError(code: 40100, message: "authentication required")), "登录已失效，请重新登录后再试。")
    }
    func testUnknownErrorsKeepTheirMessage() {
        XCTAssertEqual(pairingErrorText(APIError(code: 50000, message: "request failed")), "绑定失败：request failed")
        XCTAssertEqual(pairingErrorText(APIError.offline), "绑定失败：离线模式")
    }
}
```

- [ ] **Step 2: 跑红**。

- [ ] **Step 3: 实现**

```swift
import Foundation

/// 配对失败给一句能照着做的话，不把服务端原始错误串直接贴给用户。
func pairingErrorText(_ error: Error) -> String {
    guard let api = error as? APIError else { return "绑定失败：\(error.localizedDescription)" }
    switch api.code {
    case 40400: return "没有这个授权码，请核对电脑上显示的 8 位码。"
    case 41000: return "授权码已过期，请在电脑上重新运行 keji cloud login。"
    case 40900: return "这个授权码已经用过了，请在电脑上重新生成。"
    case 40300: return "游客账号不能绑定电脑，请先登录。"
    case 40100: return "登录已失效，请重新登录后再试。"
    default: return "绑定失败：\(api.message)"
    }
}
```
`AIToolsView.approvePairing` / `confirmPairing` 的 `catch` 改为 `pairingMessage = pairingErrorText(error)`。未登录卡片加按钮：`AppButton("去登录", variant: .accent, fullWidth: true) { router.push(.account) }`（视图需 `@Environment(AppRouter.self) private var router`），identifier `pairing.login`。

- [ ] **Step 4: 跑绿**。

- [ ] **Step 5: Commit**

```bash
git add ios/KeJi/Features/AITools ios/KeJiTests/PairingErrorsTests.swift
git commit -m "feat(ios): explain pairing failures in plain words and link guests to login"
```

### Task 17: 派发带执行时间；「保存并安排时间」真正安排

**Files:**
- Modify: `ios/KeJi/Store/AppStore+Plans.swift:83-119`（`dispatchPlan` 加 `notBefore`）、`ios/KeJi/Features/Plans/PlanDetailView.swift:218-275`（面板加时间）、`ios/KeJi/Features/Tasks/TaskCreateView.swift:165-188`（`.schedule`）、`ios/KeJi/Models/RemoteExecutionModels.swift`（`RemoteJob.displayLabel(now:)`）
- Test: `ios/KeJiTests/PlanSyncTests.swift`（或 `RemoteExecutionTests.swift`）

**Interfaces:**
- Produces: `AppStore.dispatchPlan(_:runnerID:workspaceID:toolID:notBefore: Date? = nil)`；幂等键含 `notBefore` 的秒级时间戳；`RemoteJob.displayLabel(now:) -> String`（queued 且 `notBefore > now` →「已安排 · 9月27日 14:00」，否则 `status.label`）。

- [ ] **Step 1: 写失败测试**

```swift
func testScheduledQueuedJobReadsAsPlanned() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var job = RemoteJob(id: "j", taskId: "t", runnerId: "r", workspaceId: "w", toolProfileId: "codex-default",
                        status: .queued, revision: 1, resultSummary: nil, prompt: nil, createdAt: now, updatedAt: now)
    XCTAssertEqual(job.displayLabel(now: now), "云端排队")
    job.notBefore = now.addingTimeInterval(3600)
    XCTAssertEqual(job.displayLabel(now: now), "已安排 · " + Format.resetMoment(now.addingTimeInterval(3600), now: now))
    job.notBefore = now.addingTimeInterval(-60)
    XCTAssertEqual(job.displayLabel(now: now), "云端排队")
    job.status = .running
    job.notBefore = now.addingTimeInterval(3600)
    XCTAssertEqual(job.displayLabel(now: now), "AI 执行中")
}
```
再在 `PlanSyncTests` 里找现有的「dispatchPlan 发送 RemoteJobRequest」用例（`grep -n dispatchPlan KeJiTests/*.swift`），复制一份传 `notBefore:`，断言捕获到的请求体含 `"not_before"` 且两次不同 `notBefore` 的幂等键不同。

- [ ] **Step 2: 跑红**。

- [ ] **Step 3: 实现**

`RemoteJob`：
```swift
func displayLabel(now: Date = Date()) -> String {
    if status == .queued, let notBefore, notBefore > now { return "已安排 · " + Format.resetMoment(notBefore, now: now) }
    return status.label
}
```
`dispatchPlan` 签名加 `notBefore: Date? = nil`；`identity` 数组追加 `notBefore.map { String(Int($0.timeIntervalSince1970)) } ?? "now"`；`RemoteJobRequest(..., planId: id, notBefore: notBefore)`。
`PlanDispatchSheet` 加：
```swift
@State private var scheduled = false
@State private var runAt = Date().addingTimeInterval(3600)
```
Form 里加：
```swift
Section("执行时间") {
    Toggle("指定时间执行", isOn: $scheduled).accessibilityIdentifier("plan.dispatch.schedule")
    if scheduled {
        DatePicker("开始于", selection: $runAt, in: Date().addingTimeInterval(120)...Date().addingTimeInterval(30 * 86400),
                   displayedComponents: [.date, .hourAndMinute])
            .accessibilityIdentifier("plan.dispatch.runAt")
        Text("到点后由电脑领取执行；那时额度不足会先等待，不会转为付费。")
            .font(Typo.sans(Typo.xs)).foregroundStyle(.secondary)
    }
}
```
「确认派发」调用 `store.dispatchPlan(planID, runnerID:..., workspaceID:..., toolID:..., notBefore: scheduled ? runAt : nil)`。
`PlanDetailView` 执行记录行改为 `Text("执行记录：\(job.displayLabel(now: store.now))")`。
`TaskCreateView.save(.schedule)`：与 `.start` 同路径，但 `notBefore: scheduledStart`；`canSave` 在 `.schedule` 时额外要求 `scheduledStart != nil` —— 把「保存并安排时间」按钮的 `disabled` 改为 `!canSave || scheduledStart == nil || !showsAI`，并在按钮下加一行说明「需要先填「计划开始」，并选择 AI 来做」。

- [ ] **Step 4: 跑绿**。

- [ ] **Step 5: Commit**

```bash
git add ios/KeJi ios/KeJiTests
git commit -m "feat(ios): dispatch with an optional run time and show scheduled jobs as 已安排"
```

### Task 18: 执行记录显示输出尾巴

**Files:**
- Modify: `ios/KeJi/Features/Plans/PlanDetailView.swift:106-111`
- Test: `ios/KeJiUITests/WorkspaceFlowTests.swift`（在 Task 19 一并覆盖）

- [ ] **Step 1: 实现**（纯视图，测试在 Task 19）

```swift
if let job = store.planJobs[plan.id] {
    Text("执行记录：\(job.displayLabel(now: store.now))").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
        .accessibilityIdentifier("plan.job.status")
    if let summary = job.resultSummary, !summary.isEmpty {
        Text(summary).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
    }
    if let tail = job.outputTail, !tail.isEmpty {
        DisclosureGroup("查看输出（最后 8 KB）") {
            ScrollView(.horizontal) {
                Text(tail).font(Typo.mono(Typo.xs)).foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled).padding(8)
            }
            .frame(maxHeight: 240)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .font(Typo.sans(Typo.xs)).accessibilityIdentifier("plan.job.output")
    }
    Spacer().frame(height: 12)
}
```

- [ ] **Step 2: 编译** — `xcodebuild build-for-testing ...` 无错误。

- [ ] **Step 3: Commit**

```bash
git add ios/KeJi/Features/Plans/PlanDetailView.swift
git commit -m "feat(ios): expose the runner's output tail in the plan execution record"
```

### Task 19: fixture 与 UI 测试：定时派发与输出尾巴

**Files:**
- Modify: `ios/TestSupport/workspace_server.py`（`POST /remote-jobs` 存 `not_before`、`GET /remote-jobs/:id` 回 `not_before` 与 `output_tail`）
- Test: `ios/KeJiUITests/WorkspaceFlowTests.swift`

- [ ] **Step 1: 读 fixture** — `grep -n "remote-jobs" ios/TestSupport/workspace_server.py`，找到创建与读取 job 的 handler。

- [ ] **Step 2: 写失败 UI 测试**（仿 `testCreateDispatchWaitAndAcceptThroughHTTP` 的前半段）

```swift
func testScheduledDispatchShowsPlannedTimeAndCompletedJobShowsOutput() {
    launchOnline()                       // 文件里已有的联网启动 helper 名，按实际改
    tap("project.keji"); tap("task.quota"); tap("plan.03")   // 或文件里已用的可派发 Plan
    tap("plan.dispatch")
    let toggle = app.switches["plan.dispatch.schedule"].firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    toggle.tap()
    tap("plan.dispatch.confirm")
    let planned = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "执行记录：已安排 · ")).firstMatch
    XCTAssertTrue(planned.waitForExistence(timeout: 8))
    // fixture 在下一次 GET 时把任务推进到 awaiting_review 并附上 output_tail
    XCTAssertTrue(app.staticTexts["执行记录：结果待确认"].waitForExistence(timeout: 15))
    tap("plan.job.output")
    XCTAssertTrue(app.staticTexts["3 passed"].waitForExistence(timeout: 5))
}
```

- [ ] **Step 3: 跑红**（起 fixture 后 `-only-testing:KeJiUITests/WorkspaceFlowTests/testScheduledDispatchShowsPlannedTimeAndCompletedJobShowsOutput`）。

- [ ] **Step 4: 实现 fixture**：创建 job 时 `job["not_before"] = body.get("not_before")`；读取时若 `not_before` 存在且这是第二次 GET，则把状态改为 `awaiting_review`、`output_tail = "$ pytest\n3 passed\n"`（fixture 里已有类似的「下次读取推进状态」机制则复用）。

- [ ] **Step 5: 跑绿**；全套 UI 测试 PASS（fixture 运行中）。

- [ ] **Step 6: Commit**

```bash
git add ios/TestSupport/workspace_server.py ios/KeJiUITests/WorkspaceFlowTests.swift
git commit -m "test(ios): cover scheduled dispatch and output tail through the fixture server"
```

---

## Phase D · 发布与真机验收

### Task 20: 部署 Valley

- [ ] **Step 1:** `cd /opt/coding/planb/github/Valley && make test`，全绿。
- [ ] **Step 2:** 合并到 `release/timetrace-ai-workspace` 并推送：`git checkout release/timetrace-ai-workspace && git merge --no-ff codex/keji-ai-workspace-fixes && git push`。
- [ ] **Step 3:** `gh auth switch -u underestimatedme && gh workflow run publish.yml --ref release/timetrace-ai-workspace -f deploy=true`，`gh run watch` 到绿。
- [ ] **Step 4:** 冒烟：用一个游客会话 `curl` `GET /timetrace/api/v1/runners` 应 200；用真实登录会话 `GET /quota` 应 200。

### Task 21: 在用户 Mac 上安装并配对 CLI

- [ ] **Step 1:** `cd /opt/coding/planb/github/TimeTrace/cli && python3 -m unittest discover -s tests`，全绿。
- [ ] **Step 2:** 确认 `cli/bin/keji` 在 PATH（README「安装」）；`keji agent doctor`。
- [ ] **Step 3:** `keji workspace add <一个测试仓库路径>`。
- [ ] **Step 4:** `keji cloud login`，把 8 位码交给用户在手机上输入（手机需已用验证码登录）。看到「已上报工具清单与额度」。
- [ ] **Step 5:** `keji agent install`；`launchctl list | grep keji` 有进程；`tail -f ~/.keji/logs/*.log` 看到周期上报。
- [ ] **Step 6:** 更新 `docs/remote-runner-operations.md`：上报时机、保持唤醒（`caffeinate -dims` 或 `sudo pmset -a sleep 0`）、`--once` 也上报。提交。

### Task 22: iOS TestFlight 构建

- [ ] **Step 1:** `ios/project.yml` 的 `CURRENT_PROJECT_VERSION` 改为 `2026092501`（若当天已用则递增）。
- [ ] **Step 2:** `xcodegen generate`，本地全套测试（单元 + UI，fixture 运行中）全绿。
- [ ] **Step 3:** 归档上传（`ios/README.md`「TestFlight archive」两条命令）；`python3 ios/scripts/asc_testflight.py status` 看到新构建 `VALID` 并进入内部组。
- [ ] **Step 4:** 更新 `docs/superpowers/notes/keji-ios-release-checklist.md`，提交推送，CI 绿。

### Task 23: 真机验收（spec §6，全部通过才算完成）

- [ ] **1. 配对可见性**：手机批准后 10 秒内「你的 AI」页出现 Mac、Codex 与 Claude Code 两张卡，各带套餐、用量、重置时刻。
- [ ] **2. Codex 派发**：新建任务「在 README 末尾加一行今天的日期」→ AI 来做 → Mac / 测试仓库 / Codex → 保存并开始。2 分钟内 云端排队 → 电脑已领取 → AI 执行中 → 结果待确认；可展开输出；验收通过。
- [ ] **3. Claude Code 派发**：同上换 Claude Code。
- [ ] **4. 定时派发**：选 3 分钟后，显示「已安排 · 时刻」，到点自动执行完成。
- [ ] **5. 离线感知**：合上盖子 2 分钟内显示离线且派发面板不再列出；打开后恢复。
- [ ] 结果记入 `docs/superpowers/notes/2026-09-2x-keji-0-1-acceptance.md`，每条附时间戳与截图路径；失败项回到对应任务修复后重跑。
