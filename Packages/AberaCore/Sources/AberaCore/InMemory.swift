import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public actor MemoryCredentials: CredentialStore {
    var session: Session?

    public init(_ session: Session? = nil) { self.session = session }

    public func load() -> Session? { session }
    public func save(_ session: Session) { self.session = session }
    public func remove() { session = nil }
}

public actor MemoryDocuments: DocumentStore {
    var files: [String: Data] = [:]

    public init() {}

    public func load(_ name: String) -> Data? { files[name] }
    public func save(_ data: Data, as name: String) { files[name] = data }
}

/// Weigh-ins as Apple Health would give them.
public actor MemoryWeights: WeightReading {
    public var stored: [WeightSample]
    public var denied = false
    /// A read that throws, as Apple Health does while the phone is locked.
    public var failure: String?

    public init(_ stored: [WeightSample] = []) { self.stored = stored }

    public func add(_ sample: WeightSample) { stored.append(sample) }
    public func deny() { denied = true }
    public func fail(_ reason: String?) { failure = reason }

    public func samples(since: Date) async throws -> [WeightSample] {
        if let failure { throw ReadFailure(reason: failure) }
        // Apple Health answers a denied read with nothing, not an error.
        return denied ? [] : stored.filter { $0.date >= since }
    }

    struct ReadFailure: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}

/// abera.tech's /api/app in memory: the sign-in exchange, one person's
/// requests, the wish list, the fitness summary, and weigh-ins. For the
/// tests and the demo build.
public actor FakeAberaServer: HTTPTransport {
    public var requestItems: [RequestItem]
    public var wishItems: [WishItem]
    public var fitnessSummary: FitnessSummary
    public private(set) var weights: [String: Double] = [:]
    public private(set) var calls: [String] = []
    public var offline = false
    public var latency: Duration = .zero
    /// The token the server accepts; empty when the session was ended.
    public var token: String
    public var role: Session.Role
    public var name: String
    /// Codes and their PKCE challenges, as the Google hand-off stores them.
    var codes: [String: String] = [:]
    private var nextId = 1

    public init(
        token: String, name: String = "Heb", role: Session.Role = .household,
        requests: [RequestItem] = [], wishList: [WishItem] = [],
        fitness: FitnessSummary = FitnessSummary(dueOn: nil, sections: [], weight: [])
    ) {
        self.token = token
        self.name = name
        self.role = role
        self.requestItems = requests
        self.wishItems = wishList
        self.fitnessSummary = fitness
    }

    public func setOffline(_ offline: Bool) { self.offline = offline }
    public func setLatency(_ latency: Duration) { self.latency = latency }
    public func revoke() { token = "" }
    public func setStatus(_ id: String, _ status: RequestItem.Status, reason: String? = nil) {
        guard let index = requestItems.firstIndex(where: { $0.id == id }) else { return }
        requestItems[index].status = status
        requestItems[index].reason = reason
        requestItems[index].editable = status.isOpen
    }

    /// What Google and abera.tech do between the sheet opening and the
    /// redirect: a code for this challenge.
    public func issueCode(challenge: String) -> String {
        let code = "code-\(codes.count + 1)"
        codes[code] = challenge
        return code
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if latency > .zero { try? await Task.sleep(for: latency) }
        guard !offline else { throw URLError(.notConnectedToInternet) }
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        calls.append("\(method) \(path)")

        if method == "POST", path == "/api/app/session" {
            struct Body: Decodable { let code, verifier, device: String }
            guard let body = request.httpBody.flatMap({ try? JSONDecoder().decode(Body.self, from: $0) }),
                let challenge = codes.removeValue(forKey: body.code),
                challenge == SignIn(state: "", verifier: body.verifier).challenge
            else { return respond(request, 401) }
            return respond(request, 200, ["token": token, "name": name, "role": role.rawValue])
        }

        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)", !token.isEmpty else {
            return respond(request, 401)
        }

        let parts = path.split(separator: "/").map(String.init)
        switch (method, parts.dropFirst(2).joined(separator: "/")) {
        case ("GET", "me"):
            return respond(request, 200, ["name": name, "role": role.rawValue])
        case ("GET", "requests"):
            return respond(request, 200, requestItems.filter { !($0.reason?.hasPrefix("Removed by") ?? false) })
        case ("POST", "requests"):
            guard let input = decode(RequestInput.self, request) else { return respond(request, 400) }
            if let problem = input.problem { return respond(request, 400, ["errors": ["request": [problem]]]) }
            let item = RequestItem(
                id: "new-\(nextId)", title: input.title, details: input.details, due: input.due, link: input.link)
            nextId += 1
            requestItems.insert(item, at: 0)
            return respond(request, 200, item)
        case ("GET", "wishlist"):
            return respond(request, 200, wishItems)
        case ("GET", "fitness"):
            return respond(request, 200, fitnessSummary)
        case ("POST", "health/weights"):
            guard role == .owner else { return respond(request, 403) }
            struct Upload: Decodable { let weights: [DailyWeight] }
            guard let upload = decode(Upload.self, request), !upload.weights.isEmpty else {
                return respond(request, 400)
            }
            var saved = 0
            for weight in upload.weights where weights[weight.date] != weight.weightKg {
                weights[weight.date] = weight.weightKg
                saved += 1
            }
            return respond(request, 200, WeightUploadResult(saved: saved, unchanged: upload.weights.count - saved))
        case ("DELETE", "session"):
            token = ""
            return respond(request, 204)
        default:
            break
        }

        // requests/{id} and requests/{id}/remove
        if parts.count >= 4, parts[2] == "requests", let index = requestItems.firstIndex(where: { $0.id == parts[3] }) {
            if method == "PUT", parts.count == 4 {
                guard requestItems[index].editable else {
                    return respond(request, 409, ["detail": "A finished request cannot be changed."])
                }
                guard let input = decode(RequestInput.self, request), input.problem == nil else {
                    return respond(request, 400)
                }
                requestItems[index].title = input.title
                requestItems[index].details = input.details
                requestItems[index].due = input.due
                requestItems[index].link = input.link
                return respond(request, 200, requestItems[index])
            }
            if method == "POST", parts.count == 5, parts[4] == "remove" {
                requestItems[index].status = .notDoing
                requestItems[index].reason = "Removed by \(name)"
                requestItems[index].editable = false
                return respond(request, 204)
            }
        }
        return respond(request, 404)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ request: URLRequest) -> T? {
        request.httpBody.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func respond(_ request: URLRequest, _ status: Int) -> (Data, HTTPURLResponse) {
        (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func respond(_ request: URLRequest, _ status: Int, _ body: some Encodable) -> (Data, HTTPURLResponse) {
        (
            (try? JSONEncoder().encode(body)) ?? Data(),
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}
