# 刻迹 · 分叉合并与零付费核验（2026-09-23）

## 背景

9/17 之后 TimeTrace 上出现两条平行工作线：`feature/ios-app`（远端，9/17–9/19 共 30 个提交，设计对齐、上架前置、
自查修复）与 `codex/keji-ai-workspace-fixes`（本机 worktree，9/22 共 9 个提交，F09–F12 整改：报告事实、
会话绑定的反馈、Runner outbox 原子性、跨仓集成套件）。两者从 `95940f5` 分叉，16 个文件双方都改过。
Valley 侧对应的 7 个 9/22 提交（`feac72f..eac7a19`）此前未推送。

## 合并决定（6 个冲突文件）

| 领域 | 采用 | 理由 |
| --- | --- | --- |
| 反馈 | codex 线：`FeedbackDraftStore` + `FeedbackModel`，草稿按账号目录落盘，提交绑定会话身份，回执校验正文一致 | 是整改 F11 的实现；远端线只有单草稿、无账号隔离 |
| 反馈请求体 | 远端线：`FeedbackBody(draft:)` 含 `include_diagnostics` | Valley `POST /feedback` 真实接受该字段；诊断为 opt-in 布尔，不带环境内容。`Endpoint.feedback` 保留 codex 的客户端拒绝规则（凭据/邮箱/环境/超长） |
| 偏好持久化 | 两者叠加：codex 的按账号 key（`keji.preferences.v2.<base64 userID>`）+ 远端的 `--ui-testing` 独立 suite 与 `--sample-data` 重置 | UI 测试需要跨启动验证持久化；账号隔离是整改要求 |
| 偏好同步 | 远端线：与 Valley 三方合并；同步基准也按账号隔离；每次 await 后确认账号未切换 | 跨设备同步是 I4 范围；账号切换中途不能写错人 |
| 离线身份 | 新增 `SyncEngine.offlineIdentity = "local-offline"`：离线模式下偏好与反馈草稿都用它 | 离线模式仍要保留主题等选择；登出后（在线、无账号）不读不写任何持久化偏好 |
| fixture 服务器 | 两种反馈场景并存：`feedback-*` 先 503 再成功（重试/重启），`feedback-ok-*` 直接 201 | 两条线的 UI 用例都保留 |

删除了远端线上与 codex 实现重复的 `AppStore.submitFeedback`、`PreferencesStore.savePendingFeedback`、
`WorkspaceClient.submitFeedback(_:) -> FeedbackTicket`、`Endpoint.createFeedback`、`FeedbackTicket`。

## 零付费核验（第 2 项决定）

此前 Claude/Codex adapter 把 `can_enforce_zero_spend` 硬编码为 false，统一门禁一律 `billing_unverified`，
真实环境一个任务都派不出去。现在改为**每次派发前实测**（`cli/keji/billing.py`）：

- Claude：`claude auth status` 须为 `loggedIn=true`、`authMethod=claude.ai`、`apiProvider=firstParty`、有 `subscriptionType`；
  `~/.claude/settings.json` 不得有 `apiKeyHelper` 或计费 `env`。
- Codex：`codex login status` 须为 `Logged in using ChatGPT`；`~/.codex/auth.json` 须 `auth_mode=chatgpt` 且无 `OPENAI_API_KEY`。
- 两者：环境不得含 `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_BASE_URL`/`CLAUDE_CODE_USE_*`/`OPENAI_API_KEY`/
  `CODEX_API_KEY`/`OPENAI_BASE_URL`；启动工具进程时这些变量一律从子进程环境剔除（`run_streaming(drop_env=)`）。
- 结论缓存 5 分钟；`Agent._capability_zero_spend` 在 spawn 前强制重新核验；`keji agent doctor` 逐工具打印结论与原因。
- 不改跨仓契约：上报 Valley 的 inventory 仍只有 `can_enforce_zero_spend` 布尔；`adapter_version`/`verified_at`/`unsupported_reason`
  在本机 `capability_details()` 与 doctor 输出中。

本机实测两者均通过（Claude `claude.ai/team`，Codex `chatgpt`），见 `cli/探针验证记录-2026-09-02.md`「探针 D」。
这不等于「无人值守续跑已上线」：真实工具 smoke、24 小时稳定性、真机闭环仍是发布门槛。

## 验证

- iOS `KeJiTests`：160 通过。
- iOS `KeJiUITests`（手动起 fixture 服务器）：见提交信息中的计数。
- CLI `python3 -m unittest discover -s tests`：213 通过（新增 21 个计费核验用例）。
- 跨仓集成 `tests/integration/run.sh`（配对 Valley `eac7a19`，隔离 PostgreSQL 54329）：6 通过；Valley 侧 `TestWorkspacePythonIntegration` PASS。

## 遗留

- iOS CI（`.github/workflows/ios.yml`）没有启动 fixture 服务器，UI 用例在 CI 上必失败；下一步在 workflow 里加一步后台启动。
- 反馈页失去了远端线上的「最多 N 字」提示文案；现文案为「仅本机草稿，尚未提交」等，功能不缺。

## TestFlight（追加）

- `0.1.0 (2026092301)` 已归档并上传 App Store Connect（自动签名，team `HZ788934TW`；`ExportOptions-AppStore.plist`
  的 `destination=upload` 让 `-exportArchive` 直接上传，本地无 IPA）。
- Valley 侧准备了 `release/timetrace-ai-workspace` = `codex/keji-ai-workspace-fixes` + `origin/main`（无冲突，构建通过），
  加了一个提交让配对集成测试在没有隔离库时 skip 而不是 Fatal（否则 Valley 流水线的 `go test ./...` 必红）。
  推送该分支即触发生产部署，**由用户决定何时推**。
- iOS UI 测试：合并后 21 项通过（20 项首轮 + 修复离线偏好持久化后补跑 5 项全过）。

## 生产部署（追加，用户授权）

- `publish.yml` 对 `release/**` 只跑测试与镜像，部署需 `workflow_dispatch` 且 `deploy=true`（总纲与旧 memory 里「推 release 即发布」已过期）。
- 第一次部署成功后 curl 探测：`/quota` `/preferences` `/runners` `/bootstrap` 由 404 变 401，游客会话下均 200；
  但 `/reports?date=…&zone=Asia/Dubai` 返回 422，只有 `zone=UTC` 能过。根因：运行镜像 `alpine:3.20` 没有 zoneinfo，
  `time.LoadLocation` 对所有非 UTC 时区失败并映射为 ErrInvalidInput。修复：`internal/apps/timetrace/tzdata.go`
  嵌入 `time/tzdata`，Dockerfile 加 `apk add tzdata`；第二次部署后复测见下文。
- 第二次部署（含 tzdata 修复）后，新游客会话下 `GET /reports?date=2026-09-23&zone=Asia/Dubai|Asia/Shanghai|America/New_York` 均 200，
  `POST /reports {zone: Asia/Dubai}` 返回 revision 1 的草稿。模拟器直连生产：「我的」页显示「已同步」，
  报告页显示「时区 Asia/Dubai · 本地草稿」且无「时区不匹配」错误，「你的 AI」页正确提示游客不能绑定 Runner。
- iOS CI 在加 fixture 后由 8 个失败降到 1 个，剩余的是「报告时区写死 Asia/Dubai」和「小屏模拟器上时间拆分区块在屏幕外」，
  均已改测试；同时把完整 xcodebuild 日志作为 CI 产物上传，失败时打印断言行。

## CI 收尾与一个首次安装 bug（追加）

- CI 依次修掉：fixture 服务器未启动（8 个失败）→ 报告时区写死 → 小屏模拟器上时间拆分区块在屏幕外 → runner 无「iPhone 16」设备名 →
  runner 默认选到 Xcode 16.4（现改为优先 Xcode 26.x，按 UDID 动态选一台可用 iPhone）。
- 最后一个失败暴露了真实 bug：`AIToolsView` 只在页面出现时拉一次额度；全新安装时游客会话尚未建立，首次请求失败后不再重试，
  AI 页永远拿不到真实额度。本机钥匙串里残留着 UI 测试会话，所以本地一直是绿的。已在本机 `xcrun simctl keychain reset` 后复现红灯，
  改为 `.task(id: sync.user?.id)`（会话身份出现/变化即重拉）后变绿。
- GitHub Actions 最终结果：run 35795340671 成功，160 单元 + 21 UI 全过（Xcode 26.3，动态选取的 iPhone 模拟器，fixture 服务器由 CI 启动）。
- 构建 `2026092302`（含该修复）已归档，上传时 Xcode 账号会话失效（Failed to Use Accounts），待用户在 Xcode 重新登录后上传。
