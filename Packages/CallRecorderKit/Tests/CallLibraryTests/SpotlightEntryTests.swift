import AudioCapture
import Foundation
import Testing
@testable import CallLibrary

private func recording(sample: Bool = false, lines: [String] = [], summary: String? = nil) -> RecordingItem {
    RecordingItem(
        id: UUID(), title: "Weekly", appName: "Zoom", appBundleID: nil, startedAt: .now, duration: 60,
        status: summary == nil ? .transcribed : .ready, directory: nil, isSample: sample,
        transcript: lines.enumerated().map {
            TranscriptLine(id: $0.offset, time: Double($0.offset), speaker: "Собеседник 1", isMe: false, text: $0.element)
        },
        analysis: summary.map { AnalysisResult(summary: $0, decisions: ["Релиз в пятницу"], tasks: []) },
        speakerNames: SpeakerNames(names: ["Собеседник 1": "Анна"]),
        meeting: MeetingInfo(title: "Weekly", attendees: ["Борис", "Анна"])
    )
}

@Test func spotlightFindsTheSummaryDecisionsAndWordsFromTheCall() throws {
    let entry = try #require(SpotlightEntry.entries(for: [recording(lines: ["Бюджет утвердили."], summary: "Итоги.")]).first)
    #expect(entry.summary == "Итоги.")
    #expect(entry.text.contains("Релиз в пятницу"))
    #expect(entry.text.contains("Анна: Бюджет утвердили."))
    #expect(entry.people == ["Анна", "Борис"])
}

@Test func withoutASummaryTheStartOfTheCallDescribesIt() throws {
    let entry = try #require(SpotlightEntry.entries(for: [recording(lines: ["Привет.", "Начнём."])]).first)
    #expect(entry.summary == "Анна: Привет. Анна: Начнём.")
}

@Test func samplesAndUntranscribedRecordingsAreNotIndexed() {
    #expect(SpotlightEntry.entries(for: [recording(sample: true, lines: ["x"]), recording()]).isEmpty)
}
