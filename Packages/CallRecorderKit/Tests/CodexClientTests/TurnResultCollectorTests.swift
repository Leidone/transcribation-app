import Foundation
import Testing
@testable import CodexClient

struct TurnResultCollectorTests {
    private func agentMessage(thread: String, text: String) -> JSONRPCMessage {
        .notification(method: "item/completed", params: .object([
            "threadId": .string(thread),
            "item": .object(["type": .string("agentMessage"), "id": .string("i1"), "text": .string(text)]),
        ]))
    }

    private func turnCompleted(thread: String, status: String, error: String? = nil) -> JSONRPCMessage {
        var turn: [String: JSONValue] = ["id": .string("u1"), "status": .string(status)]
        if let error { turn["error"] = .object(["message": .string(error)]) }
        return .notification(method: "turn/completed", params: .object([
            "threadId": .string(thread), "turn": .object(turn),
        ]))
    }

    @Test("returns the last agent message once the turn completes")
    func finishesWithAgentMessage() {
        // Arrange
        var collector = TurnResultCollector(threadID: "t1")

        // Act
        let midway = collector.consume(agentMessage(thread: "t1", text: "{\"ok\":true}"))
        let outcome = collector.consume(turnCompleted(thread: "t1", status: "completed"))

        // Assert
        #expect(midway == .pending)
        #expect(outcome == .finished("{\"ok\":true}"))
    }

    @Test("remembers the token usage the model reports")
    func remembersUsage() {
        var collector = TurnResultCollector(threadID: "t1")
        let update = JSONRPCMessage.notification(method: "thread/tokenUsage/updated", params: .object([
            "threadId": .string("t1"),
            "tokenUsage": .object(["total": .object([
                "inputTokens": .number(900), "cachedInputTokens": .number(100), "outputTokens": .number(120),
                "reasoningOutputTokens": .number(20), "totalTokens": .number(1020),
            ])]),
        ]))

        let outcome = collector.consume(update)

        #expect(outcome == .pending)
        #expect(collector.usage?.input == 900)
        #expect(collector.usage?.output == 120)
        #expect(collector.usage?.total == 1020)
    }

    @Test("usage of another thread is ignored")
    func ignoresOtherThreadUsage() {
        var collector = TurnResultCollector(threadID: "t1")
        _ = collector.consume(.notification(method: "thread/tokenUsage/updated", params: .object([
            "threadId": .string("t2"),
            "tokenUsage": .object(["total": .object(["totalTokens": .number(5)])]),
        ])))

        #expect(collector.usage == nil)
    }

    @Test("reports the model error when the turn fails")
    func failsWithReason() {
        var collector = TurnResultCollector(threadID: "t1")
        let outcome = collector.consume(turnCompleted(thread: "t1", status: "failed", error: "rate limited"))
        #expect(outcome == .failed("rate limited"))
    }

    @Test("ignores notifications of other threads")
    func ignoresOtherThreads() {
        var collector = TurnResultCollector(threadID: "t1")
        _ = collector.consume(agentMessage(thread: "t2", text: "other"))
        #expect(collector.consume(turnCompleted(thread: "t2", status: "completed")) == .pending)
    }

    @Test("a completed turn without an answer is a failure")
    func completedWithoutAnswerFails() {
        var collector = TurnResultCollector(threadID: "t1")
        let outcome = collector.consume(turnCompleted(thread: "t1", status: "completed"))
        #expect(outcome == .failed("the turn finished without an answer"))
    }
}
