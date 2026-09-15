import SwiftUI

/// SubPageLayout.tsx: sticky header with `← 返回`, centered title, optional trailing action; scrollable body.
struct SubPageScaffold<Content: View, Action: View>: View {
    @Environment(\.theme) private var theme
    @Environment(AppRouter.self) private var router
    let title: String
    @ViewBuilder var action: () -> Action
    @ViewBuilder var content: () -> Content

    init(title: String, @ViewBuilder action: @escaping () -> Action = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.action = action
        self.content = content
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { content() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack {
            HStack {
                Button { router.pop() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left").font(.system(size: 17, weight: .regular))
                        Text("返回").font(Typo.sans(Typo.sm))
                    }
                    .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("subpage.back")
                Spacer()
                action().frame(minWidth: 60, alignment: .trailing)
            }
            Text(title)
                .font(Typo.sans(Typo.sm, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.bg.opacity(0.95))
        .overlay(alignment: .bottom) { Divider1() }
    }
}

/// Centered "不存在" placeholder used by detail pages.
struct MissingPlaceholder: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.sans(Typo.sm))
            .foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
    }
}
