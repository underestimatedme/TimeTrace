import Foundation

/// URLSession client: envelope decoding, bearer auth, one refresh-and-retry on 401/40100.
final class APIClient {
    static let defaultBaseURL = "https://apis.atlaspaces.com/timetrace/api/v1"

    let baseURL: URL
    let keychain: KeychainStore
    private let session: URLSession
    private var isRefreshing = false

    init(baseURL: URL? = nil, keychain: KeychainStore = KeychainStore(), session: URLSession = .shared) {
        self.baseURL = baseURL ?? APIClient.resolveBaseURL()
        self.keychain = keychain
        self.session = session
    }

    /// Order: `--api-base-url <url>` launch arg > env `KEJI_API_BASE_URL` > Info.plist > default.
    static func resolveBaseURL(arguments: [String] = ProcessInfo.processInfo.arguments,
                               environment: [String: String] = ProcessInfo.processInfo.environment,
                               bundle: Bundle = .main) -> URL {
        if let idx = arguments.firstIndex(of: "--api-base-url"), idx + 1 < arguments.count,
           let url = URL(string: arguments[idx + 1]) { return url }
        if let env = environment["KEJI_API_BASE_URL"], let url = URL(string: env) { return url }
        if let plist = bundle.object(forInfoDictionaryKey: "KEJI_API_BASE_URL") as? String, let url = URL(string: plist) {
            return url
        }
        return URL(string: defaultBaseURL)!
    }

    var tokens: SessionTokens? { keychain.loadTokens() }
    var hasSession: Bool { tokens != nil }

    func storeTokens(_ tokens: SessionTokens) {
        var stamped = tokens
        if stamped.obtainedAt == nil { stamped.obtainedAt = Date() }
        keychain.saveTokens(stamped)
    }
    func clearTokens() { keychain.clear() }

    // MARK: - Requests

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type, allowRefresh: Bool = true) async throws -> T {
        // Proactive refresh: guest access tokens live 900s; renew shortly before expiry.
        if endpoint.requiresAuth, allowRefresh, let current = tokens, current.isExpiringSoon(), !current.refreshToken.isEmpty {
            _ = await refreshSession()
        }
        let request = try buildRequest(endpoint)
        let (data, response) = try await perform(request)
        let http = response as? HTTPURLResponse
        let envelope: APIEnvelope<T>
        do {
            envelope = try JSONCoding.decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            if let http, !(200..<300).contains(http.statusCode) {
                throw APIError(code: http.statusCode * 100, message: "HTTP \(http.statusCode)")
            }
            throw APIError.decoding(error)
        }

        let unauthorized = (http?.statusCode == 401) || envelope.code == APIError.unauthorizedCode
        if unauthorized && allowRefresh && endpoint.requiresAuth {
            if await refreshSession() {
                return try await send(endpoint, as: type, allowRefresh: false)
            }
            throw APIError(code: envelope.code == 0 ? APIError.unauthorizedCode : envelope.code,
                           message: envelope.message.isEmpty ? "未授权" : envelope.message)
        }

        if envelope.code != 0 {
            throw APIError(code: envelope.code, message: envelope.message)
        }
        if let http, !(200..<300).contains(http.statusCode) {
            throw APIError(code: http.statusCode * 100, message: envelope.message.isEmpty ? "HTTP \(http.statusCode)" : envelope.message)
        }
        if let data = envelope.data { return data }
        // Endpoints like logout may return an empty `data`; allow decoding from `{}`.
        if let empty = try? JSONCoding.decoder.decode(T.self, from: Data("{}".utf8)) { return empty }
        throw APIError(code: -5, message: "响应缺少 data")
    }

    /// `POST /auth/refresh` once; stores new tokens on success.
    func refreshSession() async -> Bool {
        guard !isRefreshing, let current = tokens else { return false }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var fresh = try await send(Endpoint.refresh(refreshToken: current.refreshToken), as: SessionTokens.self, allowRefresh: false)
            fresh.obtainedAt = Date()
            storeTokens(fresh)
            return true
        } catch {
            return false
        }
    }

    private func buildRequest(_ endpoint: Endpoint) throws -> URLRequest {
        let path = endpoint.path.hasPrefix("/") ? String(endpoint.path.dropFirst()) : endpoint.path
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL : URL(string: baseURL.absoluteString + "/")!
        guard let url = URL(string: path, relativeTo: base) else { throw APIError(code: -6, message: "URL 无效") }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let tokens, endpoint.requiresAuth || endpoint.path == "/auth/login" {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        } else if endpoint.requiresAuth {
            throw APIError.noSession
        }
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONCoding.encoder.encode(AnyEncodable(body))
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
    }
}

struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ value: Encodable) { encodeFn = value.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
