import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum APIError: Error, Equatable, Sendable {
    /// 401: the session ended. Sign in again.
    case unauthorized
    /// 403: signed in, and this is not for this person.
    case forbidden
    case notFound
    /// 409: a finished request cannot be changed.
    case conflict(String)
    /// 400 with the server's reason.
    case refused(String)
    case rateLimited
    /// abera.tech could not reach Notion.
    case unavailable
    case status(Int)
    case badResponse
    /// No connection, a timeout, DNS.
    case offline

    /// What the screen says.
    public var message: String {
        switch self {
        case .unauthorized: "You were signed out. Sign in again."
        case .forbidden: "That is not available to you."
        case .notFound: "That request is gone."
        case .conflict(let reason), .refused(let reason): reason
        case .rateLimited: "Too many changes at once. Wait a minute."
        case .unavailable: "Notion did not answer. Try again."
        case .status(let code): "abera.tech answered \(code)."
        case .badResponse: "abera.tech sent something this app cannot read."
        case .offline: "No connection to abera.tech."
        }
    }
}

/// abera.tech's /api/app, with the session's token.
public struct AberaClient: Sendable {
    public static let maxResponseBytes = 2_000_000

    public let session: Session
    let transport: any HTTPTransport

    public init(session: Session, transport: any HTTPTransport) {
        self.session = session
        self.transport = transport
    }

    public struct Me: Codable, Equatable, Sendable {
        public var name: String
        public var role: String
    }

    public func me() async throws(APIError) -> Me {
        try decode(await send("GET", "me", body: nil))
    }

    public func requests() async throws(APIError) -> [RequestItem] {
        try decode(await send("GET", "requests", body: nil))
    }

    public func addRequest(_ input: RequestInput) async throws(APIError) -> RequestItem {
        try decode(await send("POST", "requests", body: input.cleaned))
    }

    public func editRequest(id: String, _ input: RequestInput) async throws(APIError) -> RequestItem {
        try decode(await send("PUT", "requests/\(id)", body: input.cleaned))
    }

    public func removeRequest(id: String) async throws(APIError) {
        _ = try await send("POST", "requests/\(id)/remove", body: nil)
    }

    public func wishList() async throws(APIError) -> [WishItem] {
        try decode(await send("GET", "wishlist", body: nil))
    }

    public func fitness() async throws(APIError) -> FitnessSummary {
        try decode(await send("GET", "fitness", body: nil))
    }

    public func uploadWeights(_ weights: [DailyWeight]) async throws(APIError) -> WeightUploadResult {
        struct Body: Encodable, Sendable { let weights: [DailyWeight] }
        return try decode(await send("POST", "health/weights", body: Body(weights: weights)))
    }

    /// Ends this phone's session on abera.tech.
    public func signOut() async throws(APIError) {
        _ = try await send("DELETE", "session", body: nil)
    }

    func request(_ method: String, _ path: String, body: (any Encodable & Sendable)?) -> URLRequest {
        var request = URLRequest(url: session.server.appending(path: "api/app/\(path)"))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    func send(_ method: String, _ path: String, body: (any Encodable & Sendable)?) async throws(APIError) -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request(method, path, body: body))
        } catch let error as APIError {
            throw error
        } catch {
            throw .offline
        }
        switch response.statusCode {
        case 200, 201, 204:
            guard data.count <= Self.maxResponseBytes else { throw .badResponse }
            return data
        case 400, 422: throw .refused(Self.reason(data))
        case 401: throw .unauthorized
        case 403: throw .forbidden
        case 404: throw .notFound
        case 409: throw .conflict(Self.reason(data))
        case 429: throw .rateLimited
        case 502, 503: throw .unavailable
        default: throw .status(response.statusCode)
        }
    }

    func decode<T: Decodable>(_ data: Data) throws(APIError) -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw .badResponse }
        return value
    }

    /// The server's reason from a ValidationProblem or a problem detail.
    static func reason(_ data: Data) -> String {
        struct Problem: Decodable {
            var detail: String?
            var title: String?
            var errors: [String: [String]]?
        }
        guard let problem = try? JSONDecoder().decode(Problem.self, from: data) else {
            return "abera.tech refused the request."
        }
        let first = problem.errors?.sorted { $0.key < $1.key }.first?.value.first
        return String((problem.detail ?? first ?? problem.title ?? "abera.tech refused the request.").prefix(200))
    }
}
