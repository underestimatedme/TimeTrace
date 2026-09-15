# 刻迹 AI 工作台生产复核修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 经用户明确选择后也可使用 superpowers:subagent-driven-development。Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 2026-09-15 复核发现的安全、状态、数据和生产主流程缺陷，形成可二轮复核的版本；本文件不是实现、合并或发布授权。

**Architecture:** 保留 SwiftUI → Valley Go API → 本机 Python Runner。Valley 维护权威 Plan/执行事实与原子领取门禁；Runner 在实际 spawn 前再次检查本地计费、租约和恢复上下文；iOS 只用服务端成功回执推进验收。按 Valley、Runner、iOS 三条修复线分批交付，不重新设计视觉或重写架构。

**Tech Stack:** iOS 17+ / SwiftUI / Swift 5；Go / GORM / PostgreSQL；Python 3.9+（保持当前声明的最低版本）。

**Spec:** [已确认产品设计](../specs/2026-09-14-keji-ai-timeline-product-design.md)、[总计划](2026-09-14-keji-ai-workspace.md)、[复核报告](/opt/coding/planb/github/keji-ai-workspace-review-2026-09-15.md)。

## Global Constraints

- 业务层级固定为项目 → 任务 → Plan；目标是项目的版本/里程碑属性与任务分组，不增加第四级目录。
- 用户确认：自动续杯指订阅额度自然恢复后自动续跑暂停的 Plan，不额外付费。
- 已经开始的 Plan 默认保持原工具/会话；取消后不得被旧的恢复定时器唤醒。
- 首版每台 Runner 单个编码进程；同一 Plan/工作目录不能并发写入。
- 没有可验证的新增计费限制，不开放无人值守续跑；不自动兑换、购买、充值或使用付费 API 回退。
- 优先级 P0–P3 可人工固定；硬阻塞不能被评分越过。
- 日报默认私有草稿；不自动修改仓库 CHANGELOG.md、创建 release 或发布报告。
- 保留用户最终 Logo、历史记录、旧客户端读取能力和当前发布流水线；本次不改变生产环境。
- 不用 fake adapter 证明真实工具计费/恢复能力；缺少证据时能力保持 false，界面明确阻塞。
- 不接触原工作区未提交的 Logo 文件；执行阶段先核对用户最新分支，不把 review worktree 的旧 HEAD 当作最新代码。

## 基线、文件归属与执行规则

审查基线：Valley cc3fb46；TimeTrace 6067101；分支均 codex/keji-ai-workspace。

- TimeTrace 参考工作树：/opt/coding/planb/github/.worktrees/timetrace-workspace-review。
- Valley 参考工作树：/opt/coding/planb/github/.worktrees/valley-workspace-review。
- 下文 V 路径相对 Valley 的 internal/apps/timetrace；T 路径相对 TimeTrace。
- 新建文件仅用于独立回归测试或职责清晰的持久化组件；不借修复进行大规模重构。
- 各包单独测试、提交和 review；跨仓库配套提交在验收记录中列双 SHA。未获后续授权不 push、合并或部署。
- 固定循环：写失败测试 → 确认失败原因符合缺陷 → 最小修复 → 目标及相邻测试通过 → 记录证据 → 独立提交。并发测试用 barrier/锁协调，不用 sleep 猜时序。
- 所有新增错误应保留既有 HTTP 契约；新 reason_code、schema/capability 版本需要同时写入契约和解码测试，不能仅更新 UI 文案。
- 下文状态表是修复验收契约，不冒充现有实现；测试必须调用真实 repository/入口，不能只测试一份复制的条件表达式。

## 批次与依赖

| 批次 | 修复包 | 退出条件 |
|---|---|---|
| A 安全执行 | F01–F04 | 不越过计费、额度、取消、依赖、租约、恢复门禁 |
| B 权威状态与数据 | F05–F07 | 验收一致；旧同步不覆写；迁移/合并不丢数据 |
| C iOS 主流程 | F08 | 真正拉取、派发、同步、验收与处理冲突 |
| D 数据输出与设置 | F09–F11 | 统计可信、推荐受门禁约束、保存/并发语义正确 |
| E 全链验收 | F12 | 回归常驻、无 SKIP、形成二轮复核证据 |

F01 的 Python 兼容先修；F02 与 F03 的 profile/provider/额度维度契约先固定。F08 依赖 F02/F05/F06；F09 依赖 F05/F06；F10 依赖 F02/F03；F12 在全部修复包完成后执行。

### Task 1: F01：统一本地启动门禁与 Python 兼容（T-01、T-02）

**Files:** T cli/keji/dispatch.py、scheduler.py、agent.py、adapters/cursor.py、adapters/gemini.py；tests/test_dispatch.py、test_scheduler.py、test_capabilities.py。

**Interfaces:** 复用 DispatchGate / deny_reason；scheduler 与 agent 的 start/resume 都必须消费真实 adapter capabilities，缺失能力按 false；不新增 connected=true 等价授权的快捷路径。

- [ ] 在 scheduler 的真实 run_once 入口注入计数 fake adapter，分别用缺失/false 的 can_enforce_zero_spend，断言 start/resume 调用次数都是 0。
- [ ] 用系统 Python 3.9 收集整个 CLI 套件，确认当前导入失败；修复不兼容注解，保持 3.9+，不擅自提高最低版本。
- [ ] 把同一个 deny_reason 检查接入 scheduler 和 agent 每个启动/恢复路径；阻塞时保存原因，不写 running。
- [ ] 在 3.9、3.12 跑完整 suite，补管理模式 Cursor/Gemini 不执行测试。
- [ ] 独立提交：fix(cli): enforce dispatch gate across execution entrypoints。

### Task 2: F02：服务端取消终态、依赖与幂等门禁（V-01、V-02、V-06）

**Files:** V remote.go、plans.go、remote_integration_test.go、plan_integration_test.go；新建 workspace_regression_test.go。

**Interfaces:** CreateRemoteJob / ClaimRemoteJob / AppendRemoteEvents / CancelPlan；保留既有 API，派发指纹包含规范化 PlanID；最终领取以事务内 Plan/依赖/版本事实为准。

- [ ] 将复核的 5 个测试从 /tmp/keji_review_regression_test.go 迁入常驻测试文件，移除临时数据库诊断；先确认前述失败能够稳定复现。
- [ ] 修复取消标记不能被迟到 pause/completed 覆盖；终态 Plan 不因 quota reconcile 再排队。统一 Plan/job/runner 锁顺序并测试与 cancel、append 竞争。
- [ ] Create 与 claim 均检查适用 Plan 状态、依赖验收和工具可用性；将额度状态重查纳入最终领取的协调边界，不留下单独 reconcile 提交后的无保护窗口。
- [ ] digest 加入解析后的 PlanID；相同目标重试返回相同 job，不同 Plan 同 key 返回冲突，不创建额外 attempt。
- [ ] 两个并发 claim 只允许一个有效 attempt；额外验证取消先提交、派发后提交的次序。
- [ ] 独立提交：fix(timetrace): fence plan claims and cancellation。

验收序列：
```text
claim(A) → cancel(A) → delayed waiting_quota → available sample → claim
assert Plan.status == cancelled
assert second claim returns no job
assert attempt count == 1
```

### Task 3: F03：额度身份、provider 映射与单次探针（V-03、V-07、T-03）

**Files:** V quota.go、quota_model.go、remote.go、quota_integration_test.go；T cli/keji/quota.py、agent.py、tests/test_quota.py、test_agent.py、fixtures/codex_ratelimits.json。

**Interfaces:** payload_from_reading → QuotaSampleInput → providerAvailabilityDB；保留完整限制维度。provider 从注册 RunnerTool.Provider 获取，Runner 使用明确 provider 信息，不截取 profile 名。

- [ ] 加入真实 payload→HTTP ingest→claim 回归：总池 primary=100%、模型池 primary=6%，任意上报顺序都不能把总池 blocked 覆盖成 available。
- [ ] schema additive 传递完整 scope/limit 身份；定义旧样本兼容规则，无法消歧时 unknown 且不能无人值守。禁止把旧数据猜测性拆成新池。
- [ ] 自定义 profile 对应 codex 时正确查询 codex；未绑定/不明身份显示阻塞，不能作为可用未知池。
- [ ] 用数据库唯一 reservation 协调池/限制窗口探针；同一窗口多 job、多 runner 只允许一个，claim 和 reservation 原子提交。
- [ ] profile↔账号池精确绑定仍不在本批扩展：无法确定共享资源身份时禁止无人值守探针；可继续展示和采样。不得凭 provider 近似宣称精确账户可运行。
- [ ] 测周额度耗尽+短窗恢复、陈旧样本、倒计时归零、auto-resume-off；公共 link_only 信号不改变 claim。
- [ ] 双仓库独立提交并记录兼容部署次序（仅记录，不部署）。

### Task 4: F04：租约与 checkpoint 安全恢复（T-04、T-05）

**Files:** T cli/keji/agent.py、dispatch.py、checkpoints.py、worktree.py、tests/test_agent.py、test_checkpoints.py、test_dispatch.py。

**Interfaces:** checkpoint 保存真实 execution_path、provider/profile/session、HEAD、dirty digest、有效输出位置；恢复消费同一身份，不能 silent fallback start。

- [ ] 用可控时钟使 prepare_workspace 跨过 lease deadline，断言 adapter.start/resume 都未调用。
- [ ] 准备阶段维持/检查 lease；持锁后、实际 spawn 前重新核验 lease、取消、能力。续租失败或授权变化立即停止，不依赖第一次 future timeout 才处理。
- [ ] 记录真实执行 worktree 和文件状态；有 checkpoint 但 session 缺失、provider/profile 改变、能力降级或目录不符时进入 waiting_input，保留 checkpoint 与原因。
- [ ] 测自动恢复必须使用原 session；没有 checkpoint 的已开始任务不能伪装首次启动；人工重开须明确动作，不算自动恢复。
- [ ] 用两个独立进程测试 agent/scheduler 同时进入、路径别名、进程崩溃和子进程仍存活；旧进程尚在写时不得释放为新执行资格。
- [ ] 独立提交：fix(cli): fence leases and validate resume checkpoints。

### Task 5: F05：统一人工验收与目标推进（V-04）

**Files:** V plans.go、remote.go、plan_integration_test.go、remote_integration_test.go。

**Interfaces:** AcceptPlan 是唯一验收权威；旧 complete_review 对已关联 Plan 不允许绕过 required criteria/evidence。响应遵循 expected_revision/current revision。

- [ ] 加回归：有未验 criteria 的 Plan 调旧 complete_review，不得让 Task completed。
- [ ] 将 Plan accepted、关联待验收 job 完成、活跃占位释放和 Task 聚合放在一致事务；Plan 运行/失败/暂停状态也从执行事实正确投影。
- [ ] Task/目标按已确认范围与权重聚合：一个 Plan accepted 不等于整个 Task 完成；cancelled 不计交付，不能未经确认缩小目标分母。
- [ ] 旧入口缺少完整验收输入时返回需使用新验收接口的明确错误；不能自动构造“全部通过”。
- [ ] 测两 Plan 一成功一未验收、重复 accept、revision 冲突、跨用户证据、accept/cancel 并发。
- [ ] 独立提交：fix(timetrace): unify human acceptance lifecycle。

### Task 6: F06：保护旧同步与运行时 Plan 数据（V-05，支撑 T-07）

**Files:** V model.go、sync.go、plan_migration_test.go、app_integration_test.go；T ios/KeJi/Store/AppStore.swift、AppStore+Tasks.swift。

**Interfaces:** 服务端 remote-owned AIExecution/Task 状态字段白名单保护；本地可编辑描述不被一并禁止；Plan 来源是版本化 API，不是旧快照。

- [ ] 对真实远程执行提交较新的旧 sync，尝试覆盖 status、remote_job_id、end/result/duration，断言权威列不变、合法用户编辑字段仍可改。
- [ ] 以服务端现有归属判断 remote-owned，不能让请求先清掉 remote_job_id 再绕过保护。
- [ ] 服务端首次任务→Plan 建立使用稳定 ID、幂等；iOS 新建和同步后即时刷新 Plan，避免只有重启才补出。
- [ ] 测失败不能改成完成、重复同步不双计、离线重连不回退新 revision。
- [ ] 独立提交：fix(timetrace): protect execution facts from legacy sync。

### Task 7: F07：迁移语义与访客合并（V-08、V-12）

**Files:** V plan_migration.go、sync.go、repository.go、plan_migration_test.go、merge_test.go。

**Interfaces:** MigratePlans 仅补需要默认 Plan 的旧任务；moveUserData 同事务迁移新增用户域数据与关联。

- [ ] 建“仅自定义 Plan”的任务，执行两次迁移，断言不增默认 Plan；旧无 Plan 任务仍恰好一个默认 ID。
- [ ] 建旧访客任务→迁移默认 Plan→登录已有账户，断言 Plan/时间/执行关联可达、无悬空 ID、失败状态保留。
- [ ] 合并时显式处理目标账号已存在偏好、报告 revision、幂等反馈 key 的冲突；保留目的账号偏好，不静默覆盖，报告/反馈历史保留可追溯来源。
- [ ] 仅在全部关联移动成功后删除 guest；任一步故障整事务回滚。测试重试幂等。
- [ ] 在隔离数据库演练备份恢复、行数/归属/权重校验；不连接生产数据库。
- [ ] 独立提交：fix(timetrace): preserve plans across migration and account merge。

### Task 8: F08：iOS 真正的 Plan 闭环（T-06、T-07）

**Files:** T ios/KeJi/Networking/WorkspaceClient.swift、Endpoints.swift、Store/AppStore.swift、AppStore+Plans.swift、AppStore+Tasks.swift、Features/Plans/PlanDetailView.swift；KeJiTests/PlanSyncTests.swift、WorkspaceContractTests.swift；KeJiUITests/WorkspaceFlowTests.swift。

**Interfaces:** 现有 WorkspaceClient 的 Plan 读取/写入连接 Store；dispatch 使用真实远程 job 接口及期望 revision；只在服务端 accept 成功后更新 accepted。

- [ ] 用 URLProtocol stub 验证真实 View→Store→Client 路径，初始 running/cancelled Plan 不能本地验收。
- [ ] 移除生产路径 markPlanAccepted 直接写状态；验收表提交完整 criteria/evidence，等待回执。离线只能保存草稿，不能解锁依赖或推进目标。
- [ ] 派发按钮实现请求、进行中防重复、成功 job 状态及失败原因；429/离线/409 不显示成功。
- [ ] 409 展示当前版本并让用户重审，不自动覆盖重试；应用恢复前台、创建任务、远程事件后刷新 Plan。
- [ ] UI 测试执行创建任务→即时出现 Plan→派发→等待→待验收→确认；断网/取消/冲突必须可解释。
- [ ] 独立提交：fix(ios): connect authoritative plan workflow。

### Task 9: F09：报告事实、跨日去重与版本（V-09、V-10 日报、T-09）

**Files:** V reports.go、remote.go、reports_test.go；T ios/KeJi/Stats/Stats.swift、Features/Timeline/TimelineProjection.swift、Features/Reports/ReportsView.swift、KeJiTests/StatsTests.swift、ReportsScopeTests.swift。

**Interfaces:** 事件阶段事实→独立人工/AI/等待区间→用户 IANA 日界限裁剪；报告 revision 不覆写旧版本；缺失度量为 unknown，不当 0。

- [ ] 通过真实 job/events 产生报告，不直接注入最终秒数；重复事件/多个 attempt 不重复成果。
- [ ] 人工重叠区间取并集；AI 不同 attempt 的合法并行独立累计，不能把不同工具并行误去重；三类时间不能相加为个人投入。
- [ ] 修日界限切片与 DST；23:50–00:10 在两天各计 600 秒。iOS 生产 ReportsView 消费同口径，不只测试工具函数。
- [ ] 用用户/日期级事务锁或原子版本分配，双请求不产生通用 500；离线补报保留原 revision。
- [ ] 真实覆盖率由证据产生，79% 不给总分；无记录/未知/零分别显示。日报仍为私有草稿。
- [ ] 分仓库提交，保存跨端相同 fixture 的预期数值。

### Task 10: F10：推荐与真正门禁共用规则（V-11）

**Files:** V plans.go、scoring.go、plan_test.go、scoring_test.go、plan_integration_test.go。

**Interfaces:** recommendation 只读消费 F02/F03 的相同资格判断，不领取 lease 或消耗探针；claim 始终重新核验，推荐结果不是授权票据。

- [ ] 构造依赖完成但 runner 离线/额度 blocked/计费 unknown/已有 job 的 Plan，eligible 必须 false，reason_codes 对应真实原因。
- [ ] goal/urgency 使用项目目标与期限；unlock 计算下游解锁贡献，不用本项依赖已满足替代；缺输入注明未知和样本量，不写固定伪分。
- [ ] 验证 P0–P3 人工分组优先、组内分数稳定排序、等待时间不跨越硬门禁。
- [ ] 验证推荐产生后状态变化，实际 claim 拒绝；推荐调用不会改变数据库执行状态。
- [ ] 独立提交：fix(timetrace): base recommendations on facts and gates。

### Task 11: F11：偏好并发、反馈持久化和账号隔离（V-10 偏好、T-08）

**Files:** V account.go、account_test.go；T ios/KeJi/Features/Settings/FeedbackView.swift、Persistence/PreferencesStore.swift；新建 Persistence/FeedbackDraftStore.swift、KeJiTests/FeedbackDraftStoreTests.swift；修改 KeJiTests/UserPreferencesTests.swift。

**Interfaces:** expected_revision=0 首写冲突返回 409/current revision；FeedbackDraftStore 按 userID + draftID 持久化内容与稳定 idempotency key。

- [ ] 用 barrier 同时提交两个首写偏好请求，断言一个成功、一个 409，不能 500；现有 CAS 行为保持。
- [ ] 反馈提交前先持久化草稿及 key；请求失败、页面返回和重启复用同 key；只有收到服务端回执才显示“已提交”并清理。
- [ ] 在线接口接入若仍延期，准确显示“仅本机草稿”，不声称已发给服务端；本包不偷换成完整 V6 实现。
- [ ] 按账号隔离偏好/草稿；退出或换账号不可显示上个账号内容；输入秘密与诊断字段测试脱敏/拒绝规则，不能上传环境快照。
- [ ] 补两个设备重复反馈、相同 key 不同内容的契约测试；核验限流并发，不用 count→create 竞争当可靠限流。
- [ ] 双仓库独立提交：fix(account): persist drafts and resolve preference conflicts。

### Task 12: F12：常驻端到端回归与二轮审查

**Files:** V 全部 *_test.go；T cli/tests/、ios/KeJiTests/、ios/KeJiUITests/WorkspaceFlowTests.swift；新建 tests/integration/test_workspace_flow.py 及对应测试运行说明。

**Interfaces:** 隔离真实 Valley HTTP + 真实 Python Runner + fake adapter；iOS 针对同契约验证，不把 fake 能力提升为生产 can_enforce_zero_spend。

- [ ] 把一次性脚本改成可重复 suite，创建独立测试用户与数据库，日志保留两仓 SHA、测试数、SKIP、事件/lease/session ID，不输出令牌。
- [ ] 全链验证：新建→派发→限额→checkpoint→个人额度核验→原会话恢复→人工验收→正确日报；另跑取消、旧事件、周耗尽、未知计费、多 runner、断网补报。
- [ ] 运行下列完整矩阵，新增测试计数应记录实际值，不把旧 51/124/62 当固定通过配额。
- [ ] 对 21 个报告问题逐项标注提交 SHA、测试名称及证据；代码确认问题尤其要补真正可运行的失败/修复测试。
- [ ] 二轮审查不含 merge、生产迁移、部署、App Store 提交。真实工具/订阅验证另需用户授权；做不到验证则保留管理模式与无人值守关闭。

## 测试命令与完成标准

Git 命令使用 DEVELOPER_DIR=/Library/Developer/CommandLineTools；xcodebuild 不设该变量。不要为测试签许可或关闭全部现有模拟器；只使用指定测试设备。

Valley（工作目录 Valley review/执行 worktree）：
```sh
LC_ALL=C APP_DSN_TIMETRACE_TEST='host=127.0.0.1 port=54329 user=postgres dbname=valley_timetrace_test sslmode=disable client_encoding=UTF8' go test -race -json ./internal/apps/timetrace/ -count=1
```
只使用隔离测试实例。数据库连接失败、任何集成 SKIP 视为验收失败。

TimeTrace CLI（工作目录 cli）：
```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools /usr/bin/python3 -m unittest discover -s tests
DEVELOPER_DIR=/Library/Developer/CommandLineTools /opt/homebrew/bin/python3.12 -m unittest discover -s tests
```

iOS（工作目录 ios）：
```sh
xcodegen generate
xcodebuild test -project KeJi.xcodeproj -scheme KeJi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KeJiTests
xcodebuild test -project KeJi.xcodeproj -scheme KeJi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KeJiUITests/WorkspaceFlowTests
```
Busy/preflight 可 boot 指定测试设备后重试，保留第一次失败及重试日志；应用断言失败不是模拟器 flake。

## 范围边界与修复映射

- 21 项复核问题全部映射 F01–F11；F12 提供共同验收。
- V-01/02/06→F02；V-03/07→F03；V-04→F05；V-05→F06；V-08/12→F07；V-09/10(日报)→F09；V-11→F10；V-10(偏好)→F11。
- T-01/02→F01；T-03→F03；T-04/05→F04；T-06/07→F08；T-08→F11；T-09→F09。
- 明确延期保持：完整 profile↔账号池管理、报告/额度等全面在线接线、V6 异步导出/注销/设备解绑回执。不把这些混入修复工作量或宣称已完成。
- 发布自动续跑的额外前提：精确可用账号绑定、真实工具原会话验证、可靠零新增计费保证。缺一项则只能验收“安全阻塞/管理模式”，不能验收“自动续跑可上线”。
- 本轮无工期承诺；每批以可验证退出条件推进，不以提交数量认定完成。

