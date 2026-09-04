import Foundation

struct UserInfo: Codable, Equatable {
    var id: String
    var nickname: String?
    var isGuest: Bool
    var accountLabel: String?

    init(id: String, nickname: String? = nil, isGuest: Bool, accountLabel: String? = nil) {
        self.id = id; self.nickname = nickname; self.isGuest = isGuest; self.accountLabel = accountLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        isGuest = try c.decodeIfPresent(Bool.self, forKey: .isGuest) ?? true
        accountLabel = try c.decodeIfPresent(String.self, forKey: .accountLabel)
    }
}

struct SessionTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    /// Seconds (guest sessions: 900).
    var expiresIn: Int
    /// Client-side stamp used for proactive refresh; not sent by the server.
    var obtainedAt: Date?

    init(accessToken: String, refreshToken: String, expiresIn: Int, obtainedAt: Date? = Date()) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresIn = expiresIn; self.obtainedAt = obtainedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        expiresIn = try c.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 900
        obtainedAt = (try? c.decodeIfPresent(Date.self, forKey: .obtainedAt)) ?? Date()
    }

    var expiresAt: Date { (obtainedAt ?? Date()).addingTimeInterval(TimeInterval(expiresIn)) }

    /// True when the access token expires within `margin` seconds.
    func isExpiringSoon(margin: TimeInterval = 60, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
    }
}

struct Bootstrap: Codable, Equatable {
    var user: UserInfo?
    var state: StateSnapshot
    var serverTime: Date?

    init(user: UserInfo?, state: StateSnapshot, serverTime: Date?) {
        self.user = user; self.state = state; self.serverTime = serverTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try c.decodeIfPresent(UserInfo.self, forKey: .user)
        state = try c.decodeIfPresent(StateSnapshot.self, forKey: .state) ?? StateSnapshot()
        serverTime = try? c.decodeIfPresent(Date.self, forKey: .serverTime)
    }
}

struct SyncUpserts: Codable, Equatable {
    var projects: [Project] = []
    var goals: [Goal] = []
    var tasks: [TaskItem] = []
    var timeSessions: [TimeSession] = []
    var aiExecutions: [AIExecution] = []
    var experiments: [EfficiencyExperiment] = []

    var isEmpty: Bool {
        projects.isEmpty && goals.isEmpty && tasks.isEmpty && timeSessions.isEmpty
            && aiExecutions.isEmpty && experiments.isEmpty
    }
}

struct SyncDeletes: Codable, Equatable {
    var projects: [String] = []
    var goals: [String] = []
    var tasks: [String] = []
    var timeSessions: [String] = []
    var aiExecutions: [String] = []
    var experiments: [String] = []

    var isEmpty: Bool {
        projects.isEmpty && goals.isEmpty && tasks.isEmpty && timeSessions.isEmpty
            && aiExecutions.isEmpty && experiments.isEmpty
    }
}

/// Tri-state field: absent (unchanged) / explicit null (clear) / value.
enum SyncActiveFocus: Equatable {
    case unchanged
    case clear
    case set(ActiveFocus)
}

struct SyncRequest: Encodable {
    var clientTime: Date
    var upserts: SyncUpserts
    var deletes: SyncDeletes
    var settings: UserSettings?
    var activeFocus: SyncActiveFocus = .unchanged
    var aiTools: [AIToolConnection]?

    enum CodingKeys: String, CodingKey {
        case clientTime, upserts, deletes, settings, activeFocus, aiTools
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clientTime, forKey: .clientTime)
        try c.encode(upserts, forKey: .upserts)
        try c.encode(deletes, forKey: .deletes)
        try c.encodeIfPresent(settings, forKey: .settings)
        switch activeFocus {
        case .unchanged: break
        case .clear: try c.encodeNil(forKey: .activeFocus)
        case .set(let focus): try c.encode(focus, forKey: .activeFocus)
        }
        try c.encodeIfPresent(aiTools, forKey: .aiTools)
    }

    var hasChanges: Bool {
        !upserts.isEmpty || !deletes.isEmpty || settings != nil || activeFocus != .unchanged || aiTools != nil
    }
}

struct APIEnvelope<T: Decodable>: Decodable {
    var code: Int
    var message: String
    var data: T?
    var requestId: String?

    enum CodingKeys: String, CodingKey { case code, message, data, requestId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(Int.self, forKey: .code) ?? 0
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        data = try c.decodeIfPresent(T.self, forKey: .data)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
    }
}

struct EmptyData: Decodable {}

struct SendCodeResponse: Decodable {
    var expiresIn: Int?
    var retryAfter: Int?
}

struct RevokedResponse: Decodable { var revoked: Bool? }
struct DeletedResponse: Decodable { var deleted: Bool? }
struct ContentVersion: Decodable { var service: String?; var version: Int? }
