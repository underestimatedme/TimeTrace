# 子任务 02 · Valley 后端（刻迹 timetrace 模块）

> 先读 `00-总纲.md`，本文件只讲后端特有的部分。

---

## 你负责什么

补齐设计稿依赖、但后端还没有的能力，并为 Forge 运营后台提供 admin 接口。
后端不做 UI，但**设计稿决定了数据形状** —— 前端要展示的每一个字段，
后端都得有地方产出它。

**基线计划：`docs/superpowers/plans/2026-09-14-keji-valley.md`（V 系列任务）。**
（该文件在 TimeTrace 仓库：`/opt/coding/planb/github/TimeTrace/docs/superpowers/plans/`）
另有整改清单 `2026-09-15-keji-workspace-remediation.md`。

---

## ⚠️ 工作路径与分支（搞错分支会白干）

```
仓库    /opt/coding/planb/github/Valley
分支    codex/keji-ai-workspace-fixes
```

开工前先确认分支对：

```bash
cd /opt/coding/planb/github/Valley
git rev-parse --abbrev-ref HEAD       # 应为 codex/keji-ai-workspace-fixes
ls internal/apps/timetrace/ | wc -l   # 应为 36
```

**如果文件数只有十来个、没有 `plans.go` / `quota.go` / `reports.go`，
说明你在错误的分支上**（`main` 或 `codex/monimoni-followup` 上只有旧版 timetrace）。
在那里 grep 会让你以为 plans / reports / quota 这些接口根本不存在 —— 实际上都有。
先 `git checkout codex/keji-ai-workspace-fixes` 再开始。

该分支已合入 `origin/main`（合并提交 `4eac13d`），既有刻迹全部改动也跟得上主线。

---

## 工程约定（`Valley/CLAUDE.md`）

Valley 是 **Go 单二进制**：一个进程承载网关、平台层和多个业务 App。
新增 App = 加 `internal/apps/<name>` + 在 `cmd/server/main.go` 注册一行。

```bash
cp .env.example .env && set -a && . ./.env && set +a
docker compose up -d
make run          # make tidy / make test / make build
```

- `Makefile` 把 `GOCACHE` / `GOMODCACHE` 指向仓库内的 `.cache/`，**不要改成全局路径**
- 一 App 一逻辑库（`Config.Validate` 强制），同一个 PostgreSQL 实例不同 dbname
- `VALLEY_AUTO_MIGRATE=true` 是单副本 MVP 的有意选择；**改 schema 前先备份**
- 生产：推 `main` 即自动部署，发布任一 App 会重启同进程的其他 App
- **不要推 `main`，不要碰 `release/**`**

---

## 模块现状

`internal/apps/timetrace/`：

```
app.go                路由注册（RegisterPublicRoutes / RegisterAdminRoutes）
repository.go         仓储入口
model.go              核心领域模型
account.go/_handlers  账号、设备授权
plans.go/_model/_handlers/_migration   Plan 生命周期与迁移
quota.go/_model       额度三态、样本摄入、共享池探测
remote.go/_model/_handlers             远程 Runner、Job、Attempt、Event、租约
reports.go/report_model.go/_handlers   日报（phase-facts-v2）
scoring.go            生产力评分
reset_signals.go      公共重置信号（link_only 隔离）
sync.go               客户端全量/增量同步
```

测试覆盖较厚（`*_integration_test.go`、`workspace_regression_test.go` 等），
改动时先扩测试。

### 已有的 `/v1` 接口

```
POST   /v1/auth/guest | /auth/send-code | /auth/login | /auth/refresh | /auth/logout
DELETE /v1/account
GET    /v1/bootstrap                      POST /v1/sync
GET    /v1/tasks/:task_id/plans           POST /v1/tasks/:task_id/plans
PATCH  /v1/plans/:plan_id
POST   /v1/plans/:plan_id/accept | /cancel | /retry
GET    /v1/plans/:plan_id/recommendation
GET    /v1/reports                        POST /v1/reports
GET    /v1/quota
GET    /v1/preferences                    PUT  /v1/preferences
GET    /v1/feedback                       POST /v1/feedback
GET    /v1/reset-signals
GET    /v1/runners                        PUT  /v1/runner/inventory
POST   /v1/device-authorizations | /token | /approve | /inspect | /activate
POST   /v1/runner/session/refresh | /runner-auth/refresh
POST   /v1/remote-jobs                    GET  /v1/remote-jobs/:id
POST   /v1/remote-jobs/:id/commands
POST   /v1/runner/jobs/claim | /runner/jobs/:id/events
POST   /v1/runner/attempts/:id/events | /renew
POST   /v1/runner/quota/samples
GET    /v1/stats | /content/version
```

### 已有的 `/admin` 接口

```
GET /admin/stats        ← 就这一个
```

**Forge 需要的一切列表与详情接口都还不存在。这是你的主要工作量之一。**

---

## 工作项

### A. 为 Forge 建 admin 接口面

照 `internal/apps/continenttrail/app.go` 的 `RegisterAdminRoutes` 写法。
关键契约（Forge 的 `valleyDataProvider` 依赖它）：

- 列表 handler 交给 `httpx.OK(c, gin.H{"list": ..., "total": ...})`，
  最终线上形状是 `{"code":"OK","data":{"list":[...],"total":N}}`
- 单条：`{"code":"OK","data":{...}}`
- `/stats`、`/dashboard` 返回普通对象（同样包在 `data` 里），由仪表盘页直接读

需要的资源（最终清单与 Forge 侧对齐，见 `03-`）：

```
GET /admin/dashboard                     概览
GET /admin/users        /admin/users/:id
GET /admin/projects     /admin/projects/:id
GET /admin/tasks        /admin/tasks/:id
GET /admin/plans        /admin/plans/:id
GET /admin/runners      /admin/runners/:id
GET /admin/remote-jobs  /admin/remote-jobs/:id
GET /admin/quota
GET /admin/reports
GET /admin/feedback     PATCH /admin/feedback/:id      （处理状态流转）
```

统一支持分页、排序、按用户 / 项目 / 时间范围过滤。
参考 `continenttrail` 的 `bindAdminQuery(c)`。

**admin 接口是只读为主**。写操作只开放运营确实需要的（如反馈状态流转），
**不要**开放能篡改用户执行事实、验收结果、额度记录的接口 ——
这些是审计证据，运营改了就不可信了。

### B. 守住 phase-facts-v2 的语义

`reports.go` 刚完成重构（commit `95bd8d8`）。往下做的时候：

- 新增的任何聚合都要区分 `known` / `unknown`，**不得把 unknown 当 0 参与计算**
- `estimated_value_minor` / `actual_spend_minor` 在有真实金额来源之前保持 `null`，
  不要为了让前端好看而填一个估算值
- admin 接口同样遵守这条 —— Forge 的报表也不许出现伪造的零

### C. 沿用已有的并发栅栏

`GenerateDailyReport` 用 `lockUserPlanGraph(tx, user.ID)` 拿事务级栅栏，
保证快照一致 + 跨进程串行分配 revision（空日也要）。

新增任何会改动 Plan 图、额度或报告 revision 的写路径，**必须走同一把锁**。
不要自己发明新的锁或用乐观重试绕过 —— 这批代码里有一长串
`fix(timetrace): fence ...` 的提交，就是在补这类洞。

### D. 补齐设计稿依赖的数据

对着 `design/src/review/glassModel.ts` 和 `data.ts` 逐字段核对：
设计稿要展示的每个字段，后端是否有产出？没有的话是加字段、加接口，
还是设计稿本身不该有？**拿不准就问，不要静默降级成假数据。**

---

## 必须跑的验证命令

```bash
cd /opt/coding/planb/github/Valley

make tidy
go build ./...
make test                                    # 全量
go test ./internal/apps/timetrace/...         # 本模块（约 3 分钟，有集成测试）
```

改了 admin 接口的话，另外用 `curl` 实际打一遍并贴出响应体，
确认 `{"code":"OK","data":{"list":[...],"total":N}}` 信封形状正确。

---

## 完成标准

- [ ] admin 接口面按信封契约落地，Forge 能直接消费
- [ ] admin 写操作范围克制，不可篡改执行事实 / 验收 / 额度审计数据
- [ ] 新增聚合严格区分 known / unknown，无「未知当零」
- [ ] 新增写路径复用 `lockUserPlanGraph` 栅栏
- [ ] 设计稿字段逐项核对完毕，缺口清单已列出
- [ ] `make test` 与 `go test ./internal/apps/timetrace/...` 全绿，贴出真实输出
- [ ] 接口契约（JSON 形状，含 `null` 位置）已写入文档并通知 iOS / Forge 两端
- [ ] 变更说明 + 遗留问题清单
