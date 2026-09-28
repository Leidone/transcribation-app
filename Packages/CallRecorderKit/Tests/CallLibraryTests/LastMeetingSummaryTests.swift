import Foundation
import Testing
@testable import CallLibrary

private func meeting(_ title: String, hoursAgo: Double, summary: String?, sample: Bool = false) -> RecordingItem {
    RecordingItem(
        id: UUID(), title: title, appName: "Zoom", appBundleID: nil,
        startedAt: Date(timeIntervalSince1970: 1_790_000_000 - hoursAgo * 3_600), duration: 60,
        status: summary == nil ? .transcribed : .ready, directory: nil, isSample: sample, transcript: [],
        analysis: summary.map {
            AnalysisResult(summary: $0, decisions: ["Релиз в пятницу"], tasks: [
                TaskItem(id: UUID(), title: "Проверить тесты", owner: "Борис", due: nil, quote: nil, timestamp: nil, isDone: false),
            ])
        }
    )
}

@Test func theLatestSummarisedMeetingIsReadOut() throws {
    let recordings = [
        meeting("Вчера", hoursAgo: 24, summary: "Старое."),
        meeting("Сейчас", hoursAgo: 1, summary: nil),
        meeting("Утром", hoursAgo: 5, summary: "Договорились о релизе."),
        meeting("Пример", hoursAgo: 0, summary: "Образец.", sample: true),
    ]
    let text = try #require(LastMeetingSummary.text(from: recordings))
    #expect(text.spoken == "Утром. Договорились о релизе. Открытых задач: 1.")
    #expect(text.full.hasPrefix("# Утром\n\n## Итоги"))
    #expect(text.full.contains("- [ ] Проверить тесты — Борис"))
}

@Test func withoutSummariesThereIsNothingToRead() {
    #expect(LastMeetingSummary.text(from: [meeting("Сейчас", hoursAgo: 1, summary: nil)]) == nil)
}
