import SwiftUI

/// AITools.tsx
struct AIToolsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(RemoteExecutionClient.self) private var remote
    @Environment(AppRouter.self) private var router
    @State private var pairingCode = ""
    @State private var pairingMessage: String?
    @State private var pendingInspection: DeviceAuthorizationInspection?
    @State private var selectedPool: AccountQuotaPool?

    var body: some View {
        SubPageScaffold(title: "你的 AI") {
            Text("每个工具，都有清晰的工作边界。")
                .font(Typo.sans(Glass.body)).foregroundStyle(theme.textSecondary)
                .padding(.bottom, 6)
            Text("任务经 Valley 派发到已授权的 Mac，Claude/Codex 账号始终留在电脑本地。")
                .font(Typo.sans(Glass.small)).foregroundStyle(theme.textMuted)
                .lineSpacing(4)
                .padding(.bottom, 24)

            if let quota = store.accountQuota, !quota.pools.isEmpty {
                SectionTitle("工具与额度")
                VStack(spacing: 12) {
                    ForEach(quota.pools) { pool in
                        Button { selectedPool = pool } label: { toolCard(pool) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tool.\(pool.poolId)")
                    }
                }
                .padding(.bottom, 8)
                Text("倒计时归零显示为待核验，而非满额；未知不等于可用。点开工具可以看到每个额度窗口的明细。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 24)
            }

            if let signals = store.resetSignals { resetSignalsSection(signals) }

            if !sync.isLoggedIn {
                Card(borderColor: theme.accent.opacity(0.2)) {
                    Text("请先登录账号，再绑定电脑。游客账号不能批准 Runner。")
                        .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                    AppButton("去登录", variant: .accent, fullWidth: true) { router.push(.account) }
                        .accessibilityIdentifier("pairing.login")
                        .padding(.top, 10)
                }
            } else {
                Card(borderColor: theme.ai.opacity(0.25)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("绑定新电脑").font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                        Text("在 Mac 运行 `keji cloud login`，然后输入屏幕上的 8 位授权码。")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                        AppTextField(placeholder: "例如 A1B2C3D4", text: $pairingCode)
                            .textInputAutocapitalization(.characters)
                            .accessibilityIdentifier("runner-pairing-code")
                        AppButton("检查电脑", variant: .accent, fullWidth: true,
                                  disabled: pairingCode.trimmingCharacters(in: .whitespaces).count != 8) {
                            approvePairing()
                        }
                        .accessibilityIdentifier("runner-pairing-submit")
                        if let pairingMessage {
                            Text(pairingMessage).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }

            if remote.isLoading {
                ProgressView("正在刷新电脑状态…").frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            ForEach(remote.runners) { inventory in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(inventory.runner.name).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                            Spacer()
                            TintPill(text: inventory.runner.status == "online" ? "在线" : "离线",
                                     color: inventory.runner.status == "online" ? theme.success : theme.textMuted)
                        }
                        Text("\(inventory.workspaces.count) 个仓库 · \(inventory.tools.map { $0.provider.label }.joined(separator: " / "))")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                    }
                }
            }

            Card(borderColor: theme.accent.opacity(0.1)) {
                Text("任务 Prompt 会经 HTTPS 发送并加密存储于 Valley；代码、CLI 登录凭据和完整输出不会离开电脑。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).lineSpacing(4)
            }
            .padding(.top, 24)
        }
        .sheet(item: $selectedPool) { pool in poolDetail(pool) }
        // Keyed on the account identity: on a fresh install the page can appear before the
        // guest session exists, and that first request fails. Re-run once the session arrives.
        .task(id: sync.user?.id) {
            await store.refreshWorkspaceQuota()
            if sync.isLoggedIn { await remote.loadRunners() }
        }
        .confirmationDialog("确认绑定这台电脑？", isPresented: Binding(
            get: { pendingInspection != nil }, set: { if !$0 { pendingInspection = nil } }
        ), titleVisibility: .visible) {
            Button("确认绑定") { confirmPairing() }
            Button("取消", role: .cancel) { pendingInspection = nil }
        } message: {
            if let info = pendingInspection {
                Text("\(info.deviceName) · \(info.platform) · v\(info.clientVersion)\n请求时间：\(Format.relative(info.requestedAt, now: Date()))\n权限：仅接收任务、运行本机已登记仓库、回报状态及取消进程")
            }
        }
    }

    /// 一个工具一张卡：主数值 + 进度条 + 周额度副行，读数不新鲜就不画进度条。
    private func toolCard(_ pool: AccountQuotaPool) -> some View {
        let card = ToolQuotaCard(pool: pool, now: store.now)
        return Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(Typo.sans(Glass.quotaTitle, weight: .semibold)).foregroundStyle(theme.text)
                    Text(card.tier).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                    Text(card.capability).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(theme.textMuted).accessibilityHidden(true)
            }
            .padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline) {
                Text(card.headline)
                    .font(Typo.sans(Glass.quotaValue, weight: .medium))
                    .kerning(-1).monospacedDigit()
                    .foregroundStyle(theme.text)
                Spacer(minLength: 8)
                Text(card.availability).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
            }
            if let percent = card.meterPercent {
                ProgressBar(value: percent).padding(.top, 8)
            }
            Text(card.detail).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary).padding(.top, 10)
            Text(card.footnote).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 2)
        }
    }

    /// 公共重置信号：只展示 Valley 给的来源与事件；它不代表个人额度已恢复。
    @ViewBuilder
    private func resetSignalsSection(_ response: ResetSignalsResponse) -> some View {
        SectionTitle("公共重置信号")
        VStack(spacing: 10) {
            ForEach(response.signals) { signal in
                Card(padding: 18, radius: Glass.groupRadius) {
                    HStack {
                        Text(signal.products.joined(separator: " / "))
                            .font(Typo.sans(Glass.body, weight: .semibold)).foregroundStyle(theme.text)
                        Spacer(minLength: 8)
                        TintPill(text: signal.confidenceLabel,
                                 color: signal.canRefreshQuota ? theme.success : theme.warning)
                    }
                    Text(signal.effectiveText).font(Typo.sans(Glass.small)).foregroundStyle(theme.textSecondary)
                        .padding(.top, 6)
                    Link("查看来源", destination: signal.sourceUrl)
                        .font(Typo.sans(Glass.small)).padding(.top, 6)
                }
            }
            ForEach(response.sources) { source in
                Link(destination: source.url) {
                    Card(padding: 18, radius: Glass.groupRadius) {
                        HStack {
                            Text(source.name).font(Typo.sans(Glass.body, weight: .semibold)).foregroundStyle(theme.text)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.system(size: 13))
                                .foregroundStyle(theme.textMuted).accessibilityHidden(true)
                        }
                        Text(response.signals.isEmpty ? "公共重置与活动动态" : "信号来源")
                            .font(Typo.sans(Glass.small)).foregroundStyle(theme.textSecondary).padding(.top, 6)
                    }
                }
                .accessibilityIdentifier("reset.source.\(source.name)")
            }
        }
        Text(response.note.isEmpty ? "公共信号不代表你的个人额度已恢复。" : response.note)
            .font(Typo.sans(Glass.small)).foregroundStyle(theme.textMuted)
            .padding(.top, 8).padding(.bottom, 24)
            .accessibilityIdentifier("reset.note")
    }

    /// 额度池明细：每个窗口一行，写明来源与采样时间。
    private func poolDetail(_ pool: AccountQuotaPool) -> some View {
        let card = ToolQuotaCard(pool: pool, now: store.now)
        return NavigationStack {
            Form {
                Section("账号额度") {
                    LabeledContent("工具", value: card.name)
                    LabeledContent("套餐", value: card.tier)
                    LabeledContent("能力", value: card.capability)
                    LabeledContent("可用性", value: card.availability)
                    LabeledContent("额度池", value: pool.poolId)
                }
                Section("额度窗口") {
                    if pool.windows.isEmpty {
                        Text("还没有采到这个池的额度样本。")
                    }
                    ForEach(pool.windows) { window in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(window.scopeLabel, value: window.displayLabel)
                            Text("采样 \(Format.time(window.observedAt)) · 来源 \(window.source) · 置信度 \(window.confidence)")
                                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                            if let reset = window.resetText(now: store.now) {
                                Text(reset).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                            }
                        }
                        .accessibilityIdentifier("quota.\(window.poolId).\(window.scope)")
                    }
                }
                Section {
                    Text("额度耗尽时 Plan 进入等待，不会转为付费执行。是否自然恢复后自动续跑，在每个 Plan 的详情里单独设置。")
                        .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                }
            }
            .navigationTitle(card.name)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { selectedPool = nil } } }
        }
    }

    private func approvePairing() {
        pairingMessage = "正在核对电脑信息…"
        _Concurrency.Task {
            do {
                pendingInspection = try await remote.inspect(code: pairingCode)
                pairingMessage = nil
            } catch {
                pairingMessage = pairingErrorText(error)
            }
        }
    }

    private func confirmPairing() {
        pendingInspection = nil
        pairingMessage = "正在批准…"
        _Concurrency.Task {
            do {
                try await remote.approve(code: pairingCode)
                pairingCode = ""
                pairingMessage = "电脑已绑定，可以远程派发任务。"
            } catch { pairingMessage = pairingErrorText(error) }
        }
    }
}
