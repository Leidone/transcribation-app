import Foundation
import Localization

/// The latest meeting that has a summary, as Siri reads it out and as a shortcut receives it.
public enum LastMeetingSummary {
    public struct Text: Equatable, Sendable {
        /// Short enough to be read out: the title and the summary.
        public let spoken: String
        /// Markdown with the decisions and tasks, for a shortcut to send on.
        public let full: String
    }

    /// The person's latest meeting that has a summary; samples do not count.
    public static func latest(in recordings: [RecordingItem]) -> RecordingItem? {
        recordings
            .filter { !$0.isSample && $0.analysis != nil }
            .max { $0.startedAt < $1.startedAt }
    }

    public static func text(from recordings: [RecordingItem]) -> Text? {
        guard let recording = latest(in: recordings), let analysis = recording.analysis else { return nil }
        let openTasks = analysis.tasks.filter { !$0.isDone }.count
        var spoken = "\(recording.title). \(analysis.summary)"
        if openTasks > 0 {
            spoken += " " + tr("Открытых задач: \(openTasks).", "Open tasks: \(openTasks).")
        }
        let full = "# \(recording.title)\n\n" + RecordingExport.summaryMarkdown(of: analysis, displayName: recording.displayName)
        return Text(spoken: spoken, full: full)
    }
}
