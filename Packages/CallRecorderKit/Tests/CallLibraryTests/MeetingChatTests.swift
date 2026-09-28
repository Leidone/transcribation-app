import AudioCapture
import CodexClient
import Foundation
import Testing
@testable import CallLibrary

private func recording(
    _ title: String, daysAgo: Double = 0, lines: [String] = [], summary: String? = nil, duration: TimeInterval = 600
) -> RecordingItem {
    RecordingItem(
        id: UUID(), title: title, appName: "Zoom", appBundleID: nil,
        startedAt: Date(timeIntervalSince1970: 1_790_000_000 - daysAgo * 86_400), duration: duration,
        status: summary == nil ? .transcribed : .ready, directory: nil, isSample: false,
        transcript: lines.enumerated().map {
            TranscriptLine(id: $0.offset, time: Double($0.offset * 20), speaker: "Борис", isMe: false, text: $0.element)
        },
        analysis: summary.map { AnalysisResult(summary: $0, decisions: [], tasks: []) }
    )
}

@Test func oneMeetingIsSentWholeUnderM1() {
    let item = recording("Бюджет", lines: ["Бюджет утвердили: два миллиона."], summary: "Утвердили бюджет.")
    let context = MeetingContext.single(item)
    #expect(context.references == ["M1": item.id])
    #expect(context.text.hasPrefix("### M1 · Бюджет · "))
    #expect(context.text.contains("Summary: Утвердили бюджет."))
    #expect(context.text.contains("0:00 Борис: Бюджет утвердили"))
}

@Test func theMeetingAboutTheQuestionComesFirst() {
    let recent = recording("Планёрка", daysAgo: 0, lines: ["Обсудили отпуск."])
    let relevant = recording("Финансы", daysAgo: 5, lines: ["Бюджета на рекламу не хватает, бюджет режем."])
    let context = MeetingContext.library([recent, relevant], question: "Что решили про бюджет?")
    #expect(context.references["M1"] == relevant.id)
    #expect(context.references["M2"] == recent.id)
}

@Test func withoutMatchingWordsTheNewestComesFirst() {
    let older = recording("Старая", daysAgo: 3, lines: ["Привет."])
    let newer = recording("Новая", daysAgo: 1, lines: ["Привет."])
    let context = MeetingContext.library([older, newer], question: "Что было?")
    #expect(context.references["M1"] == newer.id)
}

@Test func whenRoomRunsOutOnlyTheSummaryIsSentAndTheRestIsLeftOut() throws {
    let long = Array(repeating: "Очень длинная реплика про бюджет и планы на квартал.", count: 40)
    let first = recording("Первая", daysAgo: 1, lines: long, summary: "Итоги первой.")
    let second = recording("Вторая", daysAgo: 2, lines: long, summary: "Итоги второй.")
    let third = recording("Третья", daysAgo: 3, lines: long)
    let budget = MeetingContext.block(first, reference: "M1", includesTranscript: true).count + 200

    let context = MeetingContext.library([first, second, third], question: "бюджет", budget: budget)
    #expect(context.references.count == 2)
    let blocks = context.text.components(separatedBy: "\n\n")
    try #require(blocks.count == 2)
    #expect(blocks[0].contains("Transcript:"))
    #expect(blocks[1].hasPrefix("### M2 · Вторая"))
    #expect(blocks[1].contains("Summary: Итоги второй."))
    #expect(!blocks[1].contains("Transcript:"))
    #expect(context.omitted == 1)
}

@Test func recordingsWithNothingToReadAreSkipped() {
    let empty = recording("Пустая")
    let context = MeetingContext.library([empty], question: "что угодно")
    #expect(context.references.isEmpty)
    #expect(context.text.isEmpty)
}

@Test func sourcesPointAtKnownMeetingsInsideTheirLength() {
    let item = recording("Бюджет", lines: ["Бюджет утвердили."], duration: 100)
    let context = MeetingContext.single(item)
    let answer = MeetingAnswer(answer: "Утвердили.", sources: [
        .init(meeting: "m1", timestampSeconds: 20, quote: "Бюджет утвердили"),
        .init(meeting: "M1", timestampSeconds: 20, quote: "повтор"),
        .init(meeting: "M7", timestampSeconds: 5, quote: nil),
        .init(meeting: "M1", timestampSeconds: 900, quote: nil),
    ])
    let sources = context.sources(of: answer, in: [item])
    #expect(sources.map(\.time) == [20, 100])
    #expect(sources.first?.title == "Бюджет")
}

@Test func keywordsAreStemsWithoutCommonWords() {
    #expect(MeetingContext.keywords(of: "Что обещал Борис про бюджета?") == ["обеща", "борис", "бюдже"])
}
