import Foundation
import Localization

public enum OpenAICompatibleError: LocalizedError, Equatable {
    case invalidKey
    case http(status: Int, message: String)
    case network(String)
    case invalidResponse
    case truncated
    case noResult

    public var errorDescription: String? {
        switch self {
        case .invalidKey: tr("Сервер не принял этот API-ключ.", "The server did not accept this API key.")
        case .http(let status, let message): tr("Сервер ответил \(status): \(message)", "The server answered \(status): \(message)")
        case .network(let detail): tr("Не удалось связаться с сервером: \(detail)", "Could not reach the server: \(detail)")
        case .invalidResponse: tr("Сервер прислал нечитаемый ответ.", "The server sent an unreadable answer.")
        case .truncated:
            tr("Ответ оборвался: он оказался слишком длинным. Попробуйте другую модель.",
               "The answer was cut off because it was too long. Try a different model.")
        case .noResult: tr("Сервер ничего не вернул.", "The server returned nothing.")
        }
    }
}

/// Talks to any server that speaks OpenAI's Chat Completions API directly with the person's key, without Codex
/// in between — the OpenAI API itself, or a compatible one (OpenRouter, Ollama, LM Studio, ...). The result is
/// forced through `response_format: json_schema` in strict mode, so the reply is always the analysis schema;
/// not every third-party server honours strict mode, in which case `parseAnalysis` reports `.invalidResponse`
/// rather than guessing at malformed JSON.
public struct OpenAICompatibleClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!
    /// A small, current, inexpensive model: an extraction task does not need more.
    public static let defaultModel = "gpt-5-mini"

    static let schemaName = "call_analysis"
    static let answerSchemaName = "meeting_answer"
    static let requestTimeout: TimeInterval = 120

    private let apiKey: String
    private let baseURL: URL
    private let transport: any HTTPTransport

    public init(apiKey: String, baseURL: URL = defaultBaseURL, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // `URL(string:relativeTo:)` treats a base URL's last path segment as replaceable unless it ends in "/"
        // (RFC 3986) — without this, "https://host/v1" + "chat/completions" resolves to "https://host/chat/completions",
        // silently dropping "v1". Every base URL, ours and whatever a person types for a custom server, is normalised here.
        self.baseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        self.transport = transport
    }

    // MARK: Analysis

    public func analyze(transcript: String, prompt: AnalysisPrompt) async throws -> AnalysisOutcome {
        let body = try Self.requestBody(transcript: transcript, prompt: prompt)
        let data = try await perform(path: "chat/completions", body: body)
        return try Self.parseAnalysis(data)
    }

    /// Answers a question about meetings; `model` as in the analysis (`nil` or empty is the default model).
    public func answer(_ question: MeetingQuestion, model: String?) async throws -> AnswerOutcome {
        let body = try Self.requestBody(
            system: MeetingQuestion.instructions, user: question.input, model: model,
            schemaName: Self.answerSchemaName, schema: try MeetingAnswer.outputSchema()
        )
        let data = try await perform(path: "chat/completions", body: body)
        let (content, usage) = try Self.parseContent(data)
        guard let answer = try? MeetingAnswer.decode(from: content) else { throw OpenAICompatibleError.invalidResponse }
        return AnswerOutcome(answer: answer, usage: usage)
    }

    /// The models this key can use. Not every OpenAI-compatible server implements `/models` the same way; a
    /// server whose response this cannot parse throws `.invalidResponse` rather than silently returning nothing.
    public func availableModels() async throws -> [ModelChoice] {
        let data = try await perform(path: "models", body: nil)
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let items)? = root["data"]
        else { throw OpenAICompatibleError.invalidResponse }
        return items.compactMap { item in
            guard let id = item["id"]?.stringValue else { return nil }
            return ModelChoice(id: id, name: id, isDefault: id == Self.defaultModel)
        }
    }

    // MARK: Request and response

    static func requestBody(transcript: String, prompt: AnalysisPrompt) throws -> Data {
        try requestBody(
            system: prompt.instructions, user: transcript, model: prompt.model,
            schemaName: schemaName, schema: try CallAnalysis.outputSchema()
        )
    }

    static func requestBody(system: String, user: String, model: String?, schemaName: String, schema: JSONValue) throws -> Data {
        let chosen = model.flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
        let body: JSONValue = .object([
            "model": .string(chosen),
            "messages": .array([
                .object(["role": .string("system"), "content": .string(system)]),
                .object(["role": .string("user"), "content": .string(user)]),
            ]),
            "response_format": .object([
                "type": .string("json_schema"),
                "json_schema": .object([
                    "name": .string(schemaName),
                    "strict": .bool(true),
                    "schema": schema,
                ]),
            ]),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(body)
    }

    static func parseAnalysis(_ data: Data) throws -> AnalysisOutcome {
        let (content, usage) = try parseContent(data)
        guard let analysis = try? CallAnalysis.decode(from: content) else {
            throw OpenAICompatibleError.invalidResponse
        }
        return AnalysisOutcome(analysis: analysis, usage: usage)
    }

    /// The text of the first choice, with the usage of the request.
    static func parseContent(_ data: Data) throws -> (String, TokenUsage?) {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw OpenAICompatibleError.invalidResponse
        }
        guard case .array(let choices)? = root["choices"], let first = choices.first else {
            throw OpenAICompatibleError.noResult
        }
        if first["finish_reason"]?.stringValue == "length" { throw OpenAICompatibleError.truncated }
        guard let content = first["message"]?["content"]?.stringValue else {
            throw OpenAICompatibleError.noResult
        }
        return (content, usage(root["usage"]))
    }

    private static func usage(_ value: JSONValue?) -> TokenUsage? {
        guard let value, let prompt = value["prompt_tokens"]?.intValue, let completion = value["completion_tokens"]?.intValue else {
            return nil
        }
        let cached = value["prompt_tokens_details"]?["cached_tokens"]?.intValue ?? 0
        let reasoning = value["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
        let total = value["total_tokens"]?.intValue ?? (prompt + completion)
        return TokenUsage(input: prompt, cachedInput: cached, output: completion, reasoning: reasoning, total: total)
    }

    private func perform(path: String, body: Data?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw OpenAICompatibleError.invalidResponse }
        var request = URLRequest(url: url.absoluteURL, timeoutInterval: Self.requestTimeout)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as OpenAICompatibleError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw OpenAICompatibleError.network(error.localizedDescription)
        }

        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw OpenAICompatibleError.invalidKey
        default: throw OpenAICompatibleError.http(status: response.statusCode, message: Self.errorMessage(in: data))
        }
    }

    private static func errorMessage(in data: Data) -> String {
        let text = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.stringValue
        return String((text ?? "no details").prefix(300))
    }
}
