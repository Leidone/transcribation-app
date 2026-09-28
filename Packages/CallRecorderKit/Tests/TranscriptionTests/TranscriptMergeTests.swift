import Foundation
import Testing
@testable import Transcription

struct TranscriptMergeTests {
    private func turn(_ start: Double, _ speaker: String, _ text: String = "…") -> Utterance {
        Utterance(start: start, end: start + 2, speaker: speaker, text: text)
    }

    @Test("interleaves both sides in start order")
    func ordersByStart() {
        // Arrange
        let me = [turn(5, "Я"), turn(20, "Я")]
        let others = [turn(0, "Собеседник 1"), turn(12, "Собеседник 2")]

        // Act
        let merged = TranscriptMerge.merge(me: me, others: others)

        // Assert
        #expect(merged.map(\.start) == [0, 5, 12, 20])
    }

    @Test("shifts microphone turns by the stream offset")
    func appliesMicOffset() {
        let merged = TranscriptMerge.merge(me: [turn(0, "Я")], others: [turn(0.02, "Собеседник 1")], micOffsetSeconds: 0.042)

        #expect(merged.map(\.speaker) == ["Собеседник 1", "Я"])
        #expect(abs(merged[1].start - 0.042) < 1e-9)
    }

    @Test("overlapping speech stays as separate turns and ties keep the microphone first")
    func keepsOverlapAndTieOrder() {
        let merged = TranscriptMerge.merge(me: [turn(10, "Я")], others: [turn(10, "Собеседник 1")])

        #expect(merged.map(\.speaker) == ["Я", "Собеседник 1"])
    }

    @Test("an empty microphone side yields only the other participants")
    func emptyMicrophoneSide() {
        let others = [turn(1, "Собеседник 1"), turn(3, "Собеседник 2")]

        #expect(TranscriptMerge.merge(me: [], others: others) == others)
    }

    @Test("formats a transcript line with minutes and seconds")
    func formatsLine() {
        let line = Utterance(start: 3903, end: 3905, speaker: "Я", text: "Давайте закроем").transcriptLine

        #expect(line == "[65:03] Я: Давайте закроем")
    }

    @Test("does not modify its inputs")
    func leavesInputsUntouched() {
        let me = [turn(5, "Я")]
        let copy = me

        _ = TranscriptMerge.merge(me: me, others: [], micOffsetSeconds: 1)

        #expect(me == copy)
    }
}
