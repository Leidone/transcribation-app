import Foundation

/// One spoken turn with its speaker label; times are seconds on the app-stream clock.
public struct Utterance: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let speaker: String
    public let text: String

    public init(start: Double, end: Double, speaker: String, text: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
        self.text = text
    }

    /// `[mm:ss] Speaker: text`, the input format the analysis prompt expects.
    public var transcriptLine: String {
        let totalSeconds = max(0, Int(start))
        let stamp = String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
        return "[\(stamp)] \(speaker): \(text)"
    }
}

public enum TranscriptMerge {
    /// Interleaves the user's microphone turns with the other participants' turns by start time.
    ///
    /// `micOffsetSeconds` is `RecordingSession.syncOffsetSeconds`: the microphone stream starts that much
    /// later than the app stream, so its timestamps are shifted onto the app clock. Overlapping speech is
    /// kept as separate turns; ties keep the microphone turn first.
    public static func merge(me: [Utterance], others: [Utterance], micOffsetSeconds: Double = 0) -> [Utterance] {
        let shifted = me.map {
            Utterance(start: $0.start + micOffsetSeconds, end: $0.end + micOffsetSeconds, speaker: $0.speaker, text: $0.text)
        }
        return (shifted + others).enumerated()
            .sorted { lhs, rhs in
                if lhs.element.start != rhs.element.start { return lhs.element.start < rhs.element.start }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public static func transcript(of utterances: [Utterance]) -> String {
        utterances.map(\.transcriptLine).joined(separator: "\n")
    }
}
