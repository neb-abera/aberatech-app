import Foundation
import Testing

@testable import AberaCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Answers one status to everything, for the error paths.
private actor Answering: HTTPTransport {
    let status: Int
    let body: Data

    init(_ status: Int, _ body: String = "") {
        self.status = status
        self.body = Data(body.utf8)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct CoverageTests {
    static let session = Session(server: Session.production, token: "abt_token", name: "Heb", role: .household)

    @Test func the_wish_list_fitness_and_me_read_and_sign_out_ends_the_session() async throws {
        let server = FakeAberaServer(
            token: "abt_token",
            wishList: [WishItem(id: "w1", item: "Running shoes", price: 160, buyWindow: "Now")],
            fitness: FitnessSummary(
                dueOn: "2027-12-31",
                sections: [
                    .init(name: "Strength", goals: [.init(label: "Bench", unit: "lb", current: 207, goal: 247.5)])
                ],
                weight: [.init(date: "2026-11-21", pounds: 170)]))
        let client = AberaClient(session: Self.session, transport: server)

        #expect(try await client.wishList().map(\.item) == ["Running shoes"])
        #expect(try await client.fitness().sections.first?.goals.first?.id == "Bench")
        #expect(try await client.fitness().sections.first?.id == "Strength")
        #expect(try await client.fitness().weight.first?.id == "2026-11-21")
        #expect(try await client.me() == AberaClient.Me(name: "Heb", role: "household"))
        try await client.signOut()
        await #expect(throws: APIError.unauthorized) { try await client.me() }
    }

    @Test func a_household_phone_cannot_send_weigh_ins_and_an_unknown_request_is_gone() async {
        let server = FakeAberaServer(token: "abt_token")
        let client = AberaClient(session: Self.session, transport: server)
        await #expect(throws: APIError.forbidden) {
            try await client.uploadWeights([DailyWeight(date: "2026-11-21", weightKg: 77.1)])
        }
        await #expect(throws: APIError.notFound) { try await client.removeRequest(id: "nope") }
        await #expect(throws: APIError.refused("Add a title.")) {
            try await client.addRequest(RequestInput(title: " "))
        }
    }

    @Test(arguments: [
        (400, #"{"errors":{"request":["The date is not a date."]}}"#, APIError.refused("The date is not a date.")),
        (403, "", APIError.forbidden),
        (404, "", APIError.notFound),
        (409, #"{"detail":"Finished."}"#, APIError.conflict("Finished.")),
        (429, "", APIError.rateLimited),
        (502, "", APIError.unavailable),
        (500, "", APIError.status(500)),
        (200, "not json", APIError.badResponse),
        (400, "not json", APIError.refused("abera.tech refused the request.")),
    ])
    func every_status_reads_as_what_it_means(status: Int, body: String, error: APIError) async {
        let client = AberaClient(session: Self.session, transport: Answering(status, body))
        await #expect(throws: error) { try await client.requests() }
        #expect(!error.message.isEmpty)
    }

    @Test func every_message_is_plain() {
        for error in [
            APIError.unauthorized, .forbidden, .notFound, .conflict("x"), .refused("x"), .rateLimited, .unavailable,
            .status(500), .badResponse, .offline,
        ] {
            #expect(!error.message.isEmpty)
        }
        for outcome in [
            WeightSync.Outcome.notSignedIn, .notOwner, .nothingToSend, .alreadySent,
            .sent(WeightUploadResult(saved: 2, unchanged: 1)), .failed(.offline),
        ] {
            #expect(!outcome.message.isEmpty)
        }
        #expect(
            WeightSync.Outcome.sent(WeightUploadResult(saved: 2, unchanged: 1)).message
                == "Sent to abera.tech: 2 new, 1 already there.")
        #expect(RequestItem.Status.allCases.map(\.label) == ["Received", "In progress", "Done", "Not doing"])
        #expect(RequestItem.Status.allCases.map(\.isOpen) == [true, true, false, false])
    }

    @Test func the_exchange_says_why_it_failed() async {
        let signIn = SignIn(state: "s1")
        await #expect(throws: SignIn.Failure.server(.rateLimited)) {
            try await signIn.exchange(code: "c", device: "iPhone", transport: Answering(429))
        }
        await #expect(throws: SignIn.Failure.server(.status(500))) {
            try await signIn.exchange(code: "c", device: "iPhone", transport: Answering(500))
        }
        await #expect(throws: SignIn.Failure.server(.badResponse)) {
            try await signIn.exchange(
                code: "c", device: "iPhone", transport: Answering(200, #"{"token":"t","name":"Heb","role":"guest"}"#))
        }
        let offline = FakeAberaServer(token: "t")
        await offline.setOffline(true)
        await #expect(throws: SignIn.Failure.server(.offline)) {
            try await signIn.exchange(code: "c", device: "iPhone", transport: offline)
        }
        #expect(throws: SignIn.Failure.badCallback) {
            try signIn.code(from: URL(string: "aberatech://signin?state=s1")!)
        }
    }

    @Test func every_unit_reads_as_a_person_says_it() {
        #expect(GoalFormat.value(12, unit: "reps") == "12 reps")
        #expect(GoalFormat.value(20.04, unit: "%") == "20.0%")
        #expect(GoalFormat.value(100, unit: "m") == "100 m")
        #expect(GoalFormat.value(1.5, unit: "xbw") == "1.50× bodyweight")
        #expect(GoalFormat.value(3, unit: "") == "3")
        #expect(GoalFormat.chance(0.999) == "over 99%")
    }

    @Test func the_fake_server_edits_only_what_exists() async throws {
        let server = FakeAberaServer(token: "abt_token", requests: [RequestItem(id: "r1", title: "Rake")])
        let client = AberaClient(session: Self.session, transport: server)
        await #expect(throws: APIError.refused("abera.tech refused the request.")) {
            try await client.editRequest(id: "r1", RequestInput(title: ""))
        }
        await #expect(throws: APIError.notFound) { try await client.editRequest(id: "r9", RequestInput(title: "x")) }
        let documents = MemoryDocuments()
        await documents.save(Data("x".utf8), as: "a")
        #expect(await documents.load("a") == Data("x".utf8))
        let credentials = MemoryCredentials(Self.session)
        await credentials.remove()
        #expect(await credentials.load() == nil)
    }

    @Test func a_slow_server_still_answers_and_a_non_http_answer_is_refused() async throws {
        let server = FakeAberaServer(token: "abt_token")
        await server.setLatency(.milliseconds(5))
        #expect(try await AberaClient(session: Self.session, transport: server).requests().isEmpty)
        await server.setStatus("missing", .done)

        let file = FileManager.default.temporaryDirectory.appending(path: "aberacore-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        // A file is not HTTP: Apple's URLSession reads it and the adapter
        // refuses it, and Linux's refuses the scheme first. Either way, no answer.
        await #expect(throws: (any Error).self) {
            _ = try await URLSession(configuration: .ephemeral).send(URLRequest(url: file))
        }
    }
}
