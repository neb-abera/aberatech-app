import Foundation

/// One weigh-in as Apple Health holds it.
public struct WeightSample: Equatable, Sendable {
    public let date: Date
    public let kilograms: Double

    public init(date: Date, kilograms: Double) {
        self.date = date
        self.kilograms = kilograms
    }
}

/// One day's weigh-in, as abera.tech keeps them: the day in the phone's zone.
public struct DailyWeight: Codable, Equatable, Sendable {
    public let date: String
    public let weightKg: Double

    public init(date: String, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}

/// What abera.tech did with an upload.
public struct WeightUploadResult: Codable, Equatable, Sendable {
    public let saved: Int
    public let unchanged: Int

    public init(saved: Int, unchanged: Int) {
        self.saved = saved
        self.unchanged = unchanged
    }
}

/// Sends Apple Health's weigh-ins to abera.tech/fitness, from Neb's phone.
///
/// Neb logs his weight in Lose It, which writes it to Apple Health and
/// sends nothing to Garmin. Apple Health has no server API, so the phone
/// reads it and sends it (2026-11-21).
///
/// Each run sends the last 30 days, one weigh-in a day: the last of the
/// day in the phone's zone. abera.tech stores a day once and answers a
/// repeat with nothing changed. A run that would send exactly what the
/// last one sent stops before the network. Only the owner sends: a
/// household member's phone reads his fitness and never writes it.
public actor WeightSync {
    public static let days = 30
    static let sentDocument = "weights-sent.json"

    let credentials: any CredentialStore
    let transport: any HTTPTransport
    let reader: any WeightReading
    let documents: any DocumentStore
    let now: @Sendable () -> Date
    let calendar: Calendar

    public init(
        credentials: any CredentialStore,
        transport: any HTTPTransport,
        reader: any WeightReading,
        documents: any DocumentStore,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.credentials = credentials
        self.transport = transport
        self.reader = reader
        self.documents = documents
        self.now = now
        self.calendar = calendar
    }

    public enum Outcome: Equatable, Sendable {
        case notSignedIn
        /// Signed in as someone other than the owner.
        case notOwner
        /// Apple Health gave nothing: no weigh-ins, or no permission. iOS
        /// does not tell an app which.
        case nothingToSend
        /// Apple Health refused the read and said why.
        case unreadable(String)
        /// The same days and weights as the last run.
        case alreadySent
        case sent(WeightUploadResult)
        case failed(APIError)

        /// What the Me tab says.
        public var message: String {
            switch self {
            case .notSignedIn: "Sign in to send weigh-ins."
            case .notOwner: "Weigh-ins go up from Neb's phone."
            case .nothingToSend:
                "No weigh-ins in Apple Health in the last 30 days. If Lose It holds some, allow Health access: Settings > Privacy & Security > Health > aberaTech."
            case .unreadable(let reason): "Apple Health could not be read: \(reason)"
            case .alreadySent: "Up to date with abera.tech."
            case .sent(let result): "Sent to abera.tech: \(result.saved) new, \(result.unchanged) already there."
            case .failed(let error): error.message
            }
        }
    }

    @discardableResult
    public func run() async -> Outcome {
        guard let session = try? await credentials.load() else { return .notSignedIn }
        guard session.role == .owner else { return .notOwner }
        let since = calendar.date(byAdding: .day, value: -Self.days, to: calendar.startOfDay(for: now())) ?? now()
        let samples: [WeightSample]
        do {
            samples = try await reader.samples(since: since)
        } catch {
            return .unreadable(String(describing: error))
        }
        let weights = Self.daily(samples, calendar: calendar)
        guard !weights.isEmpty else { return .nothingToSend }

        // Sorted keys: the encoder's key order is not fixed, and this is compared byte for byte.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try? encoder.encode(weights)
        if let body, let last = try? await documents.load(Self.sentDocument), last == body { return .alreadySent }

        do {
            let result = try await AberaClient(session: session, transport: transport).uploadWeights(weights)
            if let body { try? await documents.save(body, as: Self.sentDocument) }
            return .sent(result)
        } catch {
            return .failed(error)
        }
    }

    /// One weigh-in a day, the last of the day in the calendar's zone, oldest
    /// first. A sample abera.tech would refuse is left out, so one bad
    /// reading does not stop the rest.
    static func daily(_ samples: [WeightSample], calendar: Calendar) -> [DailyWeight] {
        var last: [String: WeightSample] = [:]
        for sample in samples where sample.kilograms > 30 && sample.kilograms <= 250 {
            let day = dayString(sample.date, calendar: calendar)
            if let held = last[day], held.date >= sample.date { continue }
            last[day] = sample
        }
        return last.keys.sorted().map { DailyWeight(date: $0, weightKg: (last[$0]!.kilograms * 1000).rounded() / 1000) }
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
