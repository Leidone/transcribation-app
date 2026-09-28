import Foundation

/// What Spotlight knows about one recording: enough to find it by a word from the call, never the audio. The index
/// is kept by macOS on this device only.
public struct SpotlightEntry: Equatable, Hashable, Sendable {
    public static let domain = "recordings"

    /// The recording's id, so a hit opens it.
    public let id: String
    public let title: String
    /// Shown under the title in the results: the summary, or the start of the transcript.
    public let summary: String
    /// Searched but not shown: decisions, tasks and the transcript.
    public let text: String
    public let date: Date
    public let duration: TimeInterval
    /// Named voices and invited people.
    public let people: [String]

    /// Spotlight gains nothing from a transcript longer than this; the start of a call names its topics.
    static let textLimit = 60_000

    public init(recording: RecordingItem) {
        id = recording.id.uuidString
        title = recording.title
        date = recording.startedAt
        duration = recording.duration

        let spoken = recording.transcript.map { "\(recording.displayName($0.speaker)): \($0.text)" }
        if let analysis = recording.analysis {
            summary = analysis.summary
        } else {
            summary = String(spoken.prefix(3).joined(separator: " ").prefix(300))
        }
        var parts: [String] = []
        if let analysis = recording.analysis {
            parts += analysis.decisions
            parts += analysis.tasks.map(\.title)
        }
        parts += spoken
        text = String(parts.joined(separator: "\n").prefix(Self.textLimit))

        var names = Array(recording.speakerNames.names.values)
        names += recording.meeting?.attendees ?? []
        people = Array(Set(names)).sorted()
    }

    /// The recordings Spotlight should know: the person's own ones that have something to find.
    public static func entries(for recordings: [RecordingItem]) -> [SpotlightEntry] {
        recordings
            .filter { !$0.isSample && (!$0.transcript.isEmpty || $0.analysis != nil) }
            .map(SpotlightEntry.init(recording:))
    }
}
