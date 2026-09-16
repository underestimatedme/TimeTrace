# 子任务 01 · TimeTrace / iOS App 重构

> 先读 `00-总纲.md`，本文件只讲 iOS 端特有的部分。

---

## 你负责什么

把 `ios/` 下的 SwiftUI App 重构到与 `design/src/review/GlassWorkspace.tsx`
（浅色玻璃稿）一致 —— 视觉、导航结构、交互状态机三者都要对齐，
并补齐设计稿里已有但 App 还没做的功能。

**基线计划：`docs/superpowers/plans/2026-09-14-keji-ios.md`（I 系列任务）。
开工第一件事是读完它，逐条核对代码里的真实完成情况。**
另外 `docs/superpowers/plans/2026-09-15-keji-workspace-remediation.md` 里有
iOS 相关的整改项，一并纳入。

规格：`docs/superpowers/specs/2026-09-04-keji-ios-design.md`

---

## 工程现状

```
仓库    /opt/coding/planb/github/TimeTrace
分支    feature/ios-app
```

```
ios/project.yml            xcodegen manifest（KeJi.xcodeproj 是生成物，git 忽略）
ios/KeJi/App               KeJiApp、RootView(Splash→Onboarding→Tabs)、AppRouter、MainTabView、LaunchOptions
ios/KeJi/Models            Codable 领域类型（snake_case JSON、RFC3339 时间）、StateSnapshot
ios/KeJi/Store             AppStore（@Observable，对应设计稿 useStore.ts）、SampleData
ios/KeJi/Stats             Stats.swift、Format.swift
ios/KeJi/Persistence       StateStore —— Application Support 下的 keji-state.json
ios/KeJi/Networking        APIClient、Endpoints、KeychainStore、SyncEngine
ios/KeJi/Theme             Theme.swift（4 套配色 × 16 个 token）、ThemeEnvironment
ios/KeJi/Components        Card、Badges、Buttons、Inputs、MetricCard、SubPageScaffold、TaskCard…
ios/KeJi/Features          每页一个目录：
                           Today Projects Tasks Plans Timeline AIExecution AITools
                           Reports Insights Profile Settings Appearance Focus Onboarding Splash
ios/KeJiTests              StatsTests、SampleDataTests、ReportsScopeTests、
                           RemoteExecutionTests、TimelineProjectionTests
ios/KeJiUITests            FunctionalUITests、WorkspaceFlowTests
ios/TestSupport/workspace_server.py   UI 测试用的 fixture 服务器
ios/scripts/run-qa.sh      自动化功能 QA
```

约束：iOS 17+，Swift 5 language mode，**零第三方依赖**。这一条不要打破 ——
设计稿用了 Phosphor 图标库，iOS 端需要用 SF Symbols 或自带资源替代，
不要为了对齐图标去引包。

---

## 重点对齐项

### 1. 导航结构（当前与设计稿不一致，这是主要工作量）

`ios/README.md` 里记录的 `--screen` 路由是**旧导航**（today / tasks / timeline /
insights / profile）。新导航是：

```
底部五入口：今日 | 项目 | 时间线 | AI | 我的
```

- 「报告」从**今日页右上角**进入，返回时回到来源页（不是固定回今日）
- 「项目报告」从项目详情页进入，范围限定当前项目
- 「我的」下挂个人中心全部子页，子页返回「我的」且**保留底部导航**

改完导航后同步更新 `ios/README.md` 的 `--screen` 路由表 —— 那张表是调试入口的
真相源，留着旧路由会让后续所有截图调试走错路。

### 2. 玻璃视觉语言

`design/src/review/glass.css` 是色彩 / 圆角 / 模糊 / 阴影的唯一定义。
把它翻译进 `ios/KeJi/Theme/Theme.swift` 的 token 体系，**不要在各个 View 里
散落硬编码颜色**。

设计稿已确认的取向（见 `design/design-qa.md` 五项保真检查）：
冰晶白底、冰蓝强调、低饱和阴影；深蓝主标题 + 灰蓝辅助信息；
系统字体（SF / PingFang 回退），**不要试图复刻原图的字体文件**。

**状态必须同时有文字，不能只靠颜色区分** —— 这是已经过 QA 的无障碍要求。

深色主题也要可读（`design/` 里已单独验证过）。

### 3. 「结果待确认」

Plan 执行完成后的状态措辞是**「结果待确认」**，不是「处理中」。
这是设计稿明确改过的用词，因为它要对应「可验收」这个动作。全局检查一遍文案。

### 4. 报告：null 不是 0

后端 `phase-facts-v2` 会返回 `null`（详见 `00-总纲.md`）。
iOS 的 `DailyReport` 模型对应字段必须是 **Optional**：

```swift
var humanSeconds: Int?
var aiSeconds: Int?
var waitingSeconds: Int?
var estimatedValueMinor: Int64?   // 目前恒为 nil，没有金额测量来源
var actualSpendMinor: Int64?      // 同上
```

渲染规则：`nil` → 明确的「未测量」文案；**不得** `?? 0`。
样本不足时不显示总分。已有的 `ReportsScopeTests.swift` 是这块的起点，
先扩充它，看它失败，再改实现。

### 5. 验收闭环与依赖门禁

- 验收条件全部勾选才能提交，提交后周目标进度与报告同步更新
- 依赖未验收的 Plan 不可执行：UI 禁用 **并说明原因**，不要只是灰掉
- 运行中锁定工具选择
- 周额度耗尽 → Plan 进入等待，**不转付费执行**；额度恢复后可续跑原会话；
  自动续跑关闭时只补额度、不自动运行，需在 Plan 详情手动继续

---

## 跑起来看：调试入口

```sh
cd ios
xcodegen generate
xcodebuild -project KeJi.xcodeproj -scheme KeJi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build test CODE_SIGNING_ALLOWED=NO
```

直达某一页截图（不用手点）：

```sh
xcrun simctl launch booted com.atlaspaces.timetrace \
  --sample-data --screen today --offline
```

`--screen` 可选值见 `ios/README.md`（改完导航后记得更新那张表）。
其他开关：`--theme claude|codex|cursor|light`、`--offline`、`--api-base-url <url>`、
`--ui-testing`（强制离线 + 使用独立的 `keji-ui-testing-state.json`）。

样本 id：任务 `t1`…`t20`（`t2` 正在专注、`t3` 正在 AI 执行、`t4` 待验收），
项目 `p1`…`p4`，目标 `g1`…`g5`。

---

## ⚠️ 跑 UI 测试前必须先手动起 fixture 服务器

```sh
python3 ios/TestSupport/workspace_server.py    # 监听 18768
```

**这一步不会自动发生。** 服务器没起，`KeJiUITests` 会整批失败，
而且失败信息看起来像是业务代码坏了 —— 会浪费你大量时间去查一个不存在的 bug。

同样重要：**上一次遗留的僵死进程也会导致整批假性失败**。跑测试前先确认端口干净：

```sh
lsof -ti:18768 | xargs -r kill    # 清掉僵死进程
python3 ios/TestSupport/workspace_server.py &
```

---

## 必须跑的验证命令

说「完成」之前，以下全部要有真实输出：

```sh
# 1. 生成工程 + 单元测试
cd ios && xcodegen generate
xcodebuild -project KeJi.xcodeproj -scheme KeJi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build test CODE_SIGNING_ALLOWED=NO

# 2. 完整功能 QA（含 UI 测试，先起 fixture 服务器！）
lsof -ti:18768 | xargs -r kill
python3 ios/TestSupport/workspace_server.py &
bash ios/scripts/run-qa.sh

# 3. 关键页面截图对比
#    对每个底部入口 + 报告页 + 项目报告页，用 --screen 直达并截图，
#    与 design 稿同尺寸（390×844）并排比对
```

截图证据放 `ios/qa-artifacts/`（`run-qa.sh` 会按时间戳导出）。
**拿不到截图路径就说拿不到，不要编造路径。**

---

## 完成标准

- [ ] 底部五入口与设计稿一致，报告 / 项目报告入口位置正确，返回行为正确
- [ ] 玻璃视觉 token 化进 `Theme.swift`，无散落硬编码颜色
- [ ] 390×844 无横向溢出；深色主题可读；状态不只靠颜色
- [ ] 报告字段为 Optional，`nil` 显示「未测量」，无 `?? 0`
- [ ] 验收闭环、依赖门禁、额度等待三条主路径有 UI 测试覆盖
- [ ] `ios/README.md` 的 `--screen` 路由表已更新
- [ ] 上述验证命令全部跑过并贴出真实输出
- [ ] 变更说明 + 遗留问题清单
