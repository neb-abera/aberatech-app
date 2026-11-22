import Foundation
import Testing

@testable import AberaCore

/// The sign-in: a PKCE challenge in the start address, a code from the
/// sheet's redirect checked against this sign-in's state, and the code
/// traded for a session only with the verifier.
struct SignInTests {
    @Test func the_start_address_carries_the_state_and_the_s256_challenge() {
        // RFC 7636 appendix B.
        let signIn = SignIn(state: "s1", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(signIn.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(
            signIn.startURL.absoluteString
                == "https://abera.tech/api/app/sign-in?state=s1&challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(SignIn.random().count == 43)
    }

    @Test func the_redirect_gives_the_code_only_for_this_sign_in() throws {
        let signIn = SignIn(state: "s1")
        #expect(try signIn.code(from: URL(string: "aberatech://signin?state=s1&code=abc")!) == "abc")
        #expect(throws: SignIn.Failure.badCallback) {
            try signIn.code(from: URL(string: "aberatech://signin?state=s2&code=abc")!)
        }
        #expect(throws: SignIn.Failure.notAllowed) {
            try signIn.code(from: URL(string: "aberatech://signin?state=s1&error=not-allowed")!)
        }
        #expect(throws: SignIn.Failure.badCallback) {
            try signIn.code(from: URL(string: "aberaalarms://signin?state=s1&code=abc")!)
        }
    }

    @Test func the_code_becomes_a_session_with_the_verifier_and_not_without_it() async throws {
        let server = FakeAberaServer(token: "abt_token", name: "Heb", role: .household)
        let signIn = SignIn(state: "s1")
        let code = await server.issueCode(challenge: signIn.challenge)

        let session = try await signIn.exchange(code: code, device: "iPhone", transport: server)
        #expect(session == Session(server: Session.production, token: "abt_token", name: "Heb", role: .household))

        // Used once.
        await #expect(throws: SignIn.Failure.server(.unauthorized)) {
            try await signIn.exchange(code: code, device: "iPhone", transport: server)
        }

        // Another app that caught the redirect has the code, not the verifier.
        let stolen = await server.issueCode(challenge: signIn.challenge)
        await #expect(throws: SignIn.Failure.server(.unauthorized)) {
            try await SignIn(state: "s1").exchange(code: stolen, device: "iPhone", transport: server)
        }
    }
}
