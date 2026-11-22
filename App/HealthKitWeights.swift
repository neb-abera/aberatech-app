import AberaCore
import Foundation
import HealthKit

/// Weigh-ins from Apple Health, for abera.tech/fitness.
///
/// Neb logs his weight in Lose It, which writes it to Apple Health. Apple
/// Health has no server API, so the phone reads it here and `WeightSync`
/// sends it (2026-11-21). Read access only. iOS never says whether a read
/// was refused: a refused read returns no samples.
struct HealthKitWeights: WeightReading {
    static let store = HKHealthStore()
    static let bodyMass = HKQuantityType(.bodyMass)

    /// The demo also writes, to put a weigh-in in the simulator's Health.
    var writes = false

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health sheet the first time, and returns at once after.
    /// One request at a time: the launch refresh and the app turning active
    /// both ask, and on 2026-11-22 iOS 27 showed a second sheet for the
    /// second request after the first was allowed.
    func requestAccess() async {
        guard Self.available else { return }
        await Self.requests.ask(toShare: writes ? [Self.bodyMass] : [], read: [Self.bodyMass])
    }

    static let requests = AccessRequests()

    /// Shares a request on screen with every caller, and asks only while
    /// iOS says a request is still needed.
    actor AccessRequests {
        private var pending: Task<Void, Never>?

        func ask(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async {
            if let pending { return await pending.value }
            let task = Task {
                let store = HealthKitWeights.store
                let status = try? await store.statusForAuthorizationRequest(toShare: toShare, read: read)
                guard status != .unnecessary else { return }
                try? await store.requestAuthorization(toShare: toShare, read: read)
            }
            pending = task
            await task.value
            pending = nil
        }
    }

    func samples(since: Date) async throws -> [WeightSample] {
        guard Self.available else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate)])
        return try await query.result(for: Self.store).map {
            WeightSample(date: $0.endDate, kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }

    /// A weigh-in in Health now, for the demo.
    func add(kilograms: Double, at date: Date = Date()) async throws {
        let sample = HKQuantitySample(
            type: Self.bodyMass, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
            start: date, end: date)
        try await Self.store.save(sample)
    }

    /// Runs `onChange` when a weigh-in is added, with the app closed too:
    /// iOS wakes the app for each new sample once background delivery is on.
    static func observe(_ onChange: @escaping @Sendable () async -> Void) {
        guard available else { return }
        let query = HKObserverQuery(sampleType: bodyMass, predicate: nil) { _, completion, error in
            let done = UncheckedCompletion(completion)
            guard error == nil else {
                done.call()
                return
            }
            Task {
                await onChange()
                done.call()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: bodyMass, frequency: .immediate) { _, _ in }
    }
}

/// HealthKit's completion handler, carried into the task that ends it.
/// HealthKit calls it from its own queue, once, and it may be called from any.
private struct UncheckedCompletion: @unchecked Sendable {
    let completion: HKObserverQueryCompletionHandler
    init(_ completion: @escaping HKObserverQueryCompletionHandler) { self.completion = completion }
    func call() { completion() }
}
