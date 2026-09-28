import Foundation
import Localization

/// Recurring meetings: recordings of calendar events with the same title (a daily stand-up, a weekly sync).
/// Recordings without an event are never a series, or every "Recording — Zoom" would be one.
public enum MeetingSeries {
    /// The series a recording belongs to, oldest first; empty when it has no calendar event or is alone.
    public static func members(of recording: RecordingItem, in recordings: [RecordingItem]) -> [RecordingItem] {
        guard let seriesKey = key(of: recording) else { return [] }
        let series = recordings.filter { key(of: $0) == seriesKey && !$0.isSample }.sorted { $0.startedAt < $1.startedAt }
        return series.count > 1 ? series : []
    }

    /// The latest meeting of the series before this one.
    public static func previous(of recording: RecordingItem, in recordings: [RecordingItem]) -> RecordingItem? {
        members(of: recording, in: recordings).last { $0.startedAt < recording.startedAt }
    }

    /// What the AI is told about the previous meeting when it summarises this one: the tasks it left open, so the
    /// summary can say what became of them. `nil` when nothing was left open.
    public static func followUpNote(from previous: RecordingItem) -> String? {
        guard let analysis = previous.analysis else { return nil }
        let open = analysis.tasks.filter { !$0.isDone }
        guard !open.isEmpty else { return nil }
        let date = previous.startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let lines = open.map { "- " + RecordingExport.describe($0, displayName: previous.displayName) }
        return tr("Незакрытые задачи с прошлой встречи этой серии (\(date)):", "Tasks the previous meeting of this series left open (\(date)):")
            + "\n" + lines.joined(separator: "\n")
    }

    private static func key(of recording: RecordingItem) -> String? {
        guard let title = recording.meeting?.title else { return nil }
        let key = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? nil : key
    }
}
