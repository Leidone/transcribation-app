import Foundation
import Testing
@testable import Transcription

struct SpeakerAssignmentTests {
    private func text(_ start: Double, _ end: Double, _ words: String = "…") -> TimedText {
        TimedText(start: start, end: end, text: words)
    }

    @Test("a phrase gets the voice that speaks most during it")
    func dominantOverlapWins() {
        // Arrange
        let turns = [SpeakerTurn(start: 0, end: 4, speakerID: "A"), SpeakerTurn(start: 4, end: 10, speakerID: "B")]

        // Act: 1 s of A against 5 s of B, so the phrase belongs to B, the second voice by appearance order
        let labelled = SpeakerAssignment.label([text(0, 1), text(3, 9)], turns: turns)

        // Assert
        #expect(labelled.map(\.speaker) == ["Собеседник 1", "Собеседник 2"])
    }

    @Test("names follow the order of first appearance, not the diarizer's ids")
    func namesByFirstAppearance() {
        let turns = [SpeakerTurn(start: 0, end: 5, speakerID: "S7"), SpeakerTurn(start: 5, end: 10, speakerID: "S2")]

        let labelled = SpeakerAssignment.label([text(6, 8), text(0, 4), text(1, 3)], turns: turns)

        // Sorted by time: S7, S7, S2
        #expect(labelled.map(\.speaker) == ["Собеседник 1", "Собеседник 1", "Собеседник 2"])
        #expect(labelled.map(\.start) == [0, 1, 6])
    }

    @Test("a phrase in a gap takes the nearest turn")
    func nearestTurnForGaps() {
        let turns = [SpeakerTurn(start: 0, end: 2, speakerID: "A"), SpeakerTurn(start: 10, end: 12, speakerID: "B")]

        let labelled = SpeakerAssignment.label([text(3, 4), text(8, 9)], turns: turns)

        #expect(labelled.map(\.speaker) == ["Собеседник 1", "Собеседник 2"])
    }

    @Test("without turns everything is spoken by the first participant")
    func noTurns() {
        let labelled = SpeakerAssignment.label([text(0, 1), text(2, 3)], turns: [])

        #expect(labelled.map(\.speaker) == ["Собеседник 1", "Собеседник 1"])
    }

    @Test("no phrases give no utterances")
    func emptyInput() {
        #expect(SpeakerAssignment.label([], turns: [SpeakerTurn(start: 0, end: 1, speakerID: "A")]).isEmpty)
    }

    @Test("the text and timing are kept as recognised")
    func keepsTextAndTiming() {
        let labelled = SpeakerAssignment.label(
            [text(1.5, 3.25, "привет")], turns: [SpeakerTurn(start: 0, end: 5, speakerID: "A")]
        )

        #expect(labelled == [Utterance(start: 1.5, end: 3.25, speaker: "Собеседник 1", text: "привет")])
    }
}
