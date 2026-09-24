import SwiftUI

/// Plans display server facts. Review captures the version the person actually saw.
struct PlanDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStore.self) private var store
    let planId: String
    @State private var review: PlanReviewDraft?
    @State private var showDispatch = false

    var body: some View {
        SubPageScaffold(title: "Plan 详情") {
            if let plan = store.plan(planId) { content(plan) }
            else { MissingPlaceholder(text: "Plan 不存在") }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await store.monitorPlan(planId) }
        }
        .sheet(item: $review) { draft in PlanAcceptanceSheet(draft: draft) }
        .sheet(isPresented: $showDispatch) {
            if let plan = store.plan(planId) { PlanDispatchSheet(planID: plan.id) }
        }
    }

    private func applyMode(_ mode: PlanExecutionMode, to plan: PlanItem) {
        _Concurrency.Task { await store.setPlanExecutionMode(plan.id, mode: mode) }
    }

    private func applyAutoResume(_ allow: Bool, to plan: PlanItem) {
        _Concurrency.Task { await store.setPlanAutoResume(plan.id, allow: allow) }
    }

    @ViewBuilder
    private func content(_ plan: PlanItem) -> some View {
        let deps = plan.dependsOn.compactMap { store.plan($0) }
        let busy = store.planBusy.contains(plan.id)
        let executorBlocker = store.planDispatchUnavailableReason(plan.id)
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.title).font(Typo.sans(Typo.lg, weight: .medium)).foregroundStyle(theme.text)
            Text(plan.status.label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("plan.status")
            Text("版本 \(plan.revision)").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
        }.padding(.bottom, 20)

        TwoColumnGrid {
            StatCard(label: "人工预计", value: "\(plan.estimatedHumanMinutes) 分钟")
            StatCard(label: "AI 预计", value: "\(plan.estimatedAiMinutes) 分钟", valueColor: theme.ai)
        }.padding(.bottom, 20)

        if !plan.criteria.isEmpty {
            SectionTitle("验收项")
            // Criteria have no server IDs: this read-only text has no row state.
            Text(plan.criteria.map { "○ " + $0 }.joined(separator: "\n"))
                .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).lineSpacing(6)
                .padding(.bottom, 20)
        }
        if !deps.isEmpty {
            SectionTitle("依赖 Plan")
            VStack(spacing: 8) {
                ForEach(deps) { dep in
                    HStack {
                        Text(dep.title).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                        Spacer()
                        Text(dep.status.label).font(Typo.sans(Typo.xs))
                            .foregroundStyle(dep.status == .accepted ? theme.accent : theme.warning)
                    }.padding(.vertical, 6)
                }
            }.padding(.bottom, 20)
        }
        SectionTitle("分派策略")
        if let mode = plan.executionPolicy.executionMode {
            GlassSegments(options: PlanExecutionMode.allCases.map { ($0, $0.label) },
                          selection: Binding(
                            get: { mode },
                            set: { next in applyMode(next, to: plan) }))
                .disabled(!canEditExecutionPolicy(plan) || store.workspaceClient == nil || busy)
                .accessibilityIdentifier("plan.policy")
        } else {
            Text("服务端策略「\(plan.executionPolicy.mode)」暂不支持在此修改。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
        }
        Toggle(isOn: Binding(
            get: { plan.executionPolicy.allowAutoResume },
            set: { allow in applyAutoResume(allow, to: plan) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("自然恢复后自动续跑").font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                Text("原会话 · 已有订阅 · 不额外付费")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
        }
        .tint(theme.accent)
        .disabled(!canEditAutoResume(plan) || store.workspaceClient == nil || busy)
        .padding(.top, 12)
        .accessibilityIdentifier("plan.autoresume")
        if !plan.executionPolicy.allowAutoResume {
            Text("额度恢复后只补额度、不自动运行，需要在此手动继续。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 6)
        }

        Text(policyNote(plan))
            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            .padding(.top, 6).padding(.bottom, 20)
            .accessibilityIdentifier("plan.policy.note")

        if let job = store.planJobs[plan.id] {
            Text("执行记录：\(job.displayLabel(now: store.now))").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("plan.job.status")
            if let summary = job.resultSummary, !summary.isEmpty {
                Text(summary).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            }
            // 电脑回传的最后 8 KB 输出；完整日志留在电脑上。
            if let tail = job.outputTail, !tail.isEmpty {
                DisclosureGroup("查看输出（最后 8 KB）") {
                    ScrollView([.horizontal, .vertical]) {
                        Text(tail).font(Typo.mono(Typo.xs)).foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled).padding(8)
                            .accessibilityIdentifier("plan.job.output.text")
                    }
                    .frame(maxHeight: 240)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .font(Typo.sans(Typo.xs))
                .accessibilityIdentifier("plan.job.output")
            }
            Spacer().frame(height: 12)
        }
        VStack(spacing: 8) {
            if let executorBlocker {
                Text(executorBlocker).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("plan.executor.unavailable")
            }
            if busy { ProgressView("正在提交…").accessibilityIdentifier("plan.loading") }
            if let error = store.planErrors[plan.id] ?? store.planErrors[plan.taskId] {
                Text(error).font(Typo.sans(Typo.xs)).foregroundStyle(theme.danger).accessibilityIdentifier("plan.error")
            }
            if plan.status == .awaitingReview {
                AppButton("确认验收通过", variant: .secondary, fullWidth: true, disabled: busy || store.workspaceClient == nil) {
                    review = PlanReviewDraft(plan: plan, job: store.planJobs[plan.id])
                }.accessibilityIdentifier("plan.accept")
            }
            AppButton("派发执行", variant: .accent, fullWidth: true,
                      disabled: busy || executorBlocker != nil || store.workspaceClient == nil || plan.id.hasPrefix("draft-") || !canDispatchPlan(plan, allPlans: store.plans)) {
                showDispatch = true
            }.accessibilityIdentifier("plan.dispatch")
            if plan.status == .failed {
                AppButton("重试此 Plan", variant: .secondary, fullWidth: true, disabled: busy) {
                    Task { await store.retryPlan(plan.id, expectedRevision: plan.revision) }
                }.accessibilityIdentifier("plan.retry")
            }
            if ![.accepted, .cancelled, .unknown].contains(plan.status), !plan.id.hasPrefix("draft-") {
                AppButton("取消 Plan", variant: .ghost, fullWidth: true, disabled: busy || store.workspaceClient == nil) {
                    Task { await store.cancelPlan(plan.id, expectedRevision: plan.revision) }
                }.accessibilityIdentifier("plan.cancel")
            }
            AppButton("刷新状态", variant: .ghost, fullWidth: true) {
                Task { await store.refreshPlanJob(plan.id) }
            }.accessibilityIdentifier("plan.refresh")
            if store.workspaceClient == nil || plan.id.hasPrefix("draft-") {
                Text("本地草稿需要联网同步；离线不能派发或验收。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
            if !canDispatchPlan(plan, allPlans: store.plans), !plan.dependsOn.isEmpty {
                Text("需先验收全部依赖 Plan。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
        }
    }
}

/// 分派策略下方的说明：解释为什么可改或为什么被锁定，而不是只把控件灰掉。
private func policyNote(_ plan: PlanItem) -> String {
    if plan.id.hasPrefix("draft-") { return "本地草稿同步后才能设置分派策略。" }
    switch plan.status {
    case .draft, .ready: return "启动前仍会校验额度与依赖；额度不足时等待，不转付费执行。"
    case .accepted, .cancelled, .failed, .unknown: return "Plan 已结束，分派策略不再修改。"
    default: return "已有执行上下文，保持原工具与会话；运行中锁定分派策略。"
    }
}

private struct PlanAcceptanceSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let draft: PlanReviewDraft
    @State private var checked: Set<UUID> = []
    @State private var evidenceChecked = false

    private var stale: Bool { store.plan(draft.plan.id)?.revision != draft.plan.revision }
    private var valid: Bool {
        !stale && checked.count == draft.criteria.count && evidenceChecked && draft.job?.status == .awaitingReview
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("版本 \(draft.plan.revision) · 验收项") {
                    ForEach(draft.criteria) { criterion in
                        Button {
                            if !checked.insert(criterion.id).inserted { checked.remove(criterion.id) }
                        } label: {
                            Label(criterion.title, systemImage: checked.contains(criterion.id) ? "checkmark.circle.fill" : "circle")
                        }.accessibilityIdentifier("plan.criterion.\(criterion.index)")
                            .accessibilityValue(checked.contains(criterion.id) ? "已确认" : "未确认")
                    }
                }
                Section("执行证据") {
                    if let job = draft.job, job.status == .awaitingReview {
                        Text(job.resultSummary ?? "请核对执行结果后选择此记录。")
                        Button { evidenceChecked.toggle() } label: {
                            Label("确认执行记录 \(job.id)", systemImage: evidenceChecked ? "checkmark.circle.fill" : "circle")
                        }.accessibilityIdentifier("plan.evidence.\(job.id)")
                            .accessibilityValue(evidenceChecked ? "已确认" : "未确认")
                    } else {
                        Text("执行证据不可用。请在派发此 Plan 的设备上审核，或联系管理员获取执行记录；服务暂不支持列出历史执行证据。")
                            .accessibilityIdentifier("plan.evidence.unavailable")
                    }
                }
                if stale { Text("版本已变化，请关闭并重新审核当前版本。").accessibilityIdentifier("plan.review.stale") }
                if let error = store.planErrors[draft.plan.id] { Text(error).accessibilityIdentifier("plan.review.error") }
                Button("确认验收通过") {
                    Task {
                        let results = draft.criteria.map { CriterionResultBody(index: $0.index, accepted: checked.contains($0.id)) }
                        if await store.acceptPlan(draft.plan.id, expectedRevision: draft.plan.revision,
                            evidenceIDs: draft.job.map { [$0.id] } ?? [], criteria: results) { dismiss() }
                    }
                }.disabled(!valid || store.planBusy.contains(draft.plan.id)).accessibilityIdentifier("plan.accept.confirm")
            }
            .navigationTitle("确认验收")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct PlanDispatchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planID: String
    @State private var runnerID = ""
    @State private var workspaceID = ""
    @State private var toolID = ""
    @State private var loading = true
    @State private var scheduled = false
    @State private var runAt = Date().addingTimeInterval(3600)
    private var runners: [RunnerInventory] { store.planRunners.online }
    private var runner: RunnerInventory? { runners.first { $0.id == runnerID } }
    private var workspaces: [RunnerWorkspace] { runner?.workspaces.filter(\.enabled) ?? [] }
    private var tools: [RunnerTool] { runner?.tools.filter { $0.status == "available" } ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                if loading { ProgressView("正在读取执行环境…") }
                Picker("执行电脑", selection: $runnerID) {
                    ForEach(runners) { Text($0.runner.name).tag($0.id) }
                }
                Picker("本地工作区", selection: $workspaceID) {
                    ForEach(workspaces) { Text($0.name).tag($0.id) }
                }
                Picker("执行工具", selection: $toolID) {
                    ForEach(tools) { Text($0.provider.label + " · " + $0.version).tag($0.id) }
                }
                if !loading && runners.isEmpty { Text("没有可用电脑，请先连接执行器后重试。") }
                Section("执行时间") {
                    Toggle("指定时间执行", isOn: $scheduled).accessibilityIdentifier("plan.dispatch.schedule")
                    if scheduled {
                        DatePicker("开始于", selection: $runAt,
                                   in: Date().addingTimeInterval(120)...Date().addingTimeInterval(30 * 86400),
                                   displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("plan.dispatch.runAt")
                        Text("到点后由电脑领取执行；那时额度不足会先等待，不会转为付费。")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(.secondary)
                    }
                }
                if let error = store.planErrors[planID] { Text(error) }
                Button("确认派发") {
                    Task {
                        if await store.dispatchPlan(planID, runnerID: runnerID, workspaceID: workspaceID, toolID: toolID,
                                                    notBefore: scheduled ? runAt : nil) { dismiss() }
                    }
                }.disabled(loading || runnerID.isEmpty || workspaceID.isEmpty || toolID.isEmpty || store.planBusy.contains(planID))
                    .accessibilityIdentifier("plan.dispatch.confirm")
            }
            .navigationTitle("派发执行")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task {
                await store.loadPlanRunners(for: planID)
                runnerID = runners.first?.id ?? ""
                selectDefaults()
                loading = false
            }
            .onChange(of: runnerID) { selectDefaults() }
        }
    }

    private func selectDefaults() {
        workspaceID = workspaces.first?.id ?? ""
        toolID = tools.first?.id ?? ""
    }
}
