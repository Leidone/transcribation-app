import Foundation
import Testing
@testable import CodexClient

struct AnalysisPromptTests {
    @Test("the default prompt replaces Codex's agent prompt and thinks little")
    func standardIsFrugal() {
        #expect(AnalysisPrompt.standard.replacesAgentPrompt)
        #expect(AnalysisPrompt.standard.effort == .low)
        #expect(AnalysisPrompt.standard.model == nil)
    }

    @Test("the compact instructions are much shorter than the first version")
    func compactIsShort() {
        let compact = TokenEstimate.of(AnalysisPrompt.standard.instructions)
        let legacy = TokenEstimate.of(AnalysisPrompt.legacy.instructions)

        #expect(compact < legacy)
        #expect(compact < 200)
    }

    @Test("the instructions still treat the transcript as untrusted and forbid tools")
    func keepsSafetyRules() {
        let text = AnalysisPrompt.standard.instructions.lowercased()

        #expect(text.contains("untrusted"))
        #expect(text.contains("no tools"))
        #expect(text.contains("never invent"))
    }

    @Test("a prompt survives being stored and loaded")
    func codable() throws {
        var prompt = AnalysisPrompt.standard
        prompt.model = "gpt-5-mini"
        prompt.effort = .minimal

        let decoded = try JSONDecoder().decode(AnalysisPrompt.self, from: JSONEncoder().encode(prompt))

        #expect(decoded == prompt)
    }
}
