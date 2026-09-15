import SwiftUI

/// Rearrange which home modules show. Core modules (目标/待办/阻塞) are locked on.
struct HomeCustomizationView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        SubPageScaffold(title: "首页个性化") {
            Text("核心模块（目标 / 待办 / 阻塞）始终显示，无法隐藏。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 16)
            VStack(spacing: 8) {
                ForEach(HomeModule.allCases) { module in
                    Card {
                        HStack {
                            Text(module.label).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                            Spacer()
                            if module.isCore {
                                Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            } else {
                                Toggle("", isOn: Binding(
                                    get: { !store.preferences.hiddenModules.contains(module) },
                                    set: { on in store.updatePreferences { $0 = on ? $0.showing(module) : $0.hiding(module) } }
                                ))
                                .labelsHidden()
                                .tint(theme.accent)
                                .accessibilityIdentifier("home.module.\(module.rawValue)")
                            }
                        }
                    }
                }
            }
        }
    }
}
