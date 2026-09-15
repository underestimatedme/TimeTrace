import Foundation

/// A private daily report from Valley's GET/POST /reports. Human input, AI
/// active time and waiting time are separate; a total score is present only when
/// coverage is high enough. Estimated API-equivalent value and actual new spend
/// are distinct fields.
struct DailyReport: Codable, Equatable {
    var localDate: String
    var revision: Int
    var status: String            // draft / empty
    var humanSeconds: Int
    var aiSeconds: Int
    var waitingSeconds: Int
    var coverage: Double
    var totalScore: Double?
    var evidenceIds: [String]
    var baselineVersion: String
    var estimatedValueMinor: Int
    var actualSpendMinor: Int
    var generatedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        localDate = try c.decodeIfPresent(String.self, forKey: .localDate) ?? ""
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "empty"
        humanSeconds = try c.decodeIfPresent(Int.self, forKey: .humanSeconds) ?? 0
        aiSeconds = try c.decodeIfPresent(Int.self, forKey: .aiSeconds) ?? 0
        waitingSeconds = try c.decodeIfPresent(Int.self, forKey: .waitingSeconds) ?? 0
        coverage = try c.decodeIfPresent(Double.self, forKey: .coverage) ?? 0
        totalScore = try c.decodeIfPresent(Double.self, forKey: .totalScore)
        evidenceIds = try c.decodeIfPresent([String].self, forKey: .evidenceIds) ?? []
        baselineVersion = try c.decodeIfPresent(String.self, forKey: .baselineVersion) ?? ""
        estimatedValueMinor = try c.decodeIfPresent(Int.self, forKey: .estimatedValueMinor) ?? 0
        actualSpendMinor = try c.decodeIfPresent(Int.self, forKey: .actualSpendMinor) ?? 0
        generatedAt = try? c.decodeIfPresent(Date.self, forKey: .generatedAt)
    }

    var hasTotal: Bool { totalScore != nil }
    var isEmpty: Bool { status == "empty" || revision == 0 }
}
