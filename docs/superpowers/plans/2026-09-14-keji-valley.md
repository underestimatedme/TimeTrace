# 刻迹 Valley Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供 Plan、可靠调度、评分与有证据日报的服务端契约。

**Architecture:** 扩展现有 timetrace app，不新建独立服务；复用 RemoteJob / RemoteAttempt / RemoteEvent。新领域数据与执行状态分开写入，所有身份来自已认证用户和 Runner。

**Tech Stack:** Go、GORM、PostgreSQL；仓库为 Valley。

**Spec:** [产品设计](../specs/2026-09-14-keji-ai-timeline-product-design.md)；[总计划/API 契约](2026-09-14-keji-ai-workspace.md)。

## Global Constraints

- 业务层级固定为项目 → 任务 → Plan。
- 自动续杯指订阅额度自然恢复后自动续跑暂停的 Plan，不额外付费。
- 工具凭据留在本机；旧客户端不能覆盖服务端执行状态。
- 未知额度不等于满额；首版每台 Runner 单个编码进程。
- 日报默认私有草稿；优先级 P0–P3 可人工固定。
- 总计划的全部 Global Constraints 同时适用；本轮仅 review，不执行迁移。

## 文件结构与接口边界

已有文件均在 `internal/apps/timetrace/`：`model.go`、`repository.go`、`app.go`、`sync.go`、`remote_model.go`、`remote.go`、`remote_handlers.go`。新增 Plan、quota、report 各自聚合在独立文件，不继续扩大 remote.go 的领域责任。

### V1：默认 Plan 与活跃执行约束迁移

**Files:** Create `plan_model.go`、`plan_migration.go`、`plan_migration_test.go`；Modify `model.go`、`remote_model.go`、`repository.go`。

**Interfaces:** `DefaultPlanID(taskID string) string`；`MigratePlans(ctx context.Context, db *gorm.DB) error`。Plan 使用总计划字段并加 UserID / CreatedAt / UpdatedAt。Goal 增加验收条件与版本范围；Task 增加 work_weight / risk / baseline_revision。RemoteJob 新增可空 PlanID；TimeSession/AIExecution 保留 TaskID 并加可空 PlanID；RemoteAttempt 不另建副本。

- [ ] 在 `plan_migration_test.go` 先写确定性 ID 测试及 PostgreSQL 集成测试：同任务迁移两次只得到一个默认 Plan，历史 AIExecution 归属不变。

```go
func TestDefaultPlanIDStable(t *testing.T) {
    a := DefaultPlanID("task-1")
    if a != DefaultPlanID("task-1") || a == DefaultPlanID("task-2") || len(a) != 32 {
        t.Fatalf("invalid default plan id: %s", a)
    }
}
```

- [ ] 运行 `go test ./internal/apps/timetrace -run TestDefaultPlanIDStable -count=1`，确认缺少函数导致失败。
- [ ] 实现固定命名空间散列与幂等事务；保留 task 原键，默认 Plan 唯一键 `(user_id, legacy_task_id)`，不能在每次进程启动重新创建。

```go
func DefaultPlanID(taskID string) string {
    sum := sha256.Sum256([]byte("timetrace:default-plan:v1:" + taskID))
    return hex.EncodeToString(sum[:16])
}
```

迁移顺序：加表/可空列→按 Task 补 Plan→回填 RemoteJob/AIExecution→核对孤儿与计数→建立新索引→最后移除旧索引。当前 `repository.go` 启动时按 `(user_id,task_id)` 中断重复作业的 UPDATE 必须移除/替换为版本化迁移；仅改索引会让重启误杀不同 Plan。

```sql
CREATE UNIQUE INDEX IF NOT EXISTS tt_one_active_remote_job_per_plan
ON tt_remote_jobs (user_id, plan_id)
WHERE plan_id IS NOT NULL AND status IN
('queued','leased','running','waiting_quota','waiting_local_auth','waiting_input','awaiting_review');
DROP INDEX IF EXISTS tt_one_active_remote_job_per_task;
```

执行 DROP 前验证所有活跃旧 job 已有 PlanID，且所有正在运行的 Valley 版本均不会重建旧索引。多 Plan 阶段禁止回滚旧迁移 binary。已有任务失败/中断记录保留，不“修复”为完成。

- [ ] 运行 `go test ./internal/apps/timetrace -run 'TestDefaultPlanID|TestPlanMigration' -count=1 -v`。集成测试沿用 `newTestApp` 和 `APP_DSN_TIMETRACE_TEST`，必须连隔离数据库；出现 SKIP 不算通过。补测同 Task 两个不同 Plan 的活跃 job 能共存、同 Plan 第二个被拒。
- [ ] 仅暂存上述文件，提交 `feat(timetrace): migrate task execution to plans`。

### V2：Plan 编辑、DAG 和状态写入隔离

**Files:** Create `plans.go`、`plan_handlers.go`、`plan_test.go`、`plan_integration_test.go`；Modify `app.go`、`sync.go`、`remote.go`、`remote_handlers.go`。

**Interfaces:** `ValidatePlanDependencies(planID string, edges map[string][]string) error`；`PlanPatch` 含 expected_revision 及可编辑字段，不含执行状态。新增 GET/POST `/tasks/{task_id}/plans`，PATCH `/plans/{plan_id}`，POST `/plans/{plan_id}/accept`、`/cancel`。accept 含 expected_revision、evidence_ids、验收项结果；dispatch 仍走既有远程 job 路由，加 plan_id，旧 task_id 调用映射默认 Plan。

- [ ] 添加循环测试；集成测试覆盖跨用户 Task/Plan/证据 ID 返回 404、revision 过期 409、未满足验收 422、旧 sync 不改 Plan 状态。

```go
func TestPlanDependencyCycle(t *testing.T) {
    if ValidatePlanDependencies("a", map[string][]string{"a":{"b"}, "b":{"a"}}) == nil {
        t.Fatal("cycle accepted")
    }
    if ValidatePlanDependencies("a", map[string][]string{"a":{"b"}, "b":{}}) != nil {
        t.Fatal("DAG rejected")
    }
}
```

- [ ] 运行 `go test ./internal/apps/timetrace -run TestPlanDependencyCycle -count=1` 确认失败。
- [ ] 用 DFS 三色状态检测环；API 先做用户归属和目标范围校验，再在事务中读取依赖图和 CAS revision。跨项目边只有用户显式提交才能建立；使用用户域图写锁防两个并发 PATCH 各自通过后合成环。

```text
PATCH: authenticated user → ownership → expected_revision → locked DAG validation → revision+1
ACCEPT: awaiting_review + all criteria accepted + evidence ownership → accepted
CANCEL: revision+1 + invalidate next_wake_at + desired_action=cancel
SYNC v1: project/task editable fields merge; Plan/job runtime fields ignored
```

Task 默认策略由 Plan 创建时继承，之后 Plan 覆盖独立记录；修改 Task 默认不重写进行中 Plan。Goal 进度只汇总其主要关联 Task 的已验收权重；不按 attempt 数更新。
- [ ] 运行 `go test ./internal/apps/timetrace -run 'TestPlan|TestRemote|TestSync' -count=1 -v`，逐项检查无 skip；409 包含当前 revision，客户端可重新合并编辑。
- [ ] 提交 `feat(timetrace): add revisioned plan APIs and dependency checks`。

### V3：账号额度池、恢复协调与 lease 门禁

**Files:** Create `quota_model.go`、`quota.go`、`quota_test.go`、`quota_integration_test.go`；Modify `remote.go`、`remote_model.go`、`remote_handlers.go`。

**Interfaces:** `QuotaAvailability(windows []QuotaWindow, now time.Time) string` 返回 available / blocked / unknown。QuotaWindow 使用总计划字段；`UsedPercent *float64`、`ResetAt *time.Time`、`ObservedAt/ExpiresAt time.Time`。POST Runner quota samples 以 `(runner_id,sample_id)` 去重；GET account quota 聚合不返回凭据。客户端报告不能改账号绑定。

- [ ] 写多窗口测试（短时 available、周 blocked）和过期 unknown 测试。

```go
func TestQuotaExpiredIsUnknown(t *testing.T) {
    now := time.Unix(200, 0)
    used := 100.0
    got := QuotaAvailability([]QuotaWindow{{UsedPercent:&used, ObservedAt:now.Add(-time.Hour), ExpiresAt:now.Add(-time.Second)}}, now)
    if got != "unknown" { t.Fatalf("got %s", got) }
}
```

- [ ] 运行 `go test ./internal/apps/timetrace -run TestQuotaExpiredIsUnknown -count=1` 确认失败。
- [ ] 实现 tri-state 聚合：任一新鲜阻塞→blocked；任何适用窗口缺失/陈旧→unknown；全部新鲜且可用才 available。reset_at 过去只安排刷新；公共 confirmed 事件同样只安排刷新。保留样本来源和接收时间，拒绝未来采样时间超过允许时钟偏差 2 分钟的记录。

```text
claim transaction:
  lock account pool → lock runner/workspace → CAS job revision/lease
  verify enabled policy + online runner + capabilities + dependency + cancellation
  reserve account/workspace/plan → issue attempt and lease
resume unknown:
  reliable reset passed AND enforced zero-spend AND native resume
  AND no fresh blocking window AND no probe for this pool/window
  → one controlled probe; otherwise keep waiting with reason
```

验证顺序固定以减少锁死；pool reservation 有过期时间，重启可回收。重复唤醒复用幂等键，不创建第二个活跃 job；续跑创建新的 RemoteAttempt，保留原 provider session。退出码不直接证明验收通过。
- [ ] 集成测试同时 claim 20 次只得 1 个 lease，重复 sample/event 不双计；旧 attempt/过期 lease 回报拒绝；取消与 wake 竞争最终不启动。运行 `go test -race ./internal/apps/timetrace -run 'TestQuota|TestRemote' -count=1 -v`。
- [ ] 提交 `feat(timetrace): coordinate quota recovery with fenced leases`。

### V4：可解释排序、AI 建议与日报事实

**Files:** Create `scoring.go`、`scoring_test.go`、`reports.go`、`report_model.go`、`reports_test.go`、`report_handlers.go`；Modify `app.go`。

**Interfaces:** `PriorityScore(goal, urgency, unlock, aging float64) float64`，输入均为 0–100；`ReportDay(at time.Time, zone string) (string,error)`；DailyReport 唯一 `(user_id,local_date,revision)`，含 evidence IDs / baseline version / generated_at / coverage，不在报告中保存凭据或原始私密日志。

- [ ] 添加纯函数测试：满分为100、固定输入为85.5；跨午夜 Dubai 日期正确。

```go
func TestPriorityScore(t *testing.T) {
    if got := PriorityScore(100,90,80,50); math.Abs(got-85.5)>0.001 { t.Fatal(got) }
}
func TestReportDayDubai(t *testing.T) {
    got, err := ReportDay(time.Date(2026,9,14,21,0,0,0,time.UTC), "Asia/Dubai")
    if err != nil || got != "2026-09-15" { t.Fatalf("%s %v",got,err) }
}
```

- [ ] 运行 `go test ./internal/apps/timetrace -run 'TestPriorityScore|TestReportDay' -count=1` 确认失败。
- [ ] 实现确定性评分和日期转换；输入 API 拒绝越界，不悄悄截断。urgency：已逾期100、24h内90、3天内70、7天内40、其余/无日期10；unlock 为解锁就绪 Plan 工作权重占比×100；aging 为 min(等待小时/72,1)×100；goal 为用户确认任务贡献权重归一化。排序键为 priority 升序、score 降序、queued_at 升序、ID。

```go
func PriorityScore(goal, urgency, unlock, aging float64) float64 {
    return .35*goal + .30*urgency + .20*unlock + .15*aging
}
func ReportDay(at time.Time, zone string) (string,error) {
    loc, err := time.LoadLocation(zone)
    if err != nil { return "",err }
    return at.In(loc).Format("2006-01-02"),nil
}
```

AI 建议只选 capability/权限/零付费合格项。速度模式排序预计完成区间上界；节省模式在同额度池按预计占用排序，跨池不比较百分比；均衡优先复用上下文、再等待时间、再有样本的验收质量。样本<5不展示成功率，返回规则理由。manual 仍校验门禁。GET `/plans/{id}/recommendation` 返回总计划 DispatchDecision，真实 dispatch 再校验 revision。

日报按用户时区午夜后生成模板草稿，事件去重键复用 job/attempt/seq；成果按 Plan/验收 revision 去重。人工投入与 AI 活跃分别聚合，等待另列；跨日区间切片。GET `/reports?date=YYYY-MM-DD`；POST `/reports/{id}/revise` 保留旧版。无记录返回空状态；补报触发修订，不改原报告。

生产力四维45/30/15/10；Goal贡献按冻结 Task范围封顶，quality按验收/返工事实，plan按当日承诺兑现，efficiency只有同类历史基准足够才计算。总数据覆盖率<80%不输出总分；否则按已知权重归一化并同时显示覆盖率、分项和版本。内部日报作业排除成果分母分子。API 等价估值与实际新增费用使用独立字段。
- [ ] 增加同 Plan 多 attempt、拆小 Plan 不增总权重、无样本不显示总分、DST 23/25小时、重复补报和越权报告测试；运行 `go test ./internal/apps/timetrace -run 'TestPriority|TestReport|TestRecommendation' -count=1 -v`。
- [ ] 提交 `feat(timetrace): explain priority and generate evidence-based daily reports`。

### V5：公共信号独立适配

**Files:** Create `reset_signals.go`、`reset_signals_test.go`、`testdata/reset-signals.json`；Modify `app.go`。

**Interfaces:** `ResetSignal` 含 ID / SourceURL / PublishedAt / EffectiveAt nullable / Products / Plans / Confidence / FetchedAt / ExpiresAt / Revision；`CanRefreshQuota(confidence string) bool`；GET `/reset-signals` 返回 cache age / source / events，不能返回个人额度。

- [ ] 测试 confirmed 仅允许刷新、possible 不刷新。

```go
func TestSignalConfidence(t *testing.T) {
    if CanRefreshQuota("possible") || !CanRefreshQuota("confirmed") { t.Fatal("invalid refresh policy") }
}
```

- [ ] 运行 `go test ./internal/apps/timetrace -run TestSignalConfidence -count=1` 确认失败。
- [ ] 实现 `func CanRefreshQuota(confidence string) bool { return confidence == "confirmed" }`。固定 source allowlist 为 betteropc.com；先核实公开或获授权接口。没有确认接口/抓取许可时仅返回源链接和 `integration_status:"link_only"`，这是首版可交付降级，不臆造 API。

若允许采集：服务端每30分钟缓存，超时5秒，失败最多3次指数退避附抖动，连续失败保留带 stale 标记缓存；按 source+event ID 去重，内容更正增 revision。禁止根据“今日”生成绝对时间，缺失生效时间保留 unknown。记录摘要/来源而非复制整站。HTML 文本只作数据，不进入调度指令。
- [ ] fixture 覆盖事件更正、重复、时间缺失、过期、抓取失败；无 source 授权测试 link_only 仍200，个人额度照常运行。运行 `go test ./internal/apps/timetrace -run TestSignal -count=1 -v`。
- [ ] 提交 `feat(timetrace): isolate public reset signal integration`。

### V6：账号生命周期、隐私与反馈契约

**先审计后定路径：** 核对并优先复用Valley共享认证、资料、授权、通知与反馈模块，不在timetrace复制凭据系统。以下均为待实现契约，尚非线上API。

- [ ] 测试用户域隔离、会话撤销、验证码过期/频控和协议版本；缺失项单独提交共享认证补丁，不绑定Plan迁移上线。
- [ ] 固定偏好schema/revision：主题、首页、时区、通知、诊断同意；显示偏好与执行策略分开，覆盖409与越权测试。
- [ ] 定义导出/注销异步作业：身份重验、幂等、状态查询、范围/期限/失败恢复；注销阻止领取并撤销令牌，明确离线Runner取消边界。生产删除另需授权。
- [ ] 设备解绑复用远程授权，只撤销刻迹能力，不读取或删除厂商密钥；测试旧token拒绝领取及运行中取消/补报策略。
- [ ] 反馈返回服务器工单ID、状态、用户内历史，带幂等/限流/长度限制；诊断逐次opt-in、脱敏、大小与保留期限限制，默认无附件/代码/环境变量。
- [ ] 通知事件去重，遵守类型/时区/免打扰；推送失败不影响任务状态机，关闭通知不影响查询恢复状态。
- [ ] 与iOS I4联调真实失败/重试/回执并记录安全测试结果；不以假账号和本地反馈编号代替生产验收。

## 自检与交接

V1覆盖迁移，V2覆盖层级/依赖/验收，V3覆盖恢复安全，V4覆盖目标评分/推荐/日报，V5覆盖 BetterOPC。全部集成测试必须证明未跳过；执行阶段最后运行 `go test ./...`，其他 Valley app 出错应分辨回归与环境问题，不凭局部测试宣布生产可发布。
