import Foundation

/// A private daily report from Valley's GET/POST /reports. Human input, AI
/// active time and waiting time are separate; a total score is present only when
/// coverage is high enough. Estimated API-equivalent value and actual new spend
/// are distinct fields.
struct DailyReport: Codable, Equatable {
    var localDate: String
    var revision: Int
    var status: String            // draft / empty
    var humanSeconds: Int?
    var aiSeconds: Int?
    var waitingSeconds: Int?
    var coverage: Double
    var totalScore: Double?
    var evidenceIds: [String]
    var baselineVersion: String
    var estimatedValueMinor: Int?
    var actualSpendMinor: Int?
    var generatedAt: Date?
    var breakdown: ReportPhaseFacts?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        localDate = try c.decodeIfPresent(String.self, forKey: .localDate) ?? ""
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "empty"
        humanSeconds = try c.decodeIfPresent(Int.self, forKey: .humanSeconds)
        aiSeconds = try c.decodeIfPresent(Int.self, forKey: .aiSeconds)
        waitingSeconds = try c.decodeIfPresent(Int.self, forKey: .waitingSeconds)
        coverage = try c.decodeIfPresent(Double.self, forKey: .coverage) ?? 0
        totalScore = try c.decodeIfPresent(Double.self, forKey: .totalScore)
        evidenceIds = try c.decodeIfPresent([String].self, forKey: .evidenceIds) ?? []
        baselineVersion = try c.decodeIfPresent(String.self, forKey: .baselineVersion) ?? ""
        estimatedValueMinor = try c.decodeIfPresent(Int.self, forKey: .estimatedValueMinor)
        actualSpendMinor = try c.decodeIfPresent(Int.self, forKey: .actualSpendMinor)
        generatedAt = try? c.decodeIfPresent(Date.self, forKey: .generatedAt)
        breakdown = try c.decodeIfPresent(ReportPhaseFacts.self, forKey: .breakdown)
    }

    var hasTotal: Bool { coverage >= 0.80 && coverage <= 1 && totalScore?.isFinite == true }
    var isEmpty: Bool { status == "empty" || revision == 0 }
}

struct ReportPhaseFact: Codable, Equatable, Identifiable {
    var id: String
    var taskId: String
    var track: TimelineTrack
    var state: String
    var start: Date
    var end: Date
}

struct ReportPhaseFacts: Codable, Equatable {
    var zone: String
    var facts: [ReportPhaseFact]
    var evidenceCoverage: Double
}

enum ReportMeasurement: Equatable {
    case empty, unknown, seconds(Int)
    var text: String {
        switch self { case .empty: return "无记录"; case .unknown: return "未测量"; case .seconds(let seconds): return Format.duration(seconds) }
    }
}

/// The screen and export share this projection, including project filtering.
struct ReportPresentation {
    /// 设计稿：样本不足不显示假总分。
    static let insufficientSampleText = "样本不足，暂不计算"

    var human: ReportMeasurement
    var ai: ReportMeasurement
    var waiting: ReportMeasurement
    var evidenceCoverage: Double

    init(facts: [ReportPhaseFact], taskIds: Set<String>? = nil) {
        var seen = Set<String>()
        let selected = facts.filter { (taskIds == nil || taskIds!.contains($0.taskId)) && seen.insert($0.id).inserted }
        func measurement(_ track: TimelineTrack) -> ReportMeasurement {
            let rows = selected.filter { $0.track == track }
            guard !rows.isEmpty else { return .empty }
            guard rows.allSatisfy({ $0.state == "known" }) else { return .unknown }
            let intervals = rows.map { TrackInterval(id: $0.id, start: $0.start, end: $0.end, track: $0.track) }
            return .seconds(Int(track == .human ? unionSeconds(intervals, track: track) : activeSeconds(intervals, track: track)))
        }
        human = measurement(.human); ai = measurement(.ai); waiting = measurement(.waiting)
        evidenceCoverage = selected.isEmpty ? 0 : Double(selected.filter { $0.state == "known" }.count) / Double(selected.count)
    }

    init(sessions: [TimeSession], day: String, timeZone: TimeZone) {
        guard let bounds = reportDayInterval(day, timeZone: timeZone) else { self.init(facts: []); return }
        let facts: [ReportPhaseFact] = sessions.compactMap { s in
            let track: TimelineTrack
            if Stats.humanTypes.contains(s.type) { track = .human }
            else if Stats.aiTypes.contains(s.type) { track = .ai }
            else if Stats.waitingTypes.contains(s.type) { track = .waiting }
            else { return nil }
            let end = s.endedAt ?? bounds.end
            guard s.startedAt < bounds.end, end > bounds.start else { return nil }
            return ReportPhaseFact(id: s.id, taskId: s.taskId, track: track,
                                   state: s.endedAt != nil && end >= s.startedAt ? "known" : "unknown",
                                   start: max(s.startedAt, bounds.start), end: min(end, bounds.end))
        }
        self.init(facts: facts)
    }
}
