import Foundation

public struct CompactLine: Equatable, Sendable {
    public let time: Double
    public let speaker: String
    public let text: String

    public init(time: Double, speaker: String, text: String) {
        self.time = time
        self.speaker = speaker
        self.text = text
    }
}

/// The transcript in the fewest tokens that keep who said what and when.
public enum CompactTranscript {
    /// One line per turn, `m:ss Name: text`. Neighbouring lines of the same speaker within `mergeGap` seconds become
    /// one turn (no repeated name and timestamp), whitespace is collapsed and empty lines are dropped.
    public static func make(_ lines: [CompactLine], mergeGap: Double = 6) -> String {
        var turns: [(time: Double, speaker: String, text: String, lastStart: Double)] = []
        for line in lines {
            let text = line.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { continue }

            if let last = turns.last, last.speaker == line.speaker, line.time - last.lastStart <= mergeGap {
                turns[turns.count - 1] = (last.time, last.speaker, last.text + " " + text, line.time)
            } else {
                turns.append((line.time, line.speaker, text, line.time))
            }
        }
        return turns.map { "\(clock($0.time)) \($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    /// `m:ss`; minutes keep growing past 59 (a long call reads "65:03").
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A rough token count, enough to show the size of a prompt or transcript; the real figure comes from the model.
public enum TokenEstimate {
    public static func of(_ text: String) -> Int {
        var tokens = 0.0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF: tokens += 0.42 // Cyrillic splits into more, shorter tokens
            case 0x30...0x39: tokens += 0.4
            case 0x41...0x5A, 0x61...0x7A: tokens += 0.27
            default: tokens += scalar.properties.isWhitespace ? 0.05 : 0.3
            }
        }
        return Int(tokens.rounded(.up))
    }
}
