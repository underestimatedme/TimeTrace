import Foundation

/// 与 Valley `POST /events` 的事件字典一一对应；新增事件必须两端同时加。
enum UsageEventName: String, CaseIterable, Codable {
    case screenView = "screen_view"
    case dispatchStarted = "dispatch_started"
    case dispatchSucceeded = "dispatch_succeeded"
    case dispatchFailed = "dispatch_failed"
    case scheduleCreated = "schedule_created"
    case pairingStep = "pairing_step"
    case planAccepted = "plan_accepted"
    case reportOpened = "report_opened"
    case reportAction = "report_action"
    case quotaViewed = "quota_viewed"
    case appOpen = "app_open"
}

/// 属性值只允许标量；服务端同样拒绝对象、数组与 null。
enum UsageValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        }
    }
}

struct UsageEvent: Codable, Equatable {
    var name: String
    var at: Date
    var props: [String: UsageValue]
}

struct UsageEventsBody: Codable, Equatable {
    var events: [UsageEvent]
    var appVersion: String
}

struct UsageEventsReceipt: Decodable {
    var accepted: Int
    var dropped: Int
}

/// 每个事件只保留白名单里的字段：任务标题、提示词、仓库路径、账号这类自由文本字段
/// 根本不在名单里，传进来也会被丢掉；字符串再截到 64 个 Unicode 标量（与服务端的上限一致）。
enum UsageSanitizer {
    static let maxProps = 8
    static let maxStringScalars = 64

    static let allowedKeys: [UsageEventName: [String]] = [
        .appOpen: [],
        .screenView: ["screen"],
        .dispatchStarted: ["tool", "scheduled", "error_code", "source"],
        .dispatchSucceeded: ["tool", "scheduled", "error_code", "source"],
        .dispatchFailed: ["tool", "scheduled", "error_code", "source"],
        .scheduleCreated: ["tool", "source"],
        .pairingStep: ["step", "result"],
        .planAccepted: ["criteria"],
        .reportOpened: ["scope"],
        .reportAction: ["action"],
        .quotaViewed: ["pools", "source"],
    ]

    static func sanitize(_ name: UsageEventName, props: [String: UsageValue], at: Date) -> UsageEvent {
        let allowed = allowedKeys[name, default: []]
        var clean: [String: UsageValue] = [:]
        for key in allowed.prefix(maxProps) {
            guard let value = props[key] else { continue }
            switch value {
            case .string(let text):
                let scalars = text.unicodeScalars
                clean[key] = scalars.count > maxStringScalars
                    ? .string(String(String.UnicodeScalarView(scalars.prefix(maxStringScalars)))) : value
            case .number(let number):
                if number.isFinite { clean[key] = value }
            case .bool:
                clean[key] = value
            }
        }
        return UsageEvent(name: name.rawValue, at: at, props: clean)
    }
}

/// 自建的使用习惯记录：先进内存 + 磁盘缓冲（最多 500 条，满了丢最旧的），
/// 满 20 条或 App 进出前台时批量上报。离线模式、用户关闭统计时一律不记录；
/// 上报失败不重试打扰用户，也绝不阻塞界面。
@MainActor final class UsageEvents {
    static let shared = UsageEvents()
    static let capacity = 500
    static let defaultFlushThreshold = 20
    static let batchSize = 100
    static let enabledKey = "keji.usageAnalytics.enabled"

    private(set) var buffered: [UsageEvent] = []
    var flushThreshold = UsageEvents.defaultFlushThreshold
    /// 测试里同步落盘，便于立即重新加载验证。
    var persistSynchronously = false

    private var fileURL: URL?
    private var defaults: UserDefaults?
    private var offline = true
    private var appVersion = ""
    private var send: ((UsageEventsBody) async throws -> Void)?
    private var flushing = false
    private let ioQueue = DispatchQueue(label: "keji.usage-events.io", qos: .utility)

    /// 默认开启；关闭时停止记录并清空缓冲。
    var isEnabled: Bool {
        get { defaults?.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            defaults?.set(newValue, forKey: Self.enabledKey)
            if !newValue { clear() }
        }
    }

    private var recording: Bool { !offline && send != nil && isEnabled }

    func configure(fileURL: URL, defaults: UserDefaults, offline: Bool, appVersion: String,
                   send: @escaping (UsageEventsBody) async throws -> Void) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.offline = offline
        self.appVersion = appVersion
        self.send = send
        buffered = []
        if !offline, isEnabled, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONCoding.decoder.decode([UsageEvent].self, from: data) {
            buffered = Array(stored.suffix(Self.capacity))
        }
        if offline || !isEnabled { clear() }
    }

    func record(_ name: UsageEventName, _ props: [String: UsageValue] = [:], at: Date = Date()) {
        guard recording else { return }
        buffered.append(UsageSanitizer.sanitize(name, props: props, at: at))
        if buffered.count > Self.capacity { buffered.removeFirst(buffered.count - Self.capacity) }
        persist()
        if buffered.count >= flushThreshold {
            Task { await self.flush() }
        }
    }

    /// 分批上报。网络失败或尚无会话时保留，下次再发；被服务端判为非法（4xx）的批次直接丢弃，
    /// 否则一条坏数据会永远堵住缓冲。
    func flush() async {
        guard recording, !flushing, let send else { return }
        flushing = true
        defer { flushing = false }
        while recording, !buffered.isEmpty {
            let batch = Array(buffered.prefix(Self.batchSize))
            do {
                try await send(UsageEventsBody(events: batch, appVersion: appVersion))
            } catch let error as APIError where Self.isRejection(error) {
                // fall through: drop the batch
            } catch {
                return
            }
            buffered.removeFirst(min(batch.count, buffered.count))
            persist()
        }
    }

    private static func isRejection(_ error: APIError) -> Bool {
        (40000..<40100).contains(error.code) || (41300..<41400).contains(error.code) || (42200..<42300).contains(error.code)
    }

    private func clear() {
        buffered = []
        guard let fileURL else { return }
        let remove = { try? FileManager.default.removeItem(at: fileURL) }
        if persistSynchronously { _ = remove() } else { ioQueue.async { _ = remove() } }
    }

    private func persist() {
        guard let fileURL, let data = try? JSONCoding.encoder.encode(buffered) else { return }
        let write = {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
        if persistSynchronously { write() } else { ioQueue.async(execute: write) }
    }
}

extension UsageEvents {
    /// Application Support 下的缓冲文件；UI 测试用独立文件，不污染真实数据。
    static func defaultFileURL(uiTesting: Bool) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(uiTesting ? "keji-usage-events-ui-testing.json" : "keji-usage-events.json")
    }
}
