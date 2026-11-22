#if DEBUG
    import AberaCore
    import Foundation

    /// The app with abera.tech in memory, for the UI tests and for trying
    /// the screens in the simulator. Debug builds only.
    ///
    /// `-demo` starts signed in as a household member with four requests.
    /// `-demo-owner` signs in as Neb instead. `-demo-signed-out` starts on
    /// the sign-in screen, and Sign in finishes at once without a browser.
    /// `-demo-health` sends Apple Health weigh-ins to the demo server
    /// through the simulator's real HealthKit, with one weigh-in of
    /// 77.111 kg put there first.
    enum Demo {
        static let token = "abt_" + String(repeating: "D", count: 43)

        static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Dependencies? {
            guard arguments.contains("-demo") else { return nil }
            let owner = arguments.contains("-demo-owner")
            let role: Session.Role = owner ? .owner : .household
            let name = owner ? "Neb" : "Heb"
            let server = FakeAberaServer(
                token: token, name: name, role: role, requests: requests, wishList: wishList, fitness: fitness)
            let session = Session(server: Session.production, token: token, name: name, role: role)
            let credentials = MemoryCredentials(arguments.contains("-demo-signed-out") ? nil : session)
            let health = arguments.contains("-demo-health") ? HealthKitWeights(writes: true) : nil
            return Dependencies(
                credentials: credentials,
                transport: server,
                server: Session.production,
                weights: health.map {
                    WeightSync(
                        credentials: credentials, transport: server, reader: SeededHealth(health: $0),
                        documents: MemoryDocuments())
                },
                health: health,
                demoSignIn: { signIn in
                    let code = await server.issueCode(challenge: signIn.challenge)
                    return URL(string: "aberatech://signin?state=\(signIn.state)&code=\(code)")!
                })
        }

        static let requests: [RequestItem] = [
            RequestItem(
                id: "r1", title: "Rake the leaves to the tree box", details: "Section B, before Sunday",
                due: "2026-11-29", fromEmail: true),
            RequestItem(id: "r2", title: "Fix the bathroom faucet", status: .inProgress),
            RequestItem(id: "r3", title: "Book the flight to Kansas City", status: .done, editable: false),
            RequestItem(
                id: "r4", title: "Paint the fence", status: .notDoing, reason: "Hiring it out", editable: false),
        ]

        static let wishList: [WishItem] = [
            WishItem(id: "w1", item: "Running shoes", pick: "Nike Pegasus 42", price: 160, buyWindow: "Now"),
            WishItem(id: "w2", item: "AI camera", price: 299, buyWindow: "Q1 2027"),
        ]

        static let fitness = FitnessSummary(
            dueOn: "2027-12-31",
            sections: [
                .init(
                    name: "Strength",
                    goals: [
                        .init(
                            label: "Bench Press", unit: "lb", current: 206.7, currentOn: "2026-11-17", goal: 247.5,
                            met: false, projected: 227.2, probability: 0.021)
                    ]),
                .init(
                    name: "Running",
                    goals: [
                        .init(
                            label: "2 mile", unit: "s", lowerIsBetter: true, current: 1009, goal: 840, met: false,
                            projected: 905, probability: 0.31)
                    ]),
            ],
            weight: [.init(date: "2026-11-19", pounds: 170.6), .init(date: "2026-11-21", pounds: 170.0)])
    }

    /// The simulator's Health with one weigh-in put there before the first read.
    actor SeededHealth: WeightReading {
        let health: HealthKitWeights
        private var seeded = false

        init(health: HealthKitWeights) { self.health = health }

        func samples(since: Date) async throws -> [WeightSample] {
            // Marked done only once the write succeeds. On iOS 27
            // (2026-11-22) the launch observer read first, before Health
            // access was allowed, and the refused write was never retried.
            if !seeded, (try? await health.add(kilograms: 77.111)) != nil {
                seeded = true
            }
            return try await health.samples(since: since)
        }
    }
#endif
