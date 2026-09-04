import SwiftUI

/// Splash.tsx: auto-advance after 2.5s or on tap.
struct SplashView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var pulse = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, theme.accent, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 96, height: 1)
                    .opacity(0.3)
                    .padding(.bottom, 48)
                Text("刻迹")
                    .font(Typo.sans(Typo.xl4, weight: .light))
                    .kerning(6)
                    .foregroundStyle(theme.text)
                    .padding(.bottom, 12)
                Text("让每一刻，都留下痕迹。")
                    .font(Typo.sans(Typo.sm))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.bottom, 64)
            }
            VStack(spacing: 16) {
                Spacer()
                Text("管理你的时间，也管理替你工作的 AI。")
                    .font(Typo.sans(Typo.xs))
                    .foregroundStyle(theme.textMuted)
                Text("点击进入")
                    .font(Typo.sans(Typo.xs))
                    .foregroundStyle(theme.textMuted)
                    .opacity(pulse ? 0.6 : 1)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
            }
            .padding(.bottom, 64)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .onAppear { pulse = true }
        .task {
            try? await _Concurrency.Task.sleep(nanoseconds: 2_500_000_000)
            if !_Concurrency.Task.isCancelled { advance() }
        }
    }

    private func advance() {
        guard router.phase == .splash else { return }
        router.phase = store.hasOnboarded ? .main : .onboarding
    }
}
