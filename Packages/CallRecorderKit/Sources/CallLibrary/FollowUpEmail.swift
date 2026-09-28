import Foundation
import Localization

/// A letter to the people of a meeting with what was agreed: the summary, the decisions and the open tasks with
/// who does them by when. It is written from the stored result, on this Mac, without asking the AI again; the
/// person reads it in Mail and sends it themselves.
public struct FollowUpEmail: Equatable, Sendable {
    public let subject: String
    public let body: String
    /// The invited people's addresses from the calendar; empty when the recording has no meeting.
    public let recipients: [String]

    /// `nil` for a recording without a summary: there is nothing to tell anyone yet.
    public static func draft(for recording: RecordingItem) -> FollowUpEmail? {
        guard let analysis = recording.analysis else { return nil }
        var parts = [
            tr("Коллеги, привет!", "Hi all,"),
            tr("Коротко по итогам встречи «\(recording.title)»:", "Here is a short recap of “\(recording.title)”:"),
            analysis.summary,
        ]
        if !analysis.decisions.isEmpty {
            parts.append(tr("Решили:", "Decided:") + "\n" + analysis.decisions.map { "- \($0)" }.joined(separator: "\n"))
        }
        let open = analysis.tasks.filter { !$0.isDone }
        if !open.isEmpty {
            let lines = open.map { line(for: $0, displayName: recording.displayName) }
            parts.append(tr("Кто что делает:", "Next steps:") + "\n" + lines.joined(separator: "\n"))
        }
        parts.append(tr("Если что-то упустил — поправьте, пожалуйста.", "If I missed anything, please let me know."))
        return FollowUpEmail(
            subject: tr("Итоги встречи: \(recording.title)", "Meeting notes: \(recording.title)"),
            body: parts.joined(separator: "\n\n") + "\n",
            recipients: recording.meeting?.emails ?? []
        )
    }

    /// "- Анна: подготовить changelog (до четверга)", with whatever of owner and deadline is known.
    private static func line(for task: TaskItem, displayName: (String) -> String) -> String {
        let owner = task.owner.map { displayName($0) + ": " } ?? ""
        let due = task.due.map { " (\($0))" } ?? ""
        return "- " + owner + task.title + due
    }
}
