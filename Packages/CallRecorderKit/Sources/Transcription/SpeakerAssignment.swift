import Foundation

/// A stretch of speech the diarizer attributed to one voice.
public struct SpeakerTurn: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let speakerID: String

    public init(start: Double, end: Double, speakerID: String) {
        self.start = start
        self.end = end
        self.speakerID = speakerID
    }
}

/// Recognised text with its time span, before a speaker is known.
public struct TimedText: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SpeakerAssignment {
    /// Gives every recognised phrase the voice that speaks most during it. Voices are named "Собеседник 1, 2, …"
    /// in order of first appearance, so the names do not depend on the diarizer's internal ids.
    /// A phrase that falls in a gap between turns takes the nearest turn; with no turns at all everything is
    /// spoken by "Собеседник 1".
    public static func label(_ texts: [TimedText], turns: [SpeakerTurn], namePrefix: String = "Собеседник") -> [Utterance] {
        labelling(texts, turns: turns, namePrefix: namePrefix).utterances
    }

    /// `label`, plus which label each diarizer id got, so per-voice data (voiceprints) can follow the label.
    public static func labelling(
        _ texts: [TimedText], turns: [SpeakerTurn], namePrefix: String = "Собеседник"
    ) -> (utterances: [Utterance], labels: [String: String]) {
        var names: [String: String] = [:]

        func name(for speakerID: String) -> String {
            if let known = names[speakerID] { return known }
            let created = "\(namePrefix) \(names.count + 1)"
            names[speakerID] = created
            return created
        }

        let utterances = texts
            .sorted { $0.start < $1.start }
            .map { text in
                let speakerID = dominantSpeaker(for: text, in: turns) ?? "unknown"
                return Utterance(start: text.start, end: text.end, speaker: name(for: speakerID), text: text.text)
            }
        return (utterances, names)
    }

    private static func dominantSpeaker(for text: TimedText, in turns: [SpeakerTurn]) -> String? {
        guard !turns.isEmpty else { return nil }

        var overlapBySpeaker: [String: Double] = [:]
        for turn in turns {
            let overlap = min(text.end, turn.end) - max(text.start, turn.start)
            if overlap > 0 { overlapBySpeaker[turn.speakerID, default: 0] += overlap }
        }
        if let best = overlapBySpeaker.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) {
            return best.key
        }
        return turns.min { distance(from: text, to: $0) < distance(from: text, to: $1) }?.speakerID
    }

    private static func distance(from text: TimedText, to turn: SpeakerTurn) -> Double {
        max(turn.start - text.end, text.start - turn.end, 0)
    }
}
