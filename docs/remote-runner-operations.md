# 刻迹远程 Runner 运维说明

## 身份绑定

1. Mac 执行 `keji cloud login`，Valley 创建 10 分钟有效的 device code，并返回 8 位 user code 和 `verification_uri`（`keji://pair?code=<USERCODE>&name=<电脑名>&platform=darwin&v=1`）。
2. CLI 在终端打印同一形式的二维码（Unicode 半块字符，白底黑码；纯标准库编码，byte 模式、纠错 M，放不下时退到 L，版本 1–6；电脑名过长时省略 `name`），下方仍打印 8 位码作为后备。二维码里只有 user code 和展示用的电脑名，没有 device code 或任何 token；拍到二维码的人仍需要登录后的手机账号确认才能绑定。
3. 已登录（非游客）的 iOS 用户任选一种方式提交 user code，都会先调用 inspect 显示电脑名/平台/版本，再由用户点「确认绑定」调用 approve；Valley 在事务中把该授权记录绑定到当前 `tt_users.id`：
   - 「你的 AI → 扫码绑定」：App 内相机（AVFoundation）只识别 `keji://pair` 二维码；模拟器或无相机权限时给出说明，改用手输。
   - 系统相机扫码或点开 `keji://pair` 链接：App 通过 `keji` URL scheme 打开，切到「你的 AI」、预填授权码并直接弹出确认框；未登录时先显示登录提示，登录后自动继续核对。
   - 手动输入 8 位码后点「检查电脑」。
4. CLI 只轮询 device code；批准后用一次性 activation code 换取 Runner 专用 access/refresh token。它不会获得手机账号密码或用户 token。
5. refresh token 通过 Security.framework 存入当前 macOS 登录用户的 Keychain；access token 仅驻留内存并每 15 分钟轮换。Claude/Codex 继续使用该 macOS 用户原有的本地登录态，任何厂商凭据都不上传 Valley。

## 多台电脑

一个账号可以绑定多台电脑，每台各自运行 `keji cloud login`。手机「我的 → 设备与授权」列出全部电脑：

- 「重命名」调用 `PATCH /runners/:id`（`{"name": "..."}`，去掉首尾空白后 1–80 个字符；只能改自己的、未解绑的电脑，其余一律 404）。名字只影响刻迹里的显示，派发与额度仍按 Runner ID。
- 「解绑这台电脑」调用 `DELETE /runners/:id`：吊销该电脑的 Runner 凭据并取消还在等它的任务。

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
- 领取通过 PostgreSQL `FOR UPDATE SKIP LOCKED`、单 Runner 活动租约和 lease epoch 防止重复执行；Agent 每 30 秒续租，事件必须严格递增且终态不可回退。
- 本机先把领取记录和回传事件写入 SQLite。网络中断时完成事件保留在 outbox，恢复后重放。
- Valley 同步投影对应的任务和 AI 执行记录，远程状态不依赖当前手机页面，App 重启或换设备后仍可恢复。
- 手机取消远程任务时只提交 desired action；Agent 收到后终止整个 CLI 进程组并回传 `cancelled`，手机收到确认前保持“等待电脑确认”。

生产环境设置独立的 `TIMETRACE_REMOTE_ENCRYPTION_KEY_V1`，并将 `TIMETRACE_REMOTE_ENCRYPTION_KEY_VERSION=1`。轮换时先同时配置旧、新版本密钥，再提高版本号；数据行记录 key version，因此轮换期间旧任务仍可解密。未配置 V1 时仅开发环境回退到 TimeTrace pepper，生产发布检查不得接受该回退。

## 运行状态

- 电脑在线：Agent 每 5 秒领取一次任务；每次领取轮询就是一次心跳，Valley 按最近 2 分钟内有无心跳实时判定在线，手机上的「在线 / 离线」与派发闸门用同一口径。
- 额度与工具清单上报时机：`keji cloud login` 成功后立即一次；`keji agent run` 启动时；空闲时每 5 分钟；每个任务结束后；被限流时；`--once` 模式也会上报。工具登录状态变化（例如退出登录）会在下一次上报时重推清单。
- 采集来源：Codex 走 `codex app-server` 的额度接口；Claude Code 用本机 OAuth 登录调用其 `/usage` 命令所用的用量接口（凭据来自 `~/.claude/.credentials.json`，macOS 上通常在钥匙串项「Claude Code-credentials」）。套餐等级来自各自的本地登录信息，只上报等级字符串。
- 电脑休眠/关机：任务停留在 Valley 队列；不会转到云端执行。**定时任务**（手机上指定了执行时刻）在到点时若电脑在睡眠，会在唤醒后执行，不会丢；需要准点执行时，用 `caffeinate -dims` 保持唤醒，或 `sudo pmset -a sleep 0`（接电源时可用 `sudo pmset -c sleep 0`）。
- Keychain 锁定、Claude/Codex 退出登录或额度耗尽：Runner 应上报等待/失败状态，由手机明确展示。
- 零付费核验：每次派发前 Runner 实测工具是订阅登录（Claude `auth status`、Codex `login status`）且环境/配置里没有 API key 路径；
  不通过就以 `billing_unverified` 拒绝派发，`keji agent doctor` 可查看原因。启动工具时所有计费相关环境变量都被剔除。见 `cli/README.md`「零付费核验」。
- LaunchAgent 日志：`~/.keji/daemon.log` 与 `~/.keji/daemon.err`。

## 发布门槛

- Valley TimeTrace 单元/集成/race 测试通过；迁移在空库与存量备份上通过。
- CLI 全套测试以及 Claude/Codex 当前版本、登录状态探针通过；目标机器上 `keji agent doctor` 的零付费核验对要派发的工具显示「通过」。
- iOS 单元、HTTP 契约和 UI 流程通过。
- 测试环境完成 iPhone 蜂窝网 → Valley → Mac → Valley → iPhone 的真实闭环。
- 生产前完成电脑重启、网络断开重连、重复派发、过期租约和至少 24 小时稳定性验证。
