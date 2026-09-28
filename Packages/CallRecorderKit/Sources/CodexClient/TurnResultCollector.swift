import Foundation

/// What one request cost, as reported by the model.
public struct TokenUsage: Equatable, Sendable {
    public let input: Int
    public let cachedInput: Int
    public let output: Int
    public let reasoning: Int
    public let total: Int

    init(input: Int, cachedInput: Int, output: Int, reasoning: Int, total: Int) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.reasoning = reasoning
        self.total = total
    }

    init?(_ value: JSONValue?) {
        guard let value, let total = value["totalTokens"]?.intValue else { return nil }
        self.total = total
        input = value["inputTokens"]?.intValue ?? 0
        cachedInput = value["cachedInputTokens"]?.intValue ?? 0
        output = value["outputTokens"]?.intValue ?? 0
        reasoning = value["reasoningOutputTokens"]?.intValue ?? 0
    }
}

/// Folds `codex app-server` notifications of one thread into the final agent message of a turn.
public struct TurnResultCollector: Sendable {
    public enum Outcome: Equatable, Sendable {
        case pending
        case finished(String)
        case failed(String)
    }

    private let threadID: String
    private var lastAgentMessage: String?
    /// The latest usage figures seen for this thread.
    public private(set) var usage: TokenUsage?

    public init(threadID: String) {
        self.threadID = threadID
    }

    public mutating func consume(_ message: JSONRPCMessage) -> Outcome {
        guard case .notification(let method, let params?) = message,
              params["threadId"]?.stringValue == threadID
        else { return .pending }

        switch method {
        case "thread/tokenUsage/updated":
            usage = TokenUsage(params["tokenUsage"]?["total"]) ?? usage
            return .pending
        case "item/completed":
            if let item = params["item"], item["type"]?.stringValue == "agentMessage",
               let text = item["text"]?.stringValue {
                lastAgentMessage = text
            }
            return .pending
        case "turn/completed":
            return outcome(for: params["turn"])
        default:
            return .pending
        }
    }

    private func outcome(for turn: JSONValue?) -> Outcome {
        let status = turn?["status"]?.stringValue ?? "unknown"
        guard status == "completed" else {
            return .failed(turn?["error"]?["message"]?.stringValue ?? "turn ended with status \(status)")
        }
        guard let lastAgentMessage else { return .failed("the turn finished without an answer") }
        return .finished(lastAgentMessage)
    }
}
