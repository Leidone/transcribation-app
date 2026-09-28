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

struct AnthropicClientTests {
    private static let goodReply = """
    {
      "stop_reason": "tool_use",
      "content": [
        {"type": "text", "text": "ok"},
        {"type": "tool_use", "id": "t1", "name": "submit_analysis", "input": {
          "summary": "Обсудили релиз.",
          "decisions": ["Релиз в пятницу"],
          "tasks": [{"title": "Подготовить релиз", "owner": "Аня", "due": null, "quote": null, "timestampSeconds": 12.5}]
        }}
      ],
      "usage": {"input_tokens": 120, "cache_read_input_tokens": 30, "output_tokens": 80}
    }
    """

    private func client(_ transport: StubTransport, key: String = "  sk-ant-test  ") -> AnthropicClient {
        AnthropicClient(apiKey: key, transport: transport)
    }

    @Test("the request goes to the Messages API with the key, the version and a forced tool")
    func requestShape() async throws {
        let transport = StubTransport(body: Self.goodReply)

        _ = try await client(transport).analyze(transcript: "0:05 Аня: привет", prompt: .standard)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == AnthropicClient.apiVersion)

        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(request.httpBody))
        #expect(body["model"]?.stringValue == AnthropicClient.defaultModel)
        #expect(body["system"]?.stringValue == AnalysisPrompt.standard.instructions + AnthropicClient.systemSuffix)
        #expect(body["tool_choice"]?["name"]?.stringValue == "submit_analysis")
        #expect(body["messages"] == .array([.object(["role": .string("user"), "content": .string("0:05 Аня: привет")])]))
        #expect(body["tools"] != nil)
    }

    @Test("a chosen model replaces the default; an empty one does not")
    func modelChoice() throws {
        var prompt = AnalysisPrompt.standard
        prompt.model = "claude-sonnet-5"
        let chosen = try JSONDecoder().decode(JSONValue.self, from: AnthropicClient.requestBody(transcript: "x", prompt: prompt))
        prompt.model = ""
        let empty = try JSONDecoder().decode(JSONValue.self, from: AnthropicClient.requestBody(transcript: "x", prompt: prompt))

        #expect(chosen["model"]?.stringValue == "claude-sonnet-5")
        #expect(empty["model"]?.stringValue == AnthropicClient.defaultModel)
    }

    @Test("the tool input becomes the analysis and the usage is counted")
    func parsesResult() async throws {
        let outcome = try await client(StubTransport(body: Self.goodReply)).analyze(transcript: "x", prompt: .standard)

        #expect(outcome.analysis.summary == "Обсудили релиз.")
        #expect(outcome.analysis.decisions == ["Релиз в пятницу"])
        #expect(outcome.analysis.tasks.first?.owner == "Аня")
        #expect(outcome.analysis.tasks.first?.due == nil)
        #expect(outcome.usage == TokenUsage(input: 150, cachedInput: 30, output: 80, reasoning: 0, total: 230))
    }

    @Test("a rejected key is reported as such")
    func invalidKey() async {
        let transport = StubTransport(status: 401, body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)

        await #expect(throws: AnthropicError.invalidKey) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("other failures carry the status and Anthropic's own message")
    func httpFailure() async {
        let transport = StubTransport(status: 429, body: #"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#)

        await #expect(throws: AnthropicError.http(status: 429, message: "slow down")) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("an error page that is not JSON still gives a readable failure")
    func htmlFailure() async {
        await #expect(throws: AnthropicError.http(status: 502, message: "no details")) {
            _ = try await client(StubTransport(status: 502, body: "<html>bad gateway</html>"))
                .analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("a network failure is wrapped")
    func networkFailure() async {
        let transport = StubTransport(failing: URLError(.notConnectedToInternet))

        await #expect(throws: AnthropicError.self) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("an answer cut off by the token limit is not treated as an analysis")
    func truncated() async {
        let transport = StubTransport(body: #"{"stop_reason":"max_tokens","content":[{"type":"tool_use","name":"submit_analysis","input":{}}]}"#)

        await #expect(throws: AnthropicError.truncated) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("a reply without the tool call has no result")
    func noToolCall() async {
        let transport = StubTransport(body: #"{"stop_reason":"end_turn","content":[{"type":"text","text":"Sure!"}]}"#)

        await #expect(throws: AnthropicError.noResult) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("a tool input that does not match the schema is refused")
    func wrongShape() async {
        let transport = StubTransport(body: #"{"content":[{"type":"tool_use","name":"submit_analysis","input":{"summary":1}}]}"#)

        await #expect(throws: AnthropicError.invalidResponse) {
            _ = try await client(transport).analyze(transcript: "x", prompt: .standard)
        }
    }

    @Test("the model list keeps ids and display names and marks the default")
    func modelList() async throws {
        let body = """
        {"data":[
          {"id":"claude-sonnet-5","display_name":"Claude Sonnet 5","type":"model"},
          {"id":"\(AnthropicClient.defaultModel)","display_name":"Claude Haiku 4.5","type":"model"},
          {"type":"model"}
        ],"has_more":false}
        """
        let transport = StubTransport(body: body)

        let models = try await client(transport).availableModels()

        #expect(models.map(\.id) == ["claude-sonnet-5", AnthropicClient.defaultModel])
        #expect(models.map(\.name) == ["Claude Sonnet 5", "Claude Haiku 4.5"])
        #expect(models.map(\.isDefault) == [false, true])
        #expect(transport.requests.first?.httpMethod == "GET")
        #expect(transport.requests.first?.httpBody == nil)
    }

    @Test("settings saved before Claude was supported still load")
    func oldSettingsStillDecode() throws {
        let old = Data(#"{"kind":"custom","customName":"X","customBaseURL":"https://a.b/v1"}"#.utf8)

        let settings = try JSONDecoder().decode(ProviderSettings.self, from: old)

        #expect(settings.kind == .custom)
        #expect(settings.claudeModel == nil)
    }

    @Test("Claude needs no Codex config")
    func noThreadConfig() {
        #expect(ProviderSettings(kind: .anthropic, customName: "", customBaseURL: "").threadConfig() == nil)
    }
}
