# 刻迹 (KeJi) — iOS

Native SwiftUI port of the `design/` prototype (iOS 17+, Swift 5 language mode, zero third-party packages).
Spec: `docs/superpowers/specs/2026-09-04-keji-ios-design.md`.

## Layout

```
ios/project.yml            xcodegen manifest (targets KeJi, KeJiTests)
ios/KeJi/App               KeJiApp (wiring), RootView (Splash→Onboarding→Tabs), AppRouter, MainTabView, LaunchOptions
ios/KeJi/Models            Codable domain types (snake_case JSON, RFC3339 dates), StateSnapshot, API models
ios/KeJi/Store             AppStore (@Observable reducers ported from useStore.ts), SampleData (mockData.ts)
ios/KeJi/Stats             Stats.swift (stats.ts), Format.swift (format.ts)
ios/KeJi/Persistence       StateStore — JSON file in Application Support (keji-state.json)
ios/KeJi/Networking        APIClient, Endpoints, KeychainStore, SyncEngine
ios/KeJi/Theme             Theme (4 palettes × 16 tokens), ThemeEnvironment (`@Environment(\.theme)`)
ios/KeJi/Components        Card, Badges, Buttons, Inputs, MetricCard, SectionTitle, SubPageScaffold, TaskCard…
ios/KeJi/Features          One folder per page
ios/KeJiTests              StatsTests, StoreReducerTests, SyncTests, SampleDataTests
```

## Generate, build, test

Requires Xcode 26.x and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd ios
xcodegen generate                       # produces KeJi.xcodeproj (git-ignored)
xcodebuild -project KeJi.xcodeproj -scheme KeJi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build test CODE_SIGNING_ALLOWED=NO
```

Run from Xcode (`open KeJi.xcodeproj`) or install on a booted simulator:

```sh
UDID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["devices"].__iter__().__next__())')
xcrun simctl install booted <DerivedData>/Build/Products/Debug-iphonesimulator/KeJi.app
xcrun simctl launch booted com.atlaspaces.keji --sample-data --screen today --offline
```

## Launch arguments (debug hooks)

| Argument | Effect |
|---|---|
| `--sample-data` | Load `createSampleData()`, mark onboarding done, skip Splash |
| `--screen <route>` | Jump to a page: `today`, `tasks`, `tasks/new`, `tasks/<id>`, `timeline`, `insights`, `profile`, `focus/<id>`, `ai/<id>`, `projects`, `projects/<id>`, `goals/<id>`, `ai-tools`, `appearance`, `account`, `onboarding`, `splash` |
| `--theme <name>` | `claude` \| `codex` \| `cursor` \| `light` |
| `--offline` | Disable all networking (fully usable offline) |
| `--api-base-url <url>` | Override the API base URL |

Sample ids: tasks `t1`…`t20` (`t2` is the running focus, `t3` the running AI execution, `t4` waiting review), projects `p1`…`p4`, goals `g1`…`g5`.

## Automated functional QA

```sh
bash ios/scripts/run-qa.sh                         # from the repository root
SIMULATOR_NAME='iPhone 16' bash ios/scripts/run-qa.sh
```

The scheme runs unit/HTTP-contract tests and `KeJiUITests` sequentially. UI coverage includes onboarding,
task creation, focus pause/resume/completion, AI task routing/pause/resume/cancellation/review,
all five tabs, project/goal/tool/account pages, four themes and persistence after relaunch.
Screenshots are attached to the `.xcresult` and exported under the timestamped `ios/qa-artifacts/` directory.
CI uploads `KeJi-test-results` even after test failures. Tests use offline mode;
HTTP tests intercept URLSession requests locally and do not contact production.

`--ui-testing` forces offline mode and selects `keji-ui-testing-state.json`, a separate persistence file.
`KEJI_OFFLINE=1` disables networking for the unit-test host. Do not use `--sample-data` without
`--ui-testing` when you want to preserve the simulator's normal app data.

离线 UI 测试仍使用显式模拟模式；正常联网模式通过 Valley 绑定电脑、选择本地 workspace/CLI 并派发真实远程任务。自动测试不等同于真机蜂窝网、电脑休眠恢复或 24 小时稳定性验证。

## API base URL

Resolution order: `--api-base-url` launch arg → `KEJI_API_BASE_URL` environment variable → `KEJI_API_BASE_URL` in Info.plist
(default `https://apis.atlaspaces.com/timetrace/api/v1`).

## Sync model

Local JSON state is the source of truth. Every mutation stamps `updated_at`, marks the entity dirty (or tombstoned)
and `SyncEngine` pushes `POST /sync` 2 s later; the merged `Bootstrap` snapshot is applied back while keeping entities that
became dirty in the meantime. `GET /bootstrap` runs on launch/foreground when nothing is pending. A guest session
(`POST /auth/guest`, 900 s access tokens, refreshed proactively) is created on first sync; 我的 → 账号 upgrades it with a
verification code. Network failures only change the status dot in 我的; they never block the UI.
