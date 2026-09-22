import SwiftUI

/// Explicit account identity prevents reuse of another account's editor state.
struct FeedbackView: View {
    let userID: String?
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        if let userID {
            FeedbackEditor(userID: userID, storage: appEnv.feedbackDraftStore)
                .id(userID)
        } else {
            SubPageScaffold(title: "反馈") {
                Text("请先建立账号会话，再填写反馈。")
            }
        }
    }
}

private struct FeedbackEditor: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @State private var model: FeedbackModel

    init(userID: String, storage: FeedbackDraftStore) {
        // One-time seed; the parent keys this editor by account identity.
        _model = State(initialValue: FeedbackModel(userID: userID, storage: storage))
    }

    var body: some View {
        SubPageScaffold(title: "反馈") {
            Text("请勿填写密码、令牌、邮箱或环境信息。正文仅保存在本机，收到服务器工单回执后才显示已提交。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 16)
            Card {
                TextEditor(text: $model.text)
                    .frame(minHeight: 120)
                    .font(Typo.sans(Typo.sm))
                    .scrollContentBackground(.hidden)
                    .disabled(model.draft.attempted || model.receipt != nil)
                    .accessibilityIdentifier("feedback.text")
            }
            .padding(.bottom, 12)

            Toggle(isOn: $model.attachDiagnostics) {
                Text("附带诊断信息（默认关闭，仅 App 版本与设备型号）")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
            }
            .disabled(model.draft.attempted || model.receipt != nil)
            .accessibilityIdentifier("feedback.diagnostics")
            .padding(.bottom, 12)

            AppButton(model.submitting ? "提交中…" : "提交反馈", variant: .accent, fullWidth: true,
                      disabled: !model.canSubmit) {
                Task { await model.submit(using: store.workspaceClient) }
            }
            .accessibilityIdentifier("feedback.submit")

            Text(model.status).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                .padding(.top, 12).accessibilityIdentifier("feedback.status")
            if model.draft.attempted && model.receipt == nil {
                Text("为避免重复建单，重试会发送首次提交的正文。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
        }
    }
}
