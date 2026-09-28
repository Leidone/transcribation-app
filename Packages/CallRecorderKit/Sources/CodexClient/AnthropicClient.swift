import Foundation
import Localization

/// Sends one HTTP request. A protocol so tests can answer without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real network. An ephemeral session keeps no cookies, cache or credentials after the request.
public struct URLSessionTransport: HTTPTransport {
    private let session = URLSession(configuration: .ephemeral)

    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.invalidResponse }
        return (data, http)
    }
}

public enum AnthropicError: LocalizedError, Equatable {
    case invalidKey
    case http(status: Int, message: String)
    case network(String)
    case invalidResponse
    case truncated
    case noResult

    public var errorDescription: String? {
        switch self {
        case .invalidKey: tr("Anthropic не принял этот API-ключ.", "Anthropic did not accept this API key.")
        case .http(let status, let message): tr("Anthropic ответил \(status): \(message)", "Anthropic answered \(status): \(message)")
        case .network(let detail): tr("Не удалось связаться с Anthropic: \(detail)", "Could not reach Anthropic: \(detail)")
        case .invalidResponse: tr("Anthropic прислал нечитаемый ответ.", "Anthropic sent an unreadable answer.")
        case .truncated:
            tr("Ответ оборвался: он оказался слишком длинным. Попробуйте другую модель.",
               "The answer was cut off because it was too long. Try a different model.")
        case .noResult: tr("Claude ничего не вернул.", "Claude returned nothing.")
        }
    }
}

/// Talks to the Anthropic Messages API directly with the person's API key, without Codex in between.
/// The result is forced through one tool whose input schema is the analysis schema, so the reply is always JSON.
public struct AnthropicClient: Sendable {
    public static let apiVersion = "2023-06-01"
    /// The smallest current model: an extraction task does not need more, and it costs the least.
    public static let defaultModel = "claude-haiku-4-5-20251001"

    static let toolName = "submit_analysis"
    /// The standard instructions say "use no tools"; the analysis itself travels through one, so say so.
    static let systemSuffix = "\nDeliver the result by calling the \(toolName) tool."
    static let answerToolName = "submit_answer"
    static let maxOutputTokens = 4096
    static let requestTimeout: TimeInterval = 120
    private static let host = "api.anthropic.com"

    /// The one tool a request may call; its input schema is the shape of the answer.
    struct Tool {
        let name: String
        let description: String
        let schema: JSONValue
    }

    private let apiKey: String
    private let transport: any HTTPTransport

    public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }

    // MARK: Analysis

    public func analyze(transcript: String, prompt: AnalysisPrompt) async throws -> AnalysisOutcome {
        let body = try Self.requestBody(transcript: transcript, prompt: prompt)
        let data = try await perform(path: "messages", body: body)
        return try Self.parseAnalysis(data)
    }

    /// Answers a question about meetings; `model` as in the analysis (`nil` or empty is the default model).
    public func answer(_ question: MeetingQuestion, model: String?) async throws -> AnswerOutcome {
        let body = try Self.requestBody(question: question, model: model)
        let data = try await perform(path: "messages", body: body)
        let (answer, usage) = try Self.parseToolInput(data, toolName: Self.answerToolName, as: MeetingAnswer.self)
        return AnswerOutcome(answer: answer, usage: usage)
    }

    /// The models this key can use, newest first.
    public func availableModels() async throws -> [ModelChoice] {
        let data = try await perform(path: "models?limit=100", body: nil)
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let items)? = root["data"]
        else { throw AnthropicError.invalidResponse }
        return items.compactMap { item in
            guard let id = item["id"]?.stringValue else { return nil }
            return ModelChoice(id: id, name: item["display_name"]?.stringValue ?? id, isDefault: id == Self.defaultModel)
        }
    }

    // MARK: Request and response

    static func requestBody(transcript: String, prompt: AnalysisPrompt) throws -> Data {
        try requestBody(
            system: prompt.instructions + systemSuffix, user: transcript, model: prompt.model,
            tool: Tool(
                name: toolName,
                description: "Report the summary, decisions and tasks found in the call transcript.",
                schema: try CallAnalysis.outputSchema()
            )
        )
    }

    static func requestBody(question: MeetingQuestion, model: String?) throws -> Data {
        try requestBody(
            system: MeetingQuestion.instructions + "\nDeliver the answer by calling the \(answerToolName) tool.",
            user: question.input, model: model,
            tool: Tool(
                name: answerToolName,
                description: "Report the answer and the places in the meetings it rests on.",
                schema: try MeetingAnswer.outputSchema()
            )
        )
    }

    static func requestBody(system: String, user: String, model: String?, tool: Tool) throws -> Data {
        let chosen = model.flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
        let body: JSONValue = .object([
            "model": .string(chosen),
            "max_tokens": .number(Double(maxOutputTokens)),
            "system": .string(system),
            "messages": .array([.object(["role": .string("user"), "content": .string(user)])]),
            "tools": .array([.object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "input_schema": tool.schema,
            ])]),
            "tool_choice": .object(["type": .string("tool"), "name": .string(tool.name)]),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(body)
    }

    static func parseAnalysis(_ data: Data) throws -> AnalysisOutcome {
        let (analysis, usage) = try parseToolInput(data, toolName: toolName, as: CallAnalysis.self)
        return AnalysisOutcome(analysis: analysis, usage: usage)
    }

    /// The input the model gave the forced tool, decoded, with the usage of the request.
    static func parseToolInput<Value: Decodable>(
        _ data: Data, toolName: String, as type: Value.Type
    ) throws -> (Value, TokenUsage?) {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw AnthropicError.invalidResponse
        }
        if root["stop_reason"]?.stringValue == "max_tokens" { throw AnthropicError.truncated }
        guard case .array(let blocks)? = root["content"],
              let input = blocks.first(where: {
                  $0["type"]?.stringValue == "tool_use" && $0["name"]?.stringValue == toolName
              })?["input"]
        else { throw AnthropicError.noResult }

        guard let encoded = try? JSONEncoder().encode(input),
              let value = try? JSONDecoder().decode(type, from: encoded)
        else { throw AnthropicError.invalidResponse }
        return (value, usage(root["usage"]))
    }

    private static func usage(_ value: JSONValue?) -> TokenUsage? {
        guard let value, let fresh = value["input_tokens"]?.intValue, let output = value["output_tokens"]?.intValue else {
            return nil
        }
        let cached = value["cache_read_input_tokens"]?.intValue ?? 0
        let input = fresh + cached + (value["cache_creation_input_tokens"]?.intValue ?? 0)
        return TokenUsage(input: input, cachedInput: cached, output: output, reasoning: 0, total: input + output)
    }

    private func perform(path: String, body: Data?) async throws -> Data {
        guard let url = URL(string: "https://\(Self.host)/v1/\(path)") else { throw AnthropicError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as AnthropicError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw AnthropicError.network(error.localizedDescription)
        }

        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw AnthropicError.invalidKey
        default: throw AnthropicError.http(status: response.statusCode, message: Self.errorMessage(in: data))
        }
    }

    private static func errorMessage(in data: Data) -> String {
        let text = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.stringValue
        return String((text ?? "no details").prefix(300))
    }
}
