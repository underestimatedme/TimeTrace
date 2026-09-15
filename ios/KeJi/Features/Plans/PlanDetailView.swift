import SwiftUI

/// Plan detail: acceptance criteria, dependencies and their status, and a
/// dispatch action that is enabled only once every dependency is accepted (the
/// server re-validates on dispatch). Acceptance is optimistic offline; only a
/// server `accepted` advances delivery goals (I3).
struct PlanDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    let planId: String

    var body: some View {
        SubPageScaffold(title: "Plan 详情") {
            if let plan = store.plan(planId) {
                content(plan)
            } else {
                MissingPlaceholder(text: "Plan 不存在")
            }
        }
    }

    @ViewBuilder
    private func content(_ plan: PlanItem) -> some View {
        let all = store.plans
        let dispatchable = canDispatchPlan(plan, allPlans: all)
        let deps = plan.dependsOn.compactMap { store.plan($0) }
        let pendingDeps = deps.filter { $0.status != .accepted }

        VStack(alignment: .leading, spacing: 0) {
            Text(plan.title).font(Typo.sans(Typo.lg, weight: .medium)).foregroundStyle(theme.text).padding(.bottom, 8)
            Text(plan.status.label)
                .font(Typo.sans(Typo.xs))
                .foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("plan.status")
        }
        .padding(.bottom, 20)

        TwoColumnGrid {
            StatCard(label: "人工预计", value: "\(plan.estimatedHumanMinutes) 分钟")
            StatCard(label: "AI 预计", value: "\(plan.estimatedAiMinutes) 分钟", valueColor: theme.ai)
        }
        .padding(.bottom, 20)

        if !plan.criteria.isEmpty {
            SectionTitle("验收项")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.criteria.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle").font(.system(size: 13)).foregroundStyle(theme.textMuted)
                        Text(item).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .padding(.bottom, 20)
        }

        if !deps.isEmpty {
            SectionTitle("依赖 Plan")
            VStack(spacing: 8) {
                ForEach(deps) { dep in
                    HStack {
                        Text(dep.title).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                        Spacer()
                        Text(dep.status.label)
                            .font(Typo.sans(Typo.xs))
                            .foregroundStyle(dep.status == .accepted ? theme.accent : theme.warning)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.bottom, 20)
        }

        VStack(spacing: 8) {
            if plan.status != .accepted {
                AppButton("标记验收", variant: .secondary, fullWidth: true) { store.markPlanAccepted(plan.id) }
                    .accessibilityIdentifier("plan.accept")
            }
            AppButton("派发执行", variant: .accent, fullWidth: true) { /* dispatch: I3 online */ }
                .disabled(!dispatchable)
                .accessibilityIdentifier("plan.dispatch")
            if !pendingDeps.isEmpty {
                Text("需先验收依赖：\(pendingDeps.map { $0.title }.joined(separator: "、"))")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
        }
    }
}
