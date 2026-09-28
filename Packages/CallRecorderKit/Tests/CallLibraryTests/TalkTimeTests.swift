import Foundation
import Testing
import AudioCapture
@testable import CallLibrary

struct TalkTimeTests {
    private func recording(_ lines: [TranscriptLine], duration: TimeInterval = 100, names: [String: String] = [:]) -> RecordingItem {
        RecordingItem(
            id: UUID(), title: "Звонок", appName: "Zoom", appBundleID: nil, startedAt: Date(), duration: duration,
            status: .transcribed, directory: nil, isSample: false, transcript: lines, analysis: nil,
            speakerNames: SpeakerNames(names: names)
        )
    }

    @Test("each voice gets the time it spoke and its share, the most talkative first")
    func sharesFromLineEnds() throws {
        // Arrange: me 10 s, the other 30 s
        let lines = [
            TranscriptLine(id: 0, time: 0, speaker: "Я", isMe: true, text: "Привет", end: 10),
            TranscriptLine(id: 1, time: 10, speaker: "Собеседник 1", isMe: false, text: "Здравствуйте", end: 40),
        ]

        // Act
        let shares = TalkTime.shares(of: recording(lines))

        // Assert
        #expect(shares.map(\.name) == ["Собеседник 1", "Я"])
        #expect(shares.map(\.seconds) == [30, 10])
        #expect(abs(shares[0].share - 0.75) < 0.0001)
        #expect(shares[1].isMe)
    }

    @Test("voices given the same name count as one person")
    func sameNameIsOnePerson() {
        let lines = [
            TranscriptLine(id: 0, time: 0, speaker: "Собеседник 1", isMe: false, text: "a", end: 5),
            TranscriptLine(id: 1, time: 5, speaker: "Собеседник 2", isMe: false, text: "b", end: 20),
        ]

        let shares = TalkTime.shares(of: recording(lines, names: ["Собеседник 1": "Анна", "Собеседник 2": "Анна"]))

        #expect(shares.map(\.name) == ["Анна"])
        #expect(shares.map(\.seconds) == [20])
    }

    @Test("without line ends a line lasts until the next one, at most 30 s, and the last one until the end")
    func estimatedWithoutEnds() {
        let lines = [
            TranscriptLine(id: 0, time: 0, speaker: "Анна", isMe: false, text: "a"),
            TranscriptLine(id: 1, time: 10, speaker: "Я", isMe: true, text: "b"),
            TranscriptLine(id: 2, time: 60, speaker: "Анна", isMe: false, text: "c"),
        ]

        let shares = TalkTime.shares(of: recording(lines, duration: 70))

        #expect(shares.map(\.name) == ["Я", "Анна"])
        #expect(shares.map(\.seconds) == [30, 20])
    }

    @Test("an empty transcript has no shares")
    func emptyTranscript() {
        #expect(TalkTime.shares(of: recording([])).isEmpty)
    }
}
