import Foundation

/// How much of a meeting one person spoke.
public struct TalkShare: Equatable, Sendable {
    /// The name shown for the voice (the one the person gave, or the label).
    public let name: String
    public let isMe: Bool
    public let seconds: TimeInterval
    /// Part of all the speech, 0…1.
    public let share: Double
}

/// Who spoke how much. Voices given the same name are one person, so this is also where two labels of one speaker
/// come together.
public enum TalkTime {
    /// A phrase without a known end lasts until the next one, but not longer than this (pauses are not speech).
    static let longestEstimatedPhrase: TimeInterval = 30

    /// The most talkative first; empty for a recording without a transcript.
    public static func shares(of recording: RecordingItem) -> [TalkShare] {
        let lines = recording.transcript.sorted { $0.time < $1.time }
        var seconds: [String: TimeInterval] = [:]
        var mine: Set<String> = []
        var order: [String] = []
        for (index, line) in lines.enumerated() {
            let name = recording.displayName(line.speaker)
            if seconds[name] == nil { order.append(name) }
            seconds[name, default: 0] += length(of: line, next: index + 1 < lines.count ? lines[index + 1] : nil,
                                                recordingEnd: recording.duration)
            if line.isMe { mine.insert(name) }
        }
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return [] }
        return order
            .map { TalkShare(name: $0, isMe: mine.contains($0), seconds: seconds[$0] ?? 0, share: (seconds[$0] ?? 0) / total) }
            .sorted { $0.seconds > $1.seconds }
    }

    private static func length(of line: TranscriptLine, next: TranscriptLine?, recordingEnd: TimeInterval) -> TimeInterval {
        if let end = line.end { return max(0, end - line.time) }
        let until = next?.time ?? recordingEnd
        return min(max(0, until - line.time), longestEstimatedPhrase)
    }
}
