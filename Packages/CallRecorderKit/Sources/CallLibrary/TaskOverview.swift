import Foundation
import Transcription

/// The tasks of one meeting, as listed in the overview of all tasks.
public struct TaskGroup: Identifiable, Equatable, Sendable {
    public let recording: RecordingItem
    public let tasks: [TaskItem]

    public var id: RecordingItem.ID { recording.id }
}

/// Every task from every meeting in one place: what is still open, grouped by the meeting it was agreed in.
public enum TaskOverview {
    public enum Filter: Equatable, Sendable {
        case open
        case all
    }

    /// Meetings newest first, each with its tasks in the order they were agreed. Meetings with nothing to show are
    /// left out. `mineOnly` keeps the tasks whose owner is the person themselves: the microphone's voice, or a name
    /// they gave to it.
    public static func groups(in recordings: [RecordingItem], filter: Filter, mineOnly: Bool = false) -> [TaskGroup] {
        recordings
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { recording in
                let tasks = (recording.analysis?.tasks ?? []).filter { task in
                    (filter == .all || !task.isDone) && (!mineOnly || isMine(task, in: recording))
                }
                return tasks.isEmpty ? nil : TaskGroup(recording: recording, tasks: tasks)
            }
    }

    /// Open tasks across the library, for the badge in the sidebar.
    public static func openCount(in recordings: [RecordingItem]) -> Int {
        recordings.reduce(0) { count, recording in
            count + (recording.analysis?.tasks.filter { !$0.isDone }.count ?? 0)
        }
    }

    /// The owner is the person recording: "Я" as the transcript names the microphone, or the name they gave it.
    static func isMine(_ task: TaskItem, in recording: RecordingItem) -> Bool {
        guard let owner = task.owner?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        let me = TranscriptionPipeline.myName
        let names = [me, recording.displayName(me), "me", "я"].map { $0.lowercased() }
        return names.contains(owner)
    }
}
