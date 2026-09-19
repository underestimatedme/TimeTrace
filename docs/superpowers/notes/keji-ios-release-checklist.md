# 刻迹 iOS · 上架前检查清单

App：刻迹（KeJi）· bundle id `com.atlaspaces.timetrace` · 当前版本 `0.1.0 (2026091201)`

**推荐路线**：先 TestFlight 内部测试，真机跑通、和真实 Valley 联调过，再提交审核。

## 一、必须由你完成（涉及账号与凭据）

- [ ] 在本机钥匙串安装 **Apple Distribution** 证书（现在只有两个 Apple Development 证书，
      打不出上架包）
- [ ] 在 App Store Connect 确认 `com.atlaspaces.timetrace` 的 App 记录存在
      （提交历史里有 `align bundle identifier with App Store record`，应当已建好）
- [ ] 上传构建包：用 Xcode Organizer，或自己配 App Store Connect API 密钥后用
      `xcrun altool` / Transporter。**密钥和 Apple ID 密码不要交给 AI 代操作**
- [ ] 在 App Store Connect 提交审核

## 二、工程侧（已完成 / 待完成）

- [x] `PrivacyInfo.xcprivacy` 已加入并随包分发，有单元测试锁定（`ReleaseReadinessTests`）
- [x] `ExportOptions-AppStore.plist` 已存在
- [x] 动态字体、VoiceOver 标签已补齐
- [ ] 打包时填 `DEVELOPMENT_TEAM` 并打开签名。工程默认关闭签名是为了模拟器测试，
      见 `ios/scripts/run-on-device.sh` 的做法，**不要**把 Team ID 写死进 `project.yml`
- [ ] 每次上传前递增 `CURRENT_PROJECT_VERSION`（`project.yml`）
- [ ] 真机验证（玻璃模糊叠层的性能、深色主题）
- [ ] 与真实 Valley 联调（派发 / 验收 / 额度），目前只在本地 fixture 下验证过

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

- [ ] 截图：6.9" 与 6.5" 两种 iPhone 尺寸是必需的。现有 390×844 模拟器截图只用于设计对比，
      **不是**商店截图尺寸
- [ ] App 图标 1024×1024（`Assets.xcassets/AppIcon` 已有，提交时确认无透明通道）
- [ ] 名称、副标题、关键词、描述、支持网址、隐私政策网址
- [ ] 年龄分级问卷

## 五、审核备注要写清楚

- App 需要登录才能用完整功能：提供一个**审核用演示账号**（验证码登录的话，要说明如何拿到验证码）
- 远程执行需要一台绑定的 Mac 运行 Runner；审核员没有这台电脑，
  要说明离线/示例数据模式可以体验主流程
- 额度数据来自用户本机工具，App 不代购、不转付费执行
