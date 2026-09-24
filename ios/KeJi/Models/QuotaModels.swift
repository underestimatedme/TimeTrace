import Foundation

/// One account quota window as returned by Valley's GET /quota. Carries only
/// opaque pool ids and de-identified readings — never credentials. A nil
/// usedPercent means an unknown reading (must not be treated as full).
struct QuotaWindow: Codable, Equatable, Identifiable {
    var poolId: String
    var scope: String
    var kind: String
    var usedPercent: Double?
    var resetAt: Date?
    var observedAt: Date
    var expiresAt: Date
    var source: String
    var confidence: String
    /// 服务端的完整窗口身份：同一 scope 下不同 limit / 时长的窗口不能撞 id。
    var limitId: String = ""
    var windowMins: Int = 0

    var id: String { "\(poolId)|\(limitId)|\(scope)|\(kind)|\(windowMins)" }
}

extension QuotaWindow {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poolId = try c.decode(String.self, forKey: .poolId)
        scope = try c.decode(String.self, forKey: .scope)
        kind = try c.decode(String.self, forKey: .kind)
        usedPercent = try c.decodeIfPresent(Double.self, forKey: .usedPercent)
        resetAt = try c.decodeIfPresent(Date.self, forKey: .resetAt)
        observedAt = try c.decode(Date.self, forKey: .observedAt)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        source = try c.decode(String.self, forKey: .source)
        confidence = try c.decode(String.self, forKey: .confidence)
        limitId = try c.decodeIfPresent(String.self, forKey: .limitId) ?? ""
        windowMins = try c.decodeIfPresent(Int.self, forKey: .windowMins) ?? 0
    }
}

struct AccountQuotaPool: Codable, Equatable, Identifiable {
    var poolId: String
    /// Tool identity (= sample kind) so clients can render per-tool cards; "" when unknown.
    var provider: String = ""
    var availability: String   // available / blocked / unknown
    var windows: [QuotaWindow]
    /// 该池所属工具登录账号的套餐等级；空表示未知。
    var planTier: String = ""

    var id: String { poolId }

    init(poolId: String, provider: String = "", availability: String, windows: [QuotaWindow], planTier: String = "") {
        self.poolId = poolId; self.provider = provider; self.availability = availability; self.windows = windows
        self.planTier = planTier
    }

    /// `provider` / `plan_tier` 是后加的字段：旧快照里没有时按未知处理，不能整条解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poolId = try c.decode(String.self, forKey: .poolId)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        availability = try c.decodeIfPresent(String.self, forKey: .availability) ?? "unknown"
        windows = try c.decodeIfPresent([QuotaWindow].self, forKey: .windows) ?? []
        planTier = try c.decodeIfPresent(String.self, forKey: .planTier) ?? ""
    }
}

struct AccountQuota: Codable, Equatable {
    var pools: [AccountQuotaPool]
    var observedAt: Date
}

/// 公共重置信号（Valley `GET /reset-signals`）。它**永远不能**替代个人额度读数：
/// 已确认的公共事件最多触发一次个人额度的重新核验，不会直接解除任何阻塞。
struct ResetSignal: Codable, Equatable, Identifiable {
    var id: String
    var sourceUrl: URL
    var publishedAt: Date
    var effectiveAt: Date?
    var products: [String]
    var plans: [String]
    var confidence: String      // confirmed / possible
    var fetchedAt: Date
    var expiresAt: Date
    var revision: Int64

    /// 与 Valley `CanRefreshQuota` 一致：只有 confirmed 才能安排一次核验。
    var canRefreshQuota: Bool { confidence == "confirmed" }
    var confidenceLabel: String { confidence == "confirmed" ? "已确认" : "可能" }
    /// 缺生效时间就说未知，不从「今天」推算。
    var effectiveText: String {
        effectiveAt.map { "预计 \(Format.dateShort($0)) \(Format.time($0)) 生效" } ?? "生效时间未知"
    }
}

struct ResetSource: Codable, Equatable, Identifiable {
    var name: String
    var url: URL
    var id: String { url.absoluteString }
}

struct ResetSignalsResponse: Codable, Equatable {
    var integrationStatus: String   // link_only / cached
    var sources: [ResetSource]
    var signals: [ResetSignal]
    var cacheAgeSeconds: Int
    var fetchedAt: Date?
    var note: String
}
