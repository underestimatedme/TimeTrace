import SwiftUI

/// Feedback form. Submit is idempotent (a stable key per attempt); a failed
/// submit keeps the draft rather than losing it or inventing a ticket number.
struct FeedbackView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var text = ""
    @State private var attachDiagnostics = false
    @State private var status: String?
    @State private var submitting = false

    var body: some View {
        SubPageScaffold(title: "反馈") {
            Text("遇到问题或有建议？提交后会返回服务器工单号；网络失败时草稿会保留，可重试，不会重复建单。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 16)

            Card {
                TextEditor(text: $text)
                    .frame(minHeight: 120)
                    .font(Typo.sans(Typo.sm))
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("feedback.text")
            }
            .padding(.bottom, 12)

            Toggle(isOn: $attachDiagnostics) {
                Text("附带脱敏诊断信息").font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
            }
            .tint(theme.accent)
            .padding(.bottom, 16)

            AppButton(submitting ? "提交中…" : "提交反馈", variant: .accent, fullWidth: true,
                      disabled: submitting || !FeedbackDraft.new(text: text).isValid) {
                submit()
            }
            .accessibilityIdentifier("feedback.submit")
            .onAppear {
                // 恢复上次没提交成功的草稿；「草稿已保留」这句话必须是真的。
                if text.isEmpty, let pending = store.pendingFeedback {
                    text = pending.text
                    attachDiagnostics = pending.attachDiagnostics
                    status = "上次的反馈还没提交成功，已恢复草稿。"
                }
            }

            if let status {
                Text(status).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                    .padding(.top, 12).accessibilityIdentifier("feedback.status")
            }
        }
    }

    private func submit() {
        submitting = true
        _Concurrency.Task {
            let outcome = await store.submitFeedback(text: text, attachDiagnostics: attachDiagnostics)
            submitting = false
            switch outcome {
            case .submitted(let ticketId):
                status = "已提交，工单号 \(ticketId)。"
                text = ""
                attachDiagnostics = false
            case .savedOffline:
                status = "已保存草稿（离线）。恢复网络后重新提交，不会重复建单。"
            case .failed(let message):
                status = message
            }
        }
    }
}
