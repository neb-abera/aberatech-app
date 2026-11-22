import Foundation
import Testing

@testable import AberaCore

/// The requests, wish list and fitness, through /api/app with the session's token.
struct ClientTests {
    static let session = Session(server: Session.production, token: "abt_token", name: "Heb", role: .household)

    static func client(_ server: FakeAberaServer) -> AberaClient { AberaClient(session: session, transport: server) }

    @Test func an_added_request_never_takes_the_id_of_one_already_there() async throws {
        let server = FakeAberaServer(token: "abt_token", requests: [RequestItem(id: "r1", title: "Rake the leaves")])
        let added = try await Self.client(server).addRequest(RequestInput(title: "Buy leaf bags"))
        #expect(added.id != "r1")
        #expect(Set(try await Self.client(server).requests().map(\.id)).count == 2)
    }

    @Test func a_request_is_added_edited_and_removed() async throws {
        let server = FakeAberaServer(token: "abt_token")
        let client = Self.client(server)

        let added = try await client.addRequest(
            RequestInput(title: "  Rake the leaves ", details: "", due: "2026-11-29", link: nil))
        #expect(added.title == "Rake the leaves")
        #expect(added.details == nil)
        #expect(added.status == .received)

        let edited = try await client.editRequest(
            id: added.id, RequestInput(title: "Rake the front yard", details: "Before Sunday"))
        #expect(edited.details == "Before Sunday")

        try await client.removeRequest(id: added.id)
        #expect(try await client.requests().isEmpty)
        #expect(
            await server.calls == [
                "POST /api/app/requests", "PUT /api/app/requests/\(added.id)",
                "POST /api/app/requests/\(added.id)/remove",
                "GET /api/app/requests",
            ])
    }

    @Test func a_finished_request_cannot_be_changed_and_says_why() async throws {
        let server = FakeAberaServer(token: "abt_token", requests: [RequestItem(id: "r1", title: "Book the flight")])
        await server.setStatus("r1", .done)
        await #expect(throws: APIError.conflict("A finished request cannot be changed.")) {
            try await Self.client(server).editRequest(id: "r1", RequestInput(title: "Again"))
        }
    }

    @Test func a_request_with_no_title_or_a_bad_link_is_stopped_before_it_is_sent() {
        #expect(RequestInput(title: "   ").problem == "Add a title.")
        #expect(
            RequestInput(title: "Fix it", link: "javascript:alert(1)").problem == "The link must start with https://.")
        #expect(RequestInput(title: "Fix it", link: "https://dpw.dc.gov/leaf").problem == nil)
        #expect(RequestInput(title: String(repeating: "a", count: 201)).problem != nil)
    }

    @Test func an_ended_session_and_no_connection_say_so() async {
        let server = FakeAberaServer(token: "abt_token")
        await server.revoke()
        await #expect(throws: APIError.unauthorized) { try await Self.client(server).requests() }
        await server.setOffline(true)
        await #expect(throws: APIError.offline) { try await Self.client(server).requests() }
        #expect(APIError.offline.message == "No connection to abera.tech.")
    }

    @Test func the_server_reads_as_abera_tech_writes_it() throws {
        let json = """
            [{"id":"a-1","title":"Rake leaves","details":null,"due":"2026-11-15","status":"in-progress","reason":null,
              "link":null,"fromEmail":true,"editable":true,"createdAt":"2026-11-08T18:00:00.000Z","updatedAt":"2026-11-09T10:00:00.000Z"},
             {"id":"a-2","title":"Paint","details":null,"due":null,"status":"not-doing","reason":"Hiring it out",
              "link":null,"fromEmail":false,"editable":false,"createdAt":"","updatedAt":""}]
            """
        let items = try JSONDecoder().decode([RequestItem].self, from: Data(json.utf8))
        #expect(items[0].status == .inProgress)
        #expect(items[0].status.label == "In progress")
        #expect(items[1].reason == "Hiring it out")

        let fitness = """
            {"dueOn":"2027-12-31","sections":[{"name":"Strength","goals":[{"label":"Bench Press","unit":"lb","lowerIsBetter":false,
            "current":206.7,"currentOn":"2026-11-17","goal":247.5,"met":false,"projected":227.2,"probability":0.021}]}],
            "weight":[{"date":"2026-11-21","pounds":170.0}]}
            """
        let summary = try JSONDecoder().decode(FitnessSummary.self, from: Data(fitness.utf8))
        #expect(summary.sections[0].goals[0].projected == 227.2)
        #expect(summary.weight.last?.pounds == 170)
    }

    @Test func goal_numbers_read_in_their_own_unit() {
        #expect(GoalFormat.value(1009, unit: "s") == "16:49")
        #expect(GoalFormat.value(7260, unit: "s") == "2:01:00")
        #expect(GoalFormat.value(206.7, unit: "lb") == "207 lb")
        #expect(GoalFormat.value(nil, unit: "lb") == "none yet")
        #expect(GoalFormat.value(540, unit: "s/mi") == "9:00/mi")
        #expect(GoalFormat.chance(0.021) == "2%")
        #expect(GoalFormat.chance(0.004) == "under 1%")
        #expect(GoalFormat.chance(nil) == nil)
    }
}
