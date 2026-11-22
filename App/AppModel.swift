import AberaCore
import Foundation
import Observation
import UIKit

/// The screens' state. Every button calls one method here.
@MainActor
@Observable
final class AppModel {
    private(set) var session: Session?
    private(set) var started = false
    private(set) var busy = false
    private(set) var requests: [RequestItem] = []
    private(set) var wishList: [WishItem] = []
    private(set) var fitness: FitnessSummary?
    private(set) var signInError: String?
    /// The last thing that went wrong, for the screen that asked.
    private(set) var error: String?
    /// What the last send of Apple Health weigh-ins did.
    private(set) var weightStatus: String?

    let dependencies: Dependencies

    init(dependencies: Dependencies = .shared) {
        self.dependencies = dependencies
    }

    var isOwner: Bool { session?.role == .owner }

    func start() async {
        session = try? await dependencies.credentials.load()
        started = true
        if session != nil { await refresh() }
    }

    // MARK: Sign-in

    /// Google in a browser sheet, then the code traded for a session.
    /// `authenticate` opens the sheet and returns its last address.
    func signIn(authenticate: @escaping @MainActor (URL) async throws -> URL) async {
        signInError = nil
        busy = true
        defer { busy = false }
        let signIn = SignIn(server: dependencies.server)
        do {
            let callback: URL
            if let demo = dependencies.demoSignIn {
                callback = await demo(signIn)
            } else {
                callback = try await authenticate(signIn.startURL)
            }
            let code = try signIn.code(from: callback)
            let session = try await signIn.exchange(
                code: code, device: UIDevice.current.name, transport: dependencies.transport)
            try await dependencies.credentials.save(session)
            self.session = session
            await refresh()
        } catch let failure as SignIn.Failure {
            signInError = Self.describe(failure)
        } catch {
            // The person closed the sheet. Nothing to say.
        }
    }

    func signOut() async {
        if let client = client() { try? await client.signOut() }
        await forget()
    }

    // MARK: Loading

    func refresh() async {
        await loadRequests()
        await loadFitness()
        await loadWishList()
        if isOwner { await sendWeights() }
    }

    func loadRequests() async {
        guard let client = client() else { return }
        do {
            requests = try await client.requests()
            error = nil
        } catch {
            await handle(error)
        }
    }

    func loadWishList() async {
        guard let client = client() else { return }
        do {
            wishList = try await client.wishList()
        } catch {
            await handle(error)
        }
    }

    func loadFitness() async {
        guard let client = client() else { return }
        do {
            fitness = try await client.fitness()
        } catch {
            await handle(error)
        }
    }

    // MARK: Requests

    /// True when abera.tech stored it, so the form can close.
    func add(_ input: RequestInput) async -> Bool {
        if let problem = input.problem {
            error = problem
            return false
        }
        guard let client = client() else { return false }
        busy = true
        defer { busy = false }
        do {
            let item = try await client.addRequest(input)
            requests.insert(item, at: 0)
            error = nil
            return true
        } catch {
            await handle(error)
            return false
        }
    }

    func edit(_ id: String, _ input: RequestInput) async -> Bool {
        if let problem = input.problem {
            error = problem
            return false
        }
        guard let client = client() else { return false }
        busy = true
        defer { busy = false }
        do {
            let item = try await client.editRequest(id: id, input)
            if let index = requests.firstIndex(where: { $0.id == id }) { requests[index] = item }
            error = nil
            return true
        } catch {
            await handle(error)
            return false
        }
    }

    /// Off her list at once. abera.tech archives it in Notion with the reason
    /// "Removed by" her name, and never deletes it.
    func remove(_ id: String) async {
        guard let client = client() else { return }
        let before = requests
        requests.removeAll { $0.id == id }
        do {
            try await client.removeRequest(id: id)
            error = nil
        } catch {
            requests = before
            await handle(error)
        }
    }

    func clearError() { error = nil }

    // MARK: Apple Health

    /// The last 30 days of Apple Health weigh-ins to abera.tech/fitness.
    /// The first time, iOS shows the Health sheet.
    func sendWeights() async {
        guard isOwner, let weights = dependencies.weights else { return }
        await dependencies.health?.requestAccess()
        weightStatus = await weights.run().message
    }

    /// Sends a weigh-in when HealthKit adds one, with the app closed too.
    nonisolated static func observeWeights(_ dependencies: Dependencies = .shared) {
        guard let weights = dependencies.weights, dependencies.health != nil else { return }
        HealthKitWeights.observe { _ = await weights.run() }
    }

    // MARK: Private

    private func client() -> AberaClient? {
        session.map { AberaClient(session: $0, transport: dependencies.transport) }
    }

    private func handle(_ error: APIError) async {
        if error == .unauthorized {
            await forget()
            signInError = error.message
        } else {
            self.error = error.message
        }
    }

    private func forget() async {
        try? await dependencies.credentials.remove()
        session = nil
        requests = []
        wishList = []
        fitness = nil
        weightStatus = nil
        error = nil
    }

    static func describe(_ failure: SignIn.Failure) -> String {
        switch failure {
        case .notAllowed: "That Google account is not set up for aberaTech. Sign in with the account Neb added."
        case .badCallback: "The sign-in did not finish. Try again."
        case .server(let error): error.message
        }
    }
}
