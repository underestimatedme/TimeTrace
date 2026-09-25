import SwiftUI

/// Onboarding.tsx: 3 slides, dots, 开始使用 / 使用示例数据体验.
struct OnboardingView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @State private var current = 0

    private struct Slide { let title: String; let description: String; let icon: String }
    private let slides = [
        Slide(title: "看见时间去了哪里", description: "自动记录投入、等待、切换与返工。", icon: "◐"),
        Slide(title: "安排你与 AI 的工作", description: "把任务交给自己、Claude、Codex 或其他执行者。", icon: "◎"),
        Slide(title: "让每一次改变都能被验证", description: "刻迹会根据真实数据分析效率，并持续优化你的工作方式。", icon: "◉"),
    ]

    private var isLast: Bool { current == slides.count - 1 }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    Text(slides[current].icon)
                        .font(.system(size: Typo.xl5))
                        .foregroundStyle(theme.text)
                        .opacity(0.6)
                        .padding(.bottom, 32)
                    Text(slides[current].title)
                        .font(Typo.sans(Typo.xl, weight: .medium))
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                    Text(slides[current].description)
                        .font(Typo.sans(Typo.sm))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 280)
                }
                .id(current)
                .transition(.opacity)
                Spacer()

                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == current ? theme.accent : theme.border)
                            .frame(width: i == current ? 24 : 8, height: 8)
                            .onTapGesture { withAnimation { current = i } }
                    }
                }
                .padding(.bottom, 32)

                VStack(spacing: 12) {
                    if isLast {
                        AppButton("开始使用", variant: .accent, size: .lg, fullWidth: true) { start(useSample: false) }
                    } else {
                        AppButton("继续", variant: .accent, size: .lg, fullWidth: true) {
                            withAnimation(.easeInOut(duration: 0.25)) { current += 1 }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
        }
    }

    private func start(useSample: Bool) {
        store.completeOnboarding(useSample: useSample)
        router.go(.today)
        router.phase = .main
        _Concurrency.Task { await sync.syncOnForeground() }
    }
}
