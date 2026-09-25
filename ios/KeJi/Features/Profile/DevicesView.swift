import SwiftUI

/// 设备与授权：刻迹账号绑定电脑 Runner，Runner 内的工具配置绑定本机 CLI 账号。
/// 这里只展示 Valley 已知的 Runner；凭据不会出现在手机上。
struct DevicesView: View {
    @Environment(\.theme) private var theme
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @Environment(RemoteExecutionClient.self) private var remote
    @State private var pendingUnbind: RunnerInventory?
    @State private var unbindError: String?

    var body: some View {
        SubPageScaffold(title: "设备与授权") {
            if !sync.isLoggedIn {
                Card { Text("请先登录，再查看已绑定的电脑。游客账号不能批准 Runner。")
                    .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary) }
                    .padding(.bottom, 20)
            } else if remote.isLoading {
                ProgressView("正在读取设备…").frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if remote.runners.isEmpty {
                Card {
                    Text("还没有绑定的电脑").font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                    Text("在「你的 AI」页输入电脑上显示的 8 位授权码完成绑定。")
                        .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 4)
                }
                .padding(.bottom, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(remote.runners) { inventory in deviceCard(inventory) }
                }
                .padding(.bottom, 20)
            }

            Card {
                Text("刻迹账号绑定电脑 Runner；Runner 内的工具配置绑定本机 CLI 账号。凭据不发送到手机，撤销后停止新的派发。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).lineSpacing(4)
            }
            .padding(.bottom, 12)

            AppButton("如何连接新电脑", variant: .secondary, fullWidth: true) { router.push(.aiTools) }
                .accessibilityIdentifier("devices.pair")

            if let unbindError {
                Text(unbindError).font(Typo.sans(Typo.xs)).foregroundStyle(theme.danger).padding(.top, 12)
            }
        }
        .task { if sync.isLoggedIn { await remote.loadRunners() } }
        .confirmationDialog("解绑这台电脑？", isPresented: Binding(
            get: { pendingUnbind != nil }, set: { if !$0 { pendingUnbind = nil } }
        ), titleVisibility: .visible) {
            Button("解绑", role: .destructive) { unbind() }
            Button("取消", role: .cancel) { pendingUnbind = nil }
        } message: {
            Text("解绑后这台电脑不再接收任务，还在等它的任务会被取消；电脑端的 Runner 会自动清除本机凭据。要重新使用，在电脑上运行 keji cloud login。")
        }
    }

    private func deviceCard(_ inventory: RunnerInventory) -> some View {
        let online = inventory.runner.status == "online"
        return Card {
            HStack {
                Text(inventory.runner.name).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                Spacer()
                TintPill(text: online ? "在线" : "离线", color: online ? theme.success : theme.textMuted)
            }
            .padding(.bottom, 8)
            Text("\(inventory.runner.platform) · v\(inventory.runner.clientVersion)")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            Text("\(inventory.workspaces.count) 个工作区 · \(inventory.tools.map { $0.provider.label }.joined(separator: " / "))")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 2)
            if let seen = inventory.runner.lastSeenAt {
                Text("最近在线 \(Format.relative(seen, now: Date()))")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 2)
            }
            AppButton("解绑这台电脑", variant: .danger, size: .sm, fullWidth: true) { pendingUnbind = inventory }
                .accessibilityIdentifier("device.unbind.\(inventory.runner.id)")
                .padding(.top, 10)
        }
        .accessibilityIdentifier("device.\(inventory.runner.id)")
    }

    private func unbind() {
        guard let target = pendingUnbind else { return }
        pendingUnbind = nil
        _Concurrency.Task {
            do {
                try await remote.unbind(runnerID: target.runner.id)
                unbindError = nil
            } catch {
                unbindError = "解绑失败：\(error.localizedDescription)"
            }
        }
    }
}
