import AudioCapture
import Foundation
import Testing
@testable import CallLibrary

private func recording(marks: [TimeInterval], meeting: MeetingInfo? = nil) -> RecordingItem {
    let lines: [(TimeInterval, String, String)] = [
        (0, "Анна", "Начинаем."),
        (20, "Борис", "Бюджет на квартал — два миллиона."),
        (28, "Я", "Согласен, фиксируем."),
        (60, "Анна", "Следующий вопрос."),
    ]
    return RecordingItem(
        id: UUID(), title: "Планёрка", appName: "Zoom", appBundleID: nil, startedAt: .now, duration: 90,
        status: .transcribed, directory: nil, isSample: false,
        transcript: lines.enumerated().map {
            TranscriptLine(id: $0.offset, time: $0.element.0, speaker: $0.element.1, isMe: $0.element.1 == "Я", text: $0.element.2)
        },
        analysis: nil, meeting: meeting, marks: marks
    )
}

@Test func aMarkPointsAtWhatWasJustSaid() {
    // Pressed at 0:29: the line being said (0:28) and the one that began within ten seconds before (0:20).
    #expect(recording(marks: [29]).lineIDs(markedAt: 29) == [1, 2])
}

@Test func aMarkLongAfterALineStartedStillPointsAtIt() {
    // A long monologue from 1:00: the mark at 1:25 points at it although it began earlier than ten seconds before.
    #expect(recording(marks: [85]).lineIDs(markedAt: 85) == [3])
}

@Test func everyMarkedLineIsHighlighted() {
    #expect(recording(marks: [5, 29]).importantLineIDs == [0, 1, 2])
    #expect(recording(marks: []).importantLineIDs.isEmpty)
}

@Test func aLineCanBeMarkedAndUnmarkedAfterTheCall() {
    let marked = recording(marks: []).togglingMark(on: 3)
    #expect(marked.marks == [60])
    #expect(marked.importantLineIDs.contains(3))
    let unmarked = marked.togglingMark(on: 3)
    #expect(unmarked.marks.isEmpty)
}

@Test func unmarkingALineRemovesEveryMarkPointingAtIt() {
    let item = recording(marks: [22, 29]).togglingMark(on: 1)
    #expect(item.marks.isEmpty)
}

@Test func theAIIsToldWhichMomentsWereMarked() {
    let text = recording(marks: [31, 85]).analysisText
    #expect(text.hasPrefix("Marked important during the call"))
    #expect(text.contains("0:31, 1:25"))
    #expect(text.contains("0:20 Борис: Бюджет на квартал"))
}

@Test func theMeetingComesBeforeTheMarks() {
    let text = recording(marks: [31], meeting: MeetingInfo(title: "Бюджет", attendees: ["Анна"])).analysisText
    let lines = text.split(separator: "\n").map(String.init)
    #expect(lines[0] == "Встреча: Бюджет")
    #expect(lines[1] == "Приглашены: Анна")
    #expect(lines[2].hasPrefix("Marked important"))
}

@Test func withoutMarksOrMeetingOnlyTheTranscriptIsSent() {
    let item = recording(marks: [])
    #expect(item.analysisText == item.transcriptText)
}
