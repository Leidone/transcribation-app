import Foundation
import Testing
@testable import CodexClient

/// Answers every request with a canned response and remembers what was sent.
private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [URLRequest] = []
    private let reply: @Sendable (URLRequest) throws -> (Int, String)

    init(status: Int = 200, body: String) {
        reply = { _ in (status, body) }
    }

    init(failing error: any Error) {
        reply = { _ in throw error }
    }

    var requests: [URLRequest] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { sent.append(request) }
        let (status, body) = try reply(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

struct OpenAICompatibleClientTests {
    private static let analysisJSON = """
    {"summary":"Обсудили релиз.","decisions":["Релиз в пятницу"],"tasks":[{"title":"Подготовить релиз","owner":"Аня","due":null,"quote":null,"timestampSeconds":12.5}]}
    """

    private static var goodReply: String {
        """
        {
          "choices": [{"finish_reason": "stop", "message": {"role": "assistant", "content": \(escaped(analysisJSON))}}],
          "usage": {"prompt_tokens": 120, "completion_tokens": 80, "total_tokens": 200, "prompt_tokens_details": {"cached_tokens": 30}}
        }
        """
    }

    private static func escaped(_ text: String) -> String {
        let data = try! JSONEncoder().encode(text)
        return String(decoding: data, as: UTF8.self)
    }

    private func client(_ transport: StubTransport, baseURL: URL = OpenAICompatibleClient.defaultBaseURL, key: String = "  sk-test  ") -> OpenAICompatibleClient {
        OpenAICompatibleClient(apiKey: key, baseURL: baseURL, transport: transport)
    }

    @Test("the request goes to chat/completions with the key and a forced json schema, and 'v1' survives joining")
    func requestShape() async throws {
        let transport = StubTransport(body: Self.goodReply)

        _ = try await client(transport).analyze(transcript: "0:05 Аня: привет", prompt: .standard)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(request.httpBody))
        #expect(body["model"]?.stringValue == OpenAICompatibleClient.defaultModel)
        #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
        #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == true)
        #expect(body["messages"]?.arrayValue?.first?["role"]?.stringValue == "system")
        #expect(body["messages"]?.arrayValue?.first?["content"]?.stringValue == AnalysisPrompt.standard.instructions)
        #expect(body["messages"]?.arrayValue?.last?["content"]?.stringValue == "0:05 Аня: привет")
    }

    @Test("a base URL without a trailing slash still keeps its path when joined with a request path")
    func baseURLWithoutTrailingSlash() async throws {
        let transport = StubTransport(body: Self.goodReply)
        let base = URL(string: "https://openrouter.ai/api/v1")!

        _ = try await client(transport, baseURL: base).analyze(transcript: "x", prompt: .standard)

        #expect(transport.requests.first?.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
    }

    @Test("a chosen model replaces the default; an empty one does not")
    func modelChoice() throws {
        var prompt = AnalysisPrompt.standard
        prompt.model = "gpt-5"
        let chosen = try JSONDecoder().decode(JSONValue.self, from: OpenAICompatibleClient.requestBody(transcript: "x", prompt: prompt))
        prompt.model = ""
        let empty = try JSONDecoder().decode(JSONValue.self, from: OpenAICompatibleClient.requestBody(transcript: "x", prompt: prompt))

        #expect(chosen["model"]?.stringValue == "gpt-5")
        #expect(empty["model"]?.stringValue == OpenAICompatibleClient.defaultModel)
    }

    @Test("the message content becomes the analysis and usage is counted, including cached input tokens")
    func parsesResult() async throws {
        let outcome = try await client(StubTransport(body: Self.goodReply)).analyze(transcript: "x", prompt: .standard)

        #expect(outcome.analysis.summary == "Обсудили релиз.")
        #expect(outcome.analysis.tasks.first?.owner == "Аня")
        #expect(outcome.usage == TokenUsage(input: 120, cachedInput: 30, output: 80, reasoning: 0, total: 200))
    }

    @Test("a rejected key is reported as such")
    func invalidKey() async {
        let transport = StubTransport(status: 401, body: #"{"error":{"message":"invalid api key"}}"#)

        await #expect(throws: OpenAICompatibleError.invalidKey) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("other failures carry the status and the server's own message")
    func httpFailure() async {
        let transport = StubTransport(status: 429, body: #"{"error":{"message":"slow down"}}"#)

        await #expect(throws: OpenAICompatibleError.http(status: 429, message: "slow down")) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("a reply truncated by the token limit is reported, not parsed as an analysis")
    func truncated() async {
        let transport = StubTransport(body: #"{"choices":[{"finish_reason":"length","message":{"content":"{\"sum"}}]}"#)

        await #expect(throws: OpenAICompatibleError.truncated) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("no choices in the reply means no result")
    func noChoices() async {
        let transport = StubTransport(body: #"{"choices":[]}"#)

        await #expect(throws: OpenAICompatibleError.noResult) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("content that is not valid CallAnalysis JSON is refused, not guessed at")
    func wrongShape() async {
        let transport = StubTransport(body: #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"summary\":1}"}}]}"#)

        await #expect(throws: OpenAICompatibleError.invalidResponse) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("the model list is read from /models")
    func modelList() async throws {
        let transport = StubTransport(body: #"{"data":[{"id":"gpt-5"},{"id":"gpt-5-mini"}]}"#)

        let models = try await client(transport).availableModels()

        #expect(models.map(\.id) == ["gpt-5", "gpt-5-mini"])
        #expect(models.map(\.isDefault) == [false, true])
        #expect(transport.requests.first?.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(transport.requests.first?.httpMethod == "GET")
    }
}
