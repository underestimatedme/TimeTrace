# 刻迹远程 Runner 运维说明

## 身份绑定

1. Mac 执行 `keji cloud login`，Valley 创建 10 分钟有效的 device code，并返回 8 位 user code。
2. 已登录（非游客）的 iOS 用户在「AI 工具管理」输入 user code。Valley 在事务中把该授权记录绑定到当前 `tt_users.id`。
3. CLI 只轮询 device code；批准后用一次性 activation code 换取 Runner 专用 access/refresh token。它不会获得手机账号密码或用户 token。
4. refresh token 存入当前 macOS 登录用户的 Keychain；access token 15 分钟轮换。Claude/Codex 继续使用该 macOS 用户原有的本地登录态，任何厂商凭据都不上传 Valley。

## 首次启用

```sh
keji cloud login
keji workspace add /absolute/path/to/repository
keji agent doctor
keji agent run --once
keji agent install
```

只有 `workspace add` 明确登记的 Git 仓库会出现在手机端。每个任务在 `~/.keji/worktrees/` 下创建隔离分支，worktree 的远端 push URL 会被封锁。

## Valley 数据与安全

- device code、user code、activation code 和 Runner token 均只存摘要；待 CLI 读取的一次性 activation code使用 AEAD 加密。
- Prompt 使用 AEAD 加密落 PostgreSQL，普通用户响应不会返回 Prompt；只有归属 Runner 领取任务时解密。
- 作业创建要求用户、Runner、workspace 和 tool 同属一个账号，并使用 `(user_id, idempotency_key)` 去重。
- 领取通过 PostgreSQL `FOR UPDATE SKIP LOCKED` 和 lease epoch 防止重复执行；事件必须严格递增。
- 本机先把领取记录和回传事件写入 SQLite。网络中断时完成事件保留在 outbox，恢复后重放。

当前加密密钥由 Valley 的 TimeTrace pepper/JWT secret 派生。正式开启功能前应配置并迁移到独立、可轮换的远程任务 AEAD 密钥，再执行空库和存量库迁移演练。

## 运行状态

- 电脑在线：Agent 每 5 秒领取一次任务。
- 电脑休眠/关机：任务停留在 Valley 队列；不会转到云端执行。
- Keychain 锁定、Claude/Codex 退出登录或额度耗尽：Runner 应上报等待/失败状态，由手机明确展示。
- LaunchAgent 日志：`~/.keji/daemon.log` 与 `~/.keji/daemon.err`。

## 发布门槛

- Valley TimeTrace 单元/集成/race 测试通过；迁移在空库与存量备份上通过。
- CLI 全套测试以及 Claude/Codex 当前版本、登录状态探针通过。
- iOS 单元、HTTP 契约和 UI 流程通过。
- 测试环境完成 iPhone 蜂窝网 → Valley → Mac → Valley → iPhone 的真实闭环。
- 生产前完成电脑重启、网络断开重连、重复派发、过期租约和至少 24 小时稳定性验证。
