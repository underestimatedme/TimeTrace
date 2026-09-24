# 2026-09-24 · iOS 命名本地化与首次使用打磨

## 做了什么

- **主屏幕名称随系统语言**：简体中文「刻迹」，其他语言「TimeTrace」。`en.lproj` / `zh-Hans.lproj` 下各一份
  `InfoPlist.strings`，未匹配语言回落 `TimeTrace`（`CFBundleDevelopmentRegion: en`）。工程、scheme、产物名仍是 KeJi，
  bundle id 不变。`ReleaseReadinessTests` 锁定两份文件都在包里。已在模拟器实际切换系统语言核对。
- **一级标签页不再显示无效「返回」**：`SubPageScaffold` 只在导航栈非空时画返回按钮。此前项目、AI 两个标签页根视图
  一直带着一个 `pop()` 为空操作的「返回」。
- **全新安装的空状态给出入口**：项目页「还没有项目」卡片带「新建第一条任务」；今日页「接下来」空卡片带「新建任务」。
  两者都推入 `taskCreate`，保存时 `ensureDefaultProject()` 会自动建默认项目。
- **调试参数 `--reset-state`**：启动前清掉本地持久化，UI 测试用它模拟全新安装。
- **TestFlight 脚本** `ios/scripts/asc_testflight.py`：用 App Store Connect API 查构建处理状态和测试组，或把构建加进组。
  凭据走 `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH`。

## 踩到的坑

- UI 测试里 `XCUIApplication.terminate()` 后立刻 `launch()`，上一个实例在退到 inactive 时还会落盘一次，
  会把新实例刚清掉的状态文件写回去，导致「全新安装」用例在整批运行时看到旧数据、单跑却通过。
  `launch` 助手里加了 `app.wait(for: .notRunning)`。
- 构建号按 `yyyyMMdd` + 两位序号编，注意跨天要换前缀（2026092303 之后是 2026092401，不是 2026092304）。

## 构建

- 2026092302：全新安装额度修复（用户上传）。
- 2026092303：中英文主屏幕名称。
- 2026092401：返回按钮 + 空状态入口。
