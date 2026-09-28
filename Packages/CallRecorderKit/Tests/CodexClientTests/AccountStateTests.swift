import Foundation
import Testing
@testable import CodexClient

struct AccountStateTests {
    private func result(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    @Test("no account means signed out and sign-in required")
    func signedOut() throws {
        let state = AccountState(result: try result(#"{"account":null,"requiresOpenaiAuth":true}"#))

        #expect(!state.isSignedIn)
        #expect(state.method == nil)
        #expect(state.requiresOpenAIAuth)
    }

    @Test("a ChatGPT account carries its email and plan")
    func chatGPT() throws {
        let state = AccountState(result: try result(
            #"{"account":{"type":"chatgpt","email":"a@b.c","planType":"plus"},"requiresOpenaiAuth":true}"#
        ))

        #expect(state.isSignedIn)
        #expect(state.method == .chatgpt)
        #expect(state.email == "a@b.c")
        #expect(state.planType == "plus")
    }

    @Test("an API-key account is signed in even though it has no email or plan")
    func apiKey() throws {
        let state = AccountState(result: try result(#"{"account":{"type":"apiKey"},"requiresOpenaiAuth":true}"#))

        #expect(state.isSignedIn)
        #expect(state.method == .apiKey)
        #expect(state.email == nil)
    }
}
