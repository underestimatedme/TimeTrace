# 刻迹 iOS · 上架前检查清单

App：刻迹 / TimeTrace（工程名仍为 KeJi）· bundle id `com.atlaspaces.timetrace` · 当前版本 `0.1.0 (2026092504)`

主屏幕名称随系统语言：简体中文显示「刻迹」，其他语言显示「TimeTrace」（`ios/KeJi/Resources/{zh-Hans,en}.lproj/InfoPlist.strings`，
`ReleaseReadinessTests` 锁定）。App Store Connect 里的名称要按语言分别填：zh-Hans「刻迹」，en-US「TimeTrace」。

**推荐路线**：先 TestFlight 内部测试，真机跑通、和真实 Valley 联调过，再提交审核。

**当前状态（2026-09-24 凌晨）**：2026092301 与 2026092302 已上传；2026092303（中英文主屏幕名称）已上传并进入内部组；2026092401 修了一级标签页的死「返回」按钮并给空状态加了新建入口，已于 2026-09-24 22:50 上传，内部组会自动收入。Valley 新后端已部署到生产（`release/timetrace-ai-workspace`，
用 `gh workflow run publish.yml -f deploy=true` 手动 dispatch；release 分支推送本身只出镜像不部署）。
首次部署后发现所有非 UTC 时区的报告请求 422（alpine 镜像无 tzdata），已用 `time/tzdata` 嵌入 + 镜像装 tzdata 修复并重新部署。

## 一、必须由你完成（涉及账号与凭据）

- [x] 本机钥匙串已有 **Apple Distribution** 证书（team `HZ788934TW`），且已下载该 team 的
      `com.atlaspaces.timetrace` App Store 描述文件（2026-09-23 核实）
- [ ] 在 App Store Connect 确认 `com.atlaspaces.timetrace` 的 App 记录存在
      （提交历史里有 `align bundle identifier with App Store record`，应当已建好）
- [x] 上传构建包：`0.1.0 (2026092301)` 已于 2026-09-23 00:24 由 `xcodebuild -exportArchive` 上传
      （`ExportOptions-AppStore.plist` 的 `destination=upload` 会直接上传，见 `ios/README.md`）。
- [x] 上传 `2026092302`：含「全新安装时 AI 页拿不到额度」修复。2026-09-24 在 Xcode 重新登录 Apple 账号后
      用 `xcodebuild -exportArchive` 上传成功。不要测 2026092301
- [x] 上传 `2026092303`：主屏幕名称本地化（中文「刻迹」/ 英文「TimeTrace」），其余与 2026092302 相同。
      2026-09-24 01:23 由 `xcodebuild -exportArchive` 上传成功，已自动进入内部组
- [x] 上传 `2026092401`：项目 / AI 标签页不再显示无效的「返回」；全新安装的项目页和今日页有「新建任务」入口。2026-09-24 22:50 上传成功
- [x] 上传 `2026092501`：0.1 核心流程（配对错误可读、套餐与绝对重置时刻、派发带执行时间、执行记录带输出尾巴）。
      2026-09-25 02:58 用 `altool` + API 密钥上传成功（Xcode 账号会话又过期了，见 `ios/README.md`）。含审查前的两个缺陷，不要测
- [x] 上传 `2026092502`：审查修复版（新建任务不再列出离线电脑；「安排时间」在手机上先校验 2 分钟～30 天；422 有中文提示）。
      2026-09-25 03:3x 上传成功
- [x] 上传 `2026092503`：真机验收中发现并修复——额度窗口按时长归类（Codex prolite 只有一个 7 天窗）、卡片脚注显示重置时刻、
      同类窗口优先主限额、底部标签栏背景延伸到屏幕底边。2026-09-25 10:3x 上传成功
- [x] 上传 `2026092504`：任务状态解码容错（服务端曾写 todo / in_progress 导致派发后整份同步失败）。2026-09-25 12:5x 上传成功。**TestFlight 请测这个构建**
- [x] TestFlight：2026092303 已处理完成（VALID），内部组「诺乔测试群」自动收入了全部构建，3 位测试员。
      状态用 `ios/scripts/asc_testflight.py status` 查（需要 `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` 环境变量）
- [ ] 在 App Store Connect 提交审核

## 二、工程侧（已完成 / 待完成）

- [x] `PrivacyInfo.xcprivacy` 已加入并随包分发，有单元测试锁定（`ReleaseReadinessTests`）
- [x] `ExportOptions-AppStore.plist` 已存在
- [x] 动态字体、VoiceOver 标签已补齐
- [x] 打包命令见 `ios/README.md`「TestFlight archive」，Team ID 只在命令行传入，未写进 `project.yml`
- [x] `CURRENT_PROJECT_VERSION` 已递增到 `2026092504`（下次上传前再递增）
- [ ] 真机验证（玻璃模糊叠层的性能、深色主题）
- [ ] 与真实 Valley 联调（派发 / 验收 / 额度）。后端已上线；游客会话下 bootstrap / quota / preferences /
      reset-signals / runners 已用 curl 验证返回 200。派发与验收需要一台绑定的 Mac 跑 Runner，尚未做

## 三、App 隐私问卷（App Store Connect → App 隐私）

与 `PrivacyInfo.xcprivacy` 保持一致：

| 数据类型 | 是否收集 | 关联到用户 | 用于追踪 | 用途 |
| --- | --- | --- | --- | --- |
| 邮箱地址 | 是（登录验证码） | 是 | 否 | App 功能 |
| 电话号码 | 是（登录验证码） | 是 | 否 | App 功能 |
| 其他用户内容（任务、Plan、验收记录） | 是 | 是 | 否 | App 功能 |
| 其他诊断数据 | 仅用户在反馈里主动勾选时 | 否 | 否 | App 功能 |

- 追踪：**否**。没有第三方 SDK，没有广告标识符。
- 需申报原因的 API：`UserDefaults`（原因 `CA92.1`）。

改动数据采集时，三处要一起改：代码、`PrivacyInfo.xcprivacy`、这张表。

## 四、商店素材

- [x] 6.9" 截图（1320×2868，iPhone 17 Pro Max 模拟器，状态栏统一为 9:41 满电满格）：
      `ios/qa-artifacts/appstore-6.9in/`，共 6 张：今日、报告、项目详情、时间线、AI、Plan 详情。
      App Store Connect 目前以 6.9" 为必需尺寸，其余尺寸可由它缩放；如需单独提供 6.5" 再补
- [ ] 截图用的是示例数据（「刻迹用户」、示例项目），上传前确认你愿意用这些内容做宣传图
- [ ] App 图标 1024×1024（`Assets.xcassets/AppIcon` 已有，提交时确认无透明通道）
- [ ] 名称（zh-Hans「刻迹」、en-US「TimeTrace」）、副标题、关键词、描述、支持网址、隐私政策网址
- [ ] 年龄分级问卷

## 五、审核备注要写清楚

- App 需要登录才能用完整功能：提供一个**审核用演示账号**（验证码登录的话，要说明如何拿到验证码）
- 远程执行需要一台绑定的 Mac 运行 Runner；审核员没有这台电脑，
  要说明离线/示例数据模式可以体验主流程
- 额度数据来自用户本机工具，App 不代购、不转付费执行
