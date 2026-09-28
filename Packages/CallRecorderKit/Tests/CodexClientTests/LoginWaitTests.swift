import Foundation
import Testing
@testable import CodexClient

struct LoginWaitTests {
    private func completed(loginID: String, success: Bool, error: String? = nil) -> JSONRPCMessage {
        var params: [String: JSONValue] = ["loginId": .string(loginID), "success": .bool(success)]
        if let error { params["error"] = .string(error) }
        return .notification(method: "account/login/completed", params: .object(params))
    }

    private func stream(_ messages: [JSONRPCMessage], finish: Bool = true) -> AsyncStream<JSONRPCMessage> {
        let (stream, continuation) = AsyncStream<JSONRPCMessage>.makeStream()
        for message in messages { continuation.yield(message) }
        if finish { continuation.finish() }
        return stream
    }

    @Test("returns when the matching login completes successfully")
    func succeeds() async throws {
        let events = stream([
            completed(loginID: "other", success: true),
            completed(loginID: "mine", success: true),
        ])

        try await LoginWait.completion(loginID: "mine", in: events, timeout: .seconds(5))
    }

    @Test("throws the server's reason when the login fails")
    func failure() async {
        let events = stream([completed(loginID: "mine", success: false, error: "access_denied")])

        await #expect(throws: CodexError.loginFailed("access_denied")) {
            try await LoginWait.completion(loginID: "mine", in: events, timeout: .seconds(5))
        }
    }

    @Test("gives up after the timeout when the user never finishes signing in")
    func timesOut() async {
        let events = stream([], finish: false)

        await #expect(throws: CodexError.loginTimedOut) {
            try await LoginWait.completion(loginID: "mine", in: events, timeout: .milliseconds(100))
        }
    }

    @Test("reports a stopped process when the stream ends first")
    func streamEnds() async {
        let events = stream([])

        await #expect(throws: CodexError.processExited) {
            try await LoginWait.completion(loginID: "mine", in: events, timeout: .seconds(5))
        }
    }
}
