import AberaCore
import Foundation
import Security

/// The parts the app and a HealthKit wake share.
struct Dependencies: Sendable {
    let credentials: any CredentialStore
    let transport: any HTTPTransport
    let server: URL
    /// Apple Health's weigh-ins to abera.tech/fitness, for the owner.
    var weights: WeightSync?
    var health: HealthKitWeights?
    /// The demo build signs in without a browser.
    var demoSignIn: (@Sendable (SignIn) async -> URL)?

    static let shared: Dependencies = {
        #if DEBUG
            if let demo = Demo.fromLaunchArguments() { return demo }
        #endif
        let credentials = KeychainCredentials()
        let transport = URLSession(configuration: .ephemeral)
        return Dependencies(
            credentials: credentials,
            transport: transport,
            server: Session.production,
            weights: WeightSync(
                credentials: credentials, transport: transport, reader: HealthKitWeights(), documents: FileDocuments()),
            health: HealthKitWeights())
    }()
}

/// The session, in the Keychain, readable after the first unlock so a
/// HealthKit wake on a locked phone can send, and never copied to a backup
/// or another device.
struct KeychainCredentials: CredentialStore {
    struct KeychainError: Error {
        let status: OSStatus
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "tech.abera.app",
            kSecAttrAccount as String: "session",
        ]
    }

    func load() async throws -> Session? {
        var request = query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func save(_ session: Session) async throws {
        try await remove()
        var item = query()
        item[kSecValueData as String] = try JSONEncoder().encode(session)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func remove() async throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// What the weigh-in sync last sent, in Application Support.
struct FileDocuments: DocumentStore {
    private func url(_ name: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "AberaTech", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    func load(_ name: String) async throws -> Data? {
        let file = try url(name)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
        return try Data(contentsOf: file)
    }

    func save(_ data: Data, as name: String) async throws {
        try data.write(to: try url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
