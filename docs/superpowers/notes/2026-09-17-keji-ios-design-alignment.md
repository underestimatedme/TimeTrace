# 刻迹 iOS · 设计对齐变更说明（2026-09-17）

分支 `feature/ios-app`，**未推送**。基线计划：`docs/superpowers/plans/2026-09-14-keji-ios.md`。
真相源：`design/src/review/`（只读）。

## 做了什么

| 提交 | 内容 |
| --- | --- |
| `ddec463` | `.light` 调成 `glass.css` 的冰晶白（`--g-bg` `#f5f9ff`、`--g-blue` `#1680ff` 等），并设为默认主题 |
| `71fed1b` | 卡片、按钮、分段控件改用 `--g-panel` 半透明面板 + `--g-shadow` 低饱和冷投影 |
| `ba17bc1` | Plan 完成后措辞改为「结果待确认」；未测量的时长显示「未测量」，不再 `?? 0`；评分改为「样本不足，暂不计算」 |
| `28840f0` | 报告页改为交付优先：「N 个 Plan 已验收」+ ChangeLog + 下一步建议，时间拆分保留在下方 |
| `aa2ef98` | 报告页改版后，UI 测试滚动到时间拆分再断言 |
| `14cdc89` | Plan 详情新增分派策略（均衡 / 速度优先 / 节省额度 / 手动），经 `PATCH /plans/:id` 落库，运行中锁定并说明原因 |
| `30e9956` | 项目卡片显示「N / M Plan 已验收」；项目详情新增版本目标与目标范围 |
| `659b9c4` | Plan 详情新增「自然恢复后自动续跑」开关，等待额度时仍可关闭 |
| `ea46fd3` | AI 页改为按额度池渲染的工具卡片，额度窗口明细收进详情 |
| `a6e168e` | 时间线拆成「我 / AI」双列，新增项目筛选与轨道筛选 |
| `8e7d499` | 新增深海蓝主题、跟随系统、强调色（冰蓝 / 鸢紫），新增「设备与授权」页 |

## 数据契约

- `DailyReport` 的 `human_seconds` / `ai_seconds` / `waiting_seconds` / `estimated_value_minor` /
  `actual_spend_minor` 保持 Optional，`nil` 渲染为「未测量」，没有任何 `?? 0` 兜底。
- 额度读数过期显示「待核验」、缺失显示「未知」，都不画进度条，也不显示成满额。
- 样本覆盖率不足时不显示总分，文案为设计稿的「样本不足，暂不计算」。
- 分派策略的取值 `balanced / speed / saver / manual` 来自 Valley `normalizeExecutionPolicy`，
  `max_additional_spend_minor` 恒为 0，未新增或修改任何跨仓接口。

## 没做 / 故意不做

- **设计稿的「查看提交与验收证据」「查看评分依据」**：设计稿自己标注这些是演示记录，
  目前没有真实证据来源，不做假页面。
- **「公共重置信号」（BetterOPC 链接）**：Valley 有 `/v1/reset-signals`，iOS 端未对接，不放假链接。
- **AI 页的全局「自动续跑」开关**：Valley 里 `allow_auto_resume` 是每个 Plan 的字段，
  偏好接口没有全局项。做成全局要改跨仓契约，现按现有契约放在 Plan 详情。
- **App 内撤销设备授权**：`/v1` 没有撤销接口，页面写明需在电脑上停止 Runner。
- **视觉重建**：目前只完成了颜色 token 化，排版、圆角、间距、控件样式、今日页 banner
  与图片资源尚未按设计稿重做。已与用户确认排在功能之后单独做。

## 视觉重建（2026-09-18 追加）

功能九步完成后，用户指出「比设计稿难看」，确认先做完功能、再统一做视觉。这一轮：

| 提交 | 内容 |
| --- | --- |
| `2c8b8e9` | `glass.css` 的字号/字距/圆角/内边距进 `Glass`（有单测）；分区标题恢复正常大小写；卡片圆角 21、内边距 22、顶部白色内高光；主按钮圆角 14/高 44/描边内高光/投影；底栏模糊与选中圆点 |
| `03b22a5` | 今日页头部重建：30px 问候语、42px 头像、183px 雪山 banner、目标进度格；`design/src/review/assets` 四张图复制进 `Assets.xcassets` |
| `...` | 玻璃分段控件替换原生 segmented（时间线 / 分派策略 / 强调色）；项目详情任务列表改为细分隔线长列表；项目名 23px |
| `a34b7e4` | 报告 hero 48px 交付数字、AI 额度数值 32px、我的页 58px 头像与 20px 名字、额度条 6px 加内发光、徽章圆角 6 |
| `...` | 深色主题下雪山 banner 压到 26% 不透明度（对应设计稿 `[data-theme=dark] .gl-hero>img`），否则浅色图上的浅色文字不可读 |

过程中两次自己的失误，已修正并记录：
- 雪山 banner 初版用 `scaledToFill` 直接放进 ZStack，把整页撑出横向溢出（违反 390 宽约束）。
  改为放进 `background`，不参与布局尺寸。
- 有一次提交前把 `DEVELOPER_DIR` 指向 CommandLineTools，`xcodebuild` 直接报错退出，
  当时没看输出就提交了；事后补跑确认通过。`DEVELOPER_DIR` 只该给 git 用。

## 遗留问题

1. **视觉仍未完全对齐**：AI 页与「我的」页的页面级层次、`gl-orb` 圆形图标容器、
   今日页的人机协作流（`collaboration-ribbon`）、启动页的 `glass-hero` 尚未使用。
   深色主题只逐页看过今日页。
2. **`00-总纲.md` 的 Valley 路径过期**：文档写的 `.worktrees/valley-workspace-review` 不存在；
   其所述分支 `codex/keji-ai-workspace-fixes` 实际在 `/opt/coding/planb/github/Valley`
   （而文档说该检出没有刻迹代码）。本次契约以该检出为准，另一个 worktree
   `valley-timetrace-remote-runner`（`codex/keji-ai-workspace`）内容一致。
3. **`--ui-testing` 下的偏好持久化**：原先完全不落盘，导致偏好类设置无法验证跨启动保留。
   已改为写入独立的 `keji-ui-testing` UserDefaults suite，并在 `--sample-data` 时重置。
4. **未推送**：全部提交停在本地 `feature/ios-app`，等人工确认后再推。

## 验证

- `xcodebuild test`（KeJiTests）：112 通过，0 失败。
- `bash ios/scripts/run-qa.sh`（含 KeJiUITests，fixture 服务器已手动启动）：见 `ios/qa-artifacts/`。
- 390×844 截图（与设计稿同尺寸，iPhone 16e 模拟器）：今日 / 项目 / 时间线 / AI / 我的 /
  报告 / 项目报告，无横向溢出。视觉重建后的一套在
  `ios/qa-artifacts/390x844-visual-rebuild/`，重建前的基线在 `390x844-design-compare/`。
