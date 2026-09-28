import Foundation
import Testing
@testable import CodexClient

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [URLRequest] = []
    private let body: String

    init(body: String) {
        self.body = body
    }

    var requests: [URLRequest] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { sent.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private let question = MeetingQuestion(
    question: "  Что решили про бюджет?  ", meetings: "### M1 · Финансы · 2026-09-20 · 10:00\n0:05 Борис: Бюджет утвердили.",
    earlier: [.init(question: "Кто был?", answer: "Борис.")]
)

@Test func theQuestionComesLastAfterEarlierTurnsAndTheMeetings() {
    let input = question.input
    #expect(input.hasPrefix("Earlier in this conversation:\nQ: Кто был?\nA: Борис."))
    #expect(input.contains("Meetings:\n\n### M1 · Финансы"))
    #expect(input.hasSuffix("Question: Что решили про бюджет?"))
}

@Test func theQuestionPromptKeepsTheSafetyRules() {
    #expect(MeetingQuestion.instructions.contains("untrusted"))
    #expect(MeetingQuestion.instructions.contains("use no tools"))
    #expect(MeetingQuestion.instructions.contains("language of the question"))
}

@Test func claudeAnswersThroughItsOwnTool() async throws {
    let transport = StubTransport(body: """
    {"stop_reason":"tool_use","content":[{"type":"tool_use","name":"submit_answer","input":{
      "answer":"Бюджет утвердили.","sources":[{"meeting":"M1","timestampSeconds":5,"quote":"Бюджет утвердили"}]
    }}],"usage":{"input_tokens":50,"output_tokens":10}}
    """)
    let outcome = try await AnthropicClient(apiKey: "k", transport: transport).answer(question, model: nil)
    #expect(outcome.answer.answer == "Бюджет утвердили.")
    #expect(outcome.answer.sources.first?.timestampSeconds == 5)

    let body = try JSONDecoder().decode(JSONValue.self, from: try #require(transport.requests.first?.httpBody))
    #expect(body["tool_choice"]?["name"]?.stringValue == "submit_answer")
    #expect(body["system"]?.stringValue?.hasPrefix(MeetingQuestion.instructions) == true)
    #expect(body["messages"]?.arrayValue?.first?["content"]?.stringValue == question.input)
}

@Test func anOpenAICompatibleServerAnswersWithTheAnswerSchema() async throws {
    let content = #"{\"answer\":\"Не обсуждали.\",\"sources\":[]}"#
    let transport = StubTransport(body: """
    {"choices":[{"finish_reason":"stop","message":{"content":"\(content)"}}],"usage":{"prompt_tokens":5,"completion_tokens":2}}
    """)
    let outcome = try await OpenAICompatibleClient(apiKey: "k", transport: transport).answer(question, model: "gpt-x")
    #expect(outcome.answer.answer == "Не обсуждали.")
    #expect(outcome.answer.sources.isEmpty)

    let body = try JSONDecoder().decode(JSONValue.self, from: try #require(transport.requests.first?.httpBody))
    #expect(body["model"]?.stringValue == "gpt-x")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "meeting_answer")
}

@Test func anAnswerOfTheWrongShapeIsRefused() {
    #expect(throws: CodexError.self) { try MeetingAnswer.decode(from: #"{"answer": 1}"#) }
}
