import SwiftUI

/// Notification categories, independent of the auto-resume policy.
struct NotificationPreferencesView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        SubPageScaffold(title: "通知") {
            Text("通知开关与自动续跑策略相互独立；关闭通知不影响你在应用内查看恢复状态。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 16)
            Card {
                toggle("验收提醒", id: "notif.acceptance",
                       get: { store.preferences.notifications.acceptance },
                       set: { v in store.updatePreferences { $0.notifications.acceptance = v } })
                Divider1().padding(.vertical, 4)
                toggle("失败提醒", id: "notif.failure",
                       get: { store.preferences.notifications.failure },
                       set: { v in store.updatePreferences { $0.notifications.failure = v } })
                Divider1().padding(.vertical, 4)
                toggle("恢复提醒", id: "notif.recovery",
                       get: { store.preferences.notifications.recovery },
                       set: { v in store.updatePreferences { $0.notifications.recovery = v } })
            }
        }
    }

    private func toggle(_ label: String, id: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: get, set: set)) {
            Text(label).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
        }
        .tint(theme.accent)
        .accessibilityIdentifier(id)
    }
}
