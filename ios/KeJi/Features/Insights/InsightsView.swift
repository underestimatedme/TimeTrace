import SwiftUI

/// Insights.tsx: 今日/本周/趋势 tabs, 8 metric cards, charts, AI 洞察建议, 效率实验.
struct InsightsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    enum Tab: String, CaseIterable {
        case today, week, trend
        var label: String { switch self { case .today: return "今日"; case .week: return "本周"; case .trend: return "趋势" } }
    }
    @State private var tab: Tab = .today

    var body: some View {
        let daily = store.dailyStats
        let todayStats = daily.last
        let weekStats = Stats.aggregateDailyStats(daily, days: 7)
        let stats = tab == .today ? todayStats : weekStats
        let chartData = daily.map(ChartPoint.init)
        let insights = Stats.generateInsights(sessions: store.timeSessions, tasks: store.tasks, dailyStats: daily,
                                              executions: store.aiExecutions)

        TabPage {
            PageTitle(title: "洞察").padding(.bottom, 16)
            HStack(spacing: 8) {
                ForEach(Tab.allCases, id: \.self) { t in
                    PillChip(label: t.label, selected: tab == t, horizontalPadding: 16) { tab = t }
                }
            }
            .padding(.bottom, 24)

            if tab != .trend, let stats {
                metrics(stats).padding(.bottom, 24)
                SectionTitle("时间分类分布")
                Card { DistributionDonut(stats: stats) }.padding(.bottom, 24)
            }

            if tab == .week || tab == .trend {
                SectionTitle("人工 vs AI 时间对比")
                Card { HumanVsAIChart(data: chartData) }.padding(.bottom, 24)
                SectionTitle("计划 vs 实际时间")
                Card { PlannedVsActualChart(data: chartData) }.padding(.bottom, 24)
                SectionTitle("等待时间趋势")
                Card { WaitingTrendChart(data: chartData) }.padding(.bottom, 24)
                SectionTitle("深度工作趋势")
                Card { DeepWorkTrendChart(data: chartData) }.padding(.bottom, 24)
            }

            SectionTitle("AI 洞察建议")
            VStack(spacing: 12) {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    Card(borderColor: theme.accent.opacity(0.1)) {
                        Text(insight).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).lineSpacing(4)
                    }
                }
                if insights.isEmpty {
                    Card { Text("数据积累中，稍后会给出建议。").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textMuted) }
                }
            }
            .padding(.bottom, 24)

            SectionTitle("效率实验")
            VStack(spacing: 12) { ForEach(store.experiments) { experimentCard($0) } }
        }
    }

    private func metrics(_ s: DailyStats) -> some View {
        let leverage = Stats.timeLeverage(humanSeconds: s.humanSeconds, aiSeconds: s.aiActiveSeconds)
        let accuracy = Stats.planAccuracy(plannedMinutes: s.plannedMinutes, actualMinutes: s.actualHumanMinutes)
        return TwoColumnGrid {
            MetricCard(label: "人工投入", value: Format.duration(s.humanSeconds))
            MetricCard(label: "AI 活跃", value: Format.duration(s.aiActiveSeconds))
            MetricCard(label: "等待时间", value: Format.duration(s.waitingSeconds))
            MetricCard(label: "深度工作", value: Format.duration(s.deepWorkSeconds))
            MetricCard(label: "中断次数", value: "\(s.interruptionCount)")
            MetricCard(label: "完成任务", value: "\(s.completedTasks)")
            MetricCard(label: "时间杠杆", value: Format.leverage(leverage))
            MetricCard(label: "计划准确率", value: Format.percent(accuracy))
        }
    }

    private func experimentCard(_ exp: EfficiencyExperiment) -> some View {
        let color: Color = exp.status == .active ? theme.success : exp.status == .planned ? theme.accent : theme.textMuted
        return Card {
            HStack(alignment: .top, spacing: 8) {
                Text(exp.title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                Spacer(minLength: 0)
                TintPill(text: exp.status.label, color: color)
            }
            .padding(.bottom, 8)
            Text(exp.description).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 8)
            HStack(spacing: 16) {
                Text("实验前: \(exp.beforeMetric)").foregroundStyle(theme.textSecondary)
                if let after = exp.afterMetric { Text("实验后: \(after)").foregroundStyle(theme.success) }
            }
            .font(Typo.sans(Typo.xs))
        }
    }
}
