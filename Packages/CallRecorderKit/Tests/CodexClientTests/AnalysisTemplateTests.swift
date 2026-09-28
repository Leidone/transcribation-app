import Testing
@testable import CodexClient

@Test func theGeneralTemplateLeavesThePromptAsItIs() {
    #expect(AnalysisTemplate.general.applied(to: .standard) == .standard)
}

@Test(arguments: AnalysisTemplate.allCases.filter { $0 != .general })
func otherTemplatesAppendTheirFocusAfterThePersonsInstructions(template: AnalysisTemplate) throws {
    let focus = try #require(template.focus)
    let adapted = template.applied(to: .standard)

    #expect(adapted.instructions.hasPrefix(AnalysisPrompt.standard.instructions.trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(adapted.instructions.hasSuffix(focus))
    #expect(adapted.effort == AnalysisPrompt.standard.effort)
    #expect(adapted.model == AnalysisPrompt.standard.model)
    #expect(adapted.replacesAgentPrompt == AnalysisPrompt.standard.replacesAgentPrompt)
}

@Test func templatesKeepAStableStoredName() {
    #expect(AnalysisTemplate.allCases.map(\.rawValue) == ["general", "standup", "interview", "sales", "one-on-one"])
}
