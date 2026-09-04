import Charts
import SwiftUI

struct ChartPoint: Identifiable {
    let id: String
    let date: String
    let human: Int, ai: Int, waiting: Int, deepWork: Int, planned: Int, actual: Int

    init(_ d: DailyStats) {
        id = d.date
        date = String(d.date.dropFirst(5))
        human = Int((Double(d.humanSeconds) / 60).rounded())
        ai = Int((Double(d.aiActiveSeconds) / 60).rounded())
        waiting = Int((Double(d.waitingSeconds) / 60).rounded())
        deepWork = Int((Double(d.deepWorkSeconds) / 60).rounded())
        planned = d.plannedMinutes
        actual = d.actualHumanMinutes
    }
}

/// Shared axis styling: dashed grid in `border`, 10pt `textMuted` labels.
struct ChartAxes: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(theme.textMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(theme.border)
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(theme.textMuted)
                }
            }
            .chartLegend(position: .bottom, alignment: .center, spacing: 8)
    }
}

struct DistributionDonut: View {
    @Environment(\.theme) private var theme
    let stats: DailyStats

    private struct Slice: Identifiable { let id: String; let value: Int }

    var body: some View {
        let slices = [
            Slice(id: "人工专注", value: stats.humanSeconds),
            Slice(id: "AI 活跃", value: stats.aiActiveSeconds),
            Slice(id: "等待", value: stats.waitingSeconds),
            Slice(id: "深度工作", value: stats.deepWorkSeconds),
            Slice(id: "返工", value: stats.reworkSeconds),
        ].filter { $0.value > 0 }
        let palette = [theme.accent, theme.ai, theme.warning, theme.success, theme.danger]
        let colors = slices.indices.map { palette[$0 % palette.count] }

        HStack(spacing: 16) {
            Chart(slices) { slice in
                SectorMark(angle: .value("时长", slice.value), innerRadius: .ratio(0.57), angularInset: 1)
                    .foregroundStyle(by: .value("类别", slice.id))
            }
            .chartForegroundStyleScale(domain: slices.map(\.id), range: colors)
            .chartLegend(.hidden)
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { i, slice in
                    HStack(spacing: 6) {
                        Circle().fill(colors[i]).frame(width: 8, height: 8)
                        Text(slice.id).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 4)
                        Text(Format.duration(slice.value)).font(Typo.mono(Typo.xs)).foregroundStyle(theme.textMuted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .frame(height: 160)
    }
}

struct HumanVsAIChart: View {
    @Environment(\.theme) private var theme
    let data: [ChartPoint]

    var body: some View {
        Chart {
            ForEach(data) { d in
                BarMark(x: .value("日期", d.date), y: .value("分钟", d.human))
                    .foregroundStyle(by: .value("系列", "人工(分)"))
                    .position(by: .value("系列", "人工(分)"))
                    .cornerRadius(4)
                BarMark(x: .value("日期", d.date), y: .value("分钟", d.ai))
                    .foregroundStyle(by: .value("系列", "AI(分)"))
                    .position(by: .value("系列", "AI(分)"))
                    .cornerRadius(4)
            }
        }
        .chartForegroundStyleScale(["人工(分)": theme.accent, "AI(分)": theme.ai])
        .modifier(ChartAxes())
        .frame(height: 180)
    }
}

struct PlannedVsActualChart: View {
    @Environment(\.theme) private var theme
    let data: [ChartPoint]

    var body: some View {
        Chart {
            ForEach(data) { d in
                LineMark(x: .value("日期", d.date), y: .value("分钟", d.planned), series: .value("系列", "计划(分)"))
                    .foregroundStyle(by: .value("系列", "计划(分)"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                LineMark(x: .value("日期", d.date), y: .value("分钟", d.actual), series: .value("系列", "实际(分)"))
                    .foregroundStyle(by: .value("系列", "实际(分)"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartForegroundStyleScale(["计划(分)": theme.warning, "实际(分)": theme.accent])
        .modifier(ChartAxes())
        .frame(height: 180)
    }
}

struct WaitingTrendChart: View {
    @Environment(\.theme) private var theme
    let data: [ChartPoint]

    var body: some View {
        Chart {
            ForEach(data) { d in
                AreaMark(x: .value("日期", d.date), y: .value("等待(分)", d.waiting))
                    .foregroundStyle(theme.warning.opacity(0.3))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", d.date), y: .value("等待(分)", d.waiting))
                    .foregroundStyle(theme.warning)
                    .interpolationMethod(.catmullRom)
            }
        }
        .modifier(ChartAxes())
        .chartLegend(.hidden)
        .frame(height: 160)
    }
}

struct DeepWorkTrendChart: View {
    @Environment(\.theme) private var theme
    let data: [ChartPoint]

    var body: some View {
        Chart {
            ForEach(data) { d in
                LineMark(x: .value("日期", d.date), y: .value("深度工作(分)", d.deepWork))
                    .foregroundStyle(theme.success)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("日期", d.date), y: .value("深度工作(分)", d.deepWork))
                    .foregroundStyle(theme.success)
                    .symbolSize(20)
            }
        }
        .modifier(ChartAxes())
        .chartLegend(.hidden)
        .frame(height: 160)
    }
}
