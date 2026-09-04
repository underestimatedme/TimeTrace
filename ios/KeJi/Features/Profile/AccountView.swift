import SwiftUI

/// Extra page (not in the prototype): guest → verified account upgrade, logout, delete.
struct AccountView: View {
    @Environment(\.theme) private var theme
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync

    @State private var identifier = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDelete = false

    private var isLoggedIn: Bool { sync.isLoggedIn }

    var body: some View {
        SubPageScaffold(title: "账号") {
            Card {
                Text(isLoggedIn ? "已登录" : "游客账号").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 4)
                Text(isLoggedIn ? (sync.user?.accountLabel ?? sync.user?.nickname ?? "已登录") : "数据仅保存在此设备的游客会话中")
                    .font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                HStack(spacing: 4) {
                    Text("同步状态：").foregroundStyle(theme.textMuted)
                    Text(sync.status.label).foregroundStyle(theme.textSecondary)
                }
                .font(Typo.sans(Typo.xs)).padding(.top, 8)
            }
            .padding(.bottom, 24)

            if !isLoggedIn {
                SectionTitle("用手机号或邮箱登录")
                Text("登录后游客数据会合并到你的账号，并可在多设备间同步。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 12)
                FormField(label: "手机号 / 邮箱") {
                    HStack(spacing: 8) {
                        AppTextField(placeholder: "输入手机号或邮箱", text: $identifier, keyboard: .emailAddress)
                        AppButton(codeSent ? "重新发送" : "发送验证码", variant: .secondary, size: .md,
                                  disabled: busy || identifier.isEmpty) { sendCode() }
                    }
                }
                FormField(label: "验证码") {
                    AppTextField(placeholder: "6 位验证码", text: $code, keyboard: .numberPad)
                }
                AppButton("登录", variant: .accent, fullWidth: true, disabled: busy || identifier.isEmpty || code.isEmpty) { login() }
                    .padding(.bottom, 24)
            } else {
                AppButton("退出登录", variant: .secondary, fullWidth: true, disabled: busy) { logout() }.padding(.bottom, 24)
            }

            if let message {
                Text(message).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary).padding(.bottom, 16)
            }

            SectionTitle("危险操作")
            AppButton("删除账号", variant: .danger, fullWidth: true, disabled: busy || !sync.hasSession) { confirmDelete = true }
            Text("删除账号会永久移除云端与本机的全部数据。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 8)
        }
        .alert("删除账号？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { deleteAccount() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可恢复。")
        }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> String) {
        busy = true
        message = nil
        _Concurrency.Task {
            do {
                message = try await work()
            } catch {
                message = "\(label)失败：\(error.localizedDescription)"
            }
            busy = false
        }
    }

    private func sendCode() {
        run("发送") {
            try await sync.sendCode(identifier: identifier.trimmingCharacters(in: .whitespaces))
            codeSent = true
            return "验证码已发送"
        }
    }

    private func login() {
        run("登录") {
            try await sync.login(identifier: identifier.trimmingCharacters(in: .whitespaces), code: code.trimmingCharacters(in: .whitespaces))
            code = ""
            return "登录成功，数据已合并"
        }
    }

    private func logout() {
        run("退出") {
            await sync.logout()
            return "已退出登录，当前为游客"
        }
    }

    private func deleteAccount() {
        run("删除") {
            try await sync.deleteAccount()
            router.popToRoot()
            router.phase = .onboarding
            return "账号已删除"
        }
    }
}
