import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Who is signed in, and the token abera.tech issued this phone.
public struct Session: Codable, Equatable, Sendable {
    public var server: URL
    public var token: String
    public var name: String
    public var role: Role

    public enum Role: String, Codable, Sendable {
        /// Neb: his weigh-ins go up from this phone.
        case owner
        /// A household member: their requests, his fitness and wish list.
        case household
    }

    public init(server: URL, token: String, name: String, role: Role) {
        self.server = server
        self.token = token
        self.name = name
        self.role = role
    }

    /// The one server a release build signs in to.
    public static let production = URL(string: "https://abera.tech")!
}

/// The sign-in: Google in a browser sheet, then a one-time code traded for
/// a token.
///
/// The app opens `/api/app/sign-in` with a state and a PKCE challenge. After
/// Google, abera.tech sends the sheet to `aberatech://signin` with a code
/// that lives 2 minutes. The app posts the code with the verifier only it
/// holds. Another app that caught the redirect has the code and not the
/// verifier.
public struct SignIn: Sendable {
    public static let scheme = "aberatech"

    public let server: URL
    public let state: String
    public let verifier: String

    public init(server: URL = Session.production, state: String = SignIn.random(), verifier: String = SignIn.random()) {
        self.server = server
        self.state = state
        self.verifier = verifier
    }

    /// PKCE S256: base64url SHA-256 of the verifier.
    public var challenge: String { Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    /// Where the browser sheet starts.
    public var startURL: URL {
        var components = URLComponents(url: server.appending(path: "api/app/sign-in"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "state", value: state), URLQueryItem(name: "challenge", value: challenge),
        ]
        return components.url!
    }

    public enum Failure: Error, Equatable, Sendable {
        /// The Google account is neither Neb's nor a household member's.
        case notAllowed
        /// The callback was not for this sign-in, or carried nothing usable.
        case badCallback
        case server(APIError)
    }

    /// The code from the sheet's last address, checked against this sign-in's state.
    public func code(from callback: URL) throws(Failure) -> String {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
            components.scheme == Self.scheme, components.host == "signin"
        else { throw .badCallback }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state else { throw .badCallback }
        if value("error") == "not-allowed" { throw .notAllowed }
        guard let code = value("code"), !code.isEmpty, code.count <= 64 else { throw .badCallback }
        return code
    }

    /// Trades the code for a session.
    public func exchange(code: String, device: String, transport: any HTTPTransport) async throws(Failure) -> Session {
        struct Body: Encodable { let code, verifier, device: String }
        struct Answer: Decodable { let token, name, role: String }
        var request = URLRequest(url: server.appending(path: "api/app/session"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Body(code: code, verifier: verifier, device: device))
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw .server(.offline)
        }
        switch response.statusCode {
        case 200:
            guard let answer = try? JSONDecoder().decode(Answer.self, from: data),
                let role = Session.Role(rawValue: answer.role)
            else { throw .server(.badResponse) }
            return Session(server: server, token: answer.token, name: answer.name, role: role)
        case 401: throw .server(.unauthorized)
        case 429: throw .server(.rateLimited)
        default: throw .server(.status(response.statusCode))
        }
    }

    /// 32 random bytes, base64url: 43 characters, as PKCE asks.
    public static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64url(Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
