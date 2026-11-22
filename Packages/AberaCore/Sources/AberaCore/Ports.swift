import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sends one HTTP request. The app passes URLSession. Tests pass a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Where the session lives. The app uses the Keychain, this device only.
public protocol CredentialStore: Sendable {
    func load() async throws -> Session?
    func save(_ session: Session) async throws
    func remove() async throws
}

/// Small documents that survive a restart. The app keeps them in
/// Application Support. Tests keep them in memory.
public protocol DocumentStore: Sendable {
    func load(_ name: String) async throws -> Data?
    func save(_ data: Data, as name: String) async throws
}

/// The phone's weigh-ins. The app passes Apple Health. Tests pass a fake.
public protocol WeightReading: Sendable {
    /// Weigh-ins since the date, in any order.
    func samples(since: Date) async throws -> [WeightSample]
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        return (data, http)
    }
}
