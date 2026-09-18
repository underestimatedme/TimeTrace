import SwiftUI

/// Profile.tsx (+ 账号 row and a tiny sync indicator).
struct ProfileView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @State private var confirmClear = false

    private struct MenuItem: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        var value: String?
        var route: Route?
    }

    private var accountLabel: String {
        if let user = sync.user, !user.isGuest { return user.accountLabel ?? user.nickname ?? "已登录" }
        return "游客"
    }

    private var menu: [MenuItem] {
        [
            MenuItem(icon: "person.crop.circle", label: "账号", value: accountLabel, route: .account),
            MenuItem(icon: "folder", label: "项目与目标", route: .projects),
            MenuItem(icon: "target", label: "每周时间目标", value: "\(store.settings.weeklyTimeGoalHours) 小时"),
            MenuItem(icon: "clock", label: "工作时间设置", value: "\(store.settings.workStartHour):00 – \(store.settings.workEndHour):00"),
            MenuItem(icon: "cpu", label: "你的 AI", route: .aiTools),
            MenuItem(icon: "desktopcomputer", label: "设备与授权", value: "电脑 Runner 与 AI 账号绑定", route: .devices),
            MenuItem(icon: "shield", label: "数据与隐私", route: .privacy),
            MenuItem(icon: "bell", label: "通知设置", route: .notifications),
            MenuItem(icon: "square.grid.2x2", label: "首页个性化", route: .homeCustomization),
            MenuItem(icon: "paintpalette", label: "主题与动效", value: store.preferences.themeMode.label, route: .appearance),
            MenuItem(icon: "bubble.left", label: "反馈", route: .feedback),
            MenuItem(icon: "info.circle", label: "关于刻迹", value: "v0.1.0"),
        ]
    }

    var body: some View {
        let today = Format.dayKey(store.now)
        let todayHuman = Stats.humanSeconds(store.timeSessions, day: today)
        let todayAI = Stats.aiActiveSeconds(store.timeSessions, day: today)

        TabPage {
            HStack(spacing: 16) {
                Image("avatar")
                    .resizable().scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .overlay(Circle().stroke(theme.accent.opacity(0.3), lineWidth: 1).padding(-2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.settings.name)
                        .font(Typo.sans(Glass.profileName, weight: .semibold)).foregroundStyle(theme.text)
                    Text("连续专注 \(store.settings.streakDays) 天").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                    syncIndicator
                }
            }
            .padding(.bottom, 24)

            TwoColumnGrid {
                StatCard(label: "今日人工", value: Format.duration(todayHuman), valueColor: theme.accent, valueSize: Typo.lg)
                StatCard(label: "今日 AI", value: Format.duration(todayAI), valueColor: theme.ai, valueSize: Typo.lg)
            }
            .padding(.bottom, 24)

            Card {
                HStack {
                    Text("默认专注时长").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text("\(store.settings.defaultFocusMinutes) 分钟").font(Typo.mono(Typo.sm)).foregroundStyle(theme.text)
                }
                .padding(.bottom, 12)
                Slider(value: Binding(
                    get: { Double(store.settings.defaultFocusMinutes) },
                    set: { v in store.updateSettings { $0.defaultFocusMinutes = Int(v) } }
                ), in: 15...90, step: 5)
                .tint(theme.accent)
            }
            .padding(.bottom, 16)

            Card(padding: 0, radius: Glass.groupRadius) {
                VStack(spacing: 0) {
                    ForEach(menu) { item in
                        menuRow(item)
                        if item.id != menu.last?.id { Divider1() }
                    }
                }
                .padding(.horizontal, 15)
            }
            .padding(.bottom, 24)

            VStack(spacing: 8) {
                AppButton("恢复示例数据", icon: "arrow.counterclockwise", variant: .secondary, fullWidth: true) { store.resetToSample() }
                AppButton("清除所有数据", variant: .danger, fullWidth: true) { confirmClear = true }
            }
        }
        .alert("清除所有数据？", isPresented: $confirmClear) {
            Button("清除", role: .destructive) {
                store.clearAll()
                router.phase = .onboarding
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本地与云端的任务、时间记录都会被删除。")
        }
    }

    private var syncIndicator: some View {
        let color: Color
        switch sync.status {
        case .idle: color = theme.success
        case .syncing: color = theme.ai
        case .offline: color = theme.textMuted
        case .error: color = theme.danger
        }
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(sync.status.label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).lineLimit(1)
        }
        .padding(.top, 2)
    }

    private func menuRow(_ item: MenuItem) -> some View {
        Button {
            if let route = item.route { router.push(route) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(theme.textSecondary).frame(width: 21)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label).font(Typo.sans(13, weight: .medium)).foregroundStyle(theme.text)
                    if let value = item.value {
                        Text(value).font(Typo.sans(Glass.tiny)).foregroundStyle(theme.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if item.route != nil {
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(theme.textMuted).accessibilityHidden(true)
                }
            }
            .frame(minHeight: Glass.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.route == nil)
    }
}
