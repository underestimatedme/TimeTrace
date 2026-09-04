import SwiftUI

/// AppLayout + BottomNav (Layout.tsx): custom bar so colors follow the theme.
struct MainTabView: View {
    @Environment(\.theme) private var theme
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            Group {
                switch router.tab {
                case .today: TodayView()
                case .tasks: TasksView()
                case .timeline: TimeFlowView()
                case .insights: InsightsView()
                case .profile: ProfileView()
                }
            }
            .id(router.tab)
            .transition(.opacity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let active = router.tab == tab
                Button {
                    router.go(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: .light))
                            .frame(height: 22)
                        Text(tab.label)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundStyle(active ? theme.accent : theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(theme.bgElevated.opacity(0.95).background(.ultraThinMaterial))
        .overlay(alignment: .top) { Divider1() }
    }
}

/// Scrollable tab page body: `px-4 pt-4 pb-20`.
struct TabPage<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.bg)
    }
}

/// Two-column grid with 8pt gaps (`grid grid-cols-2 gap-2`).
struct TwoColumnGrid<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)],
                  alignment: .leading, spacing: spacing) {
            content()
        }
    }
}
