import EventKit
import Foundation
import Localization

/// A task deadline as the model wrote it. Only exact dates (`2026-09-30`, optionally with `T14:00`) become a due
/// date; words like "до среды" stay in the note, because turning them into a date would be a guess.
public enum TaskDueDate {
    public static func components(from due: String?) -> DateComponents? {
        guard let due = due?.trimmingCharacters(in: .whitespaces), !due.isEmpty else { return nil }
        let halves = due.split(separator: "T", maxSplits: 1).map(String.init)
        let day = halves[0].split(separator: "-").compactMap { Int($0) }
        guard halves[0].count == 10, day.count == 3, (1...12).contains(day[1]), (1...31).contains(day[2]) else {
            return nil
        }
        var components = DateComponents(year: day[0], month: day[1], day: day[2])
        guard components.isValidDate(in: Calendar(identifier: .gregorian)) else { return nil }

        if halves.count == 2 {
            let time = halves[1].prefix(5).split(separator: ":").compactMap { Int($0) }
            guard time.count == 2, (0...23).contains(time[0]), (0...59).contains(time[1]) else { return nil }
            components.hour = time[0]
            components.minute = time[1]
        }
        return components
    }
}

public enum RemindersError: LocalizedError {
    case accessDenied
    case noList

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            tr("Нет доступа к Напоминаниям. Разрешите его в настройках конфиденциальности.",
               "No access to Reminders. Allow it in Privacy & Security settings.")
        case .noList: tr("В Напоминаниях нет списка для новых задач.", "Reminders has no list for new tasks.")
        }
    }
}

/// Puts tasks of a recording into the person's Reminders, in the default list, after asking for access once.
@MainActor
public final class RemindersExporter {
    private let store = EKEventStore()

    public init() {}

    /// Adds the tasks that are not done yet; returns how many were added.
    @discardableResult
    public func add(_ tasks: [TaskItem], from recording: RecordingItem) async throws -> Int {
        guard try await store.requestFullAccessToReminders() else { throw RemindersError.accessDenied }
        guard let list = store.defaultCalendarForNewReminders() else { throw RemindersError.noList }

        let open = tasks.filter { !$0.isDone }
        for task in open {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = task.title
            reminder.notes = Self.note(for: task, in: recording)
            reminder.dueDateComponents = TaskDueDate.components(from: task.due)
            try store.save(reminder, commit: false)
        }
        try store.commit()
        return open.count
    }

    nonisolated static func note(for task: TaskItem, in recording: RecordingItem) -> String {
        let date = recording.startedAt.formatted(RecordingExport.dateStyle)
        var lines = [tr("Из записи «\(recording.title)», \(date)", "From the recording “\(recording.title)”, \(date)")]
        if let owner = task.owner { lines.append(tr("Исполнитель: ", "Owner: ") + recording.displayName(owner)) }
        if let due = task.due, TaskDueDate.components(from: due) == nil { lines.append(tr("Срок: ", "Due: ") + due) }
        if let quote = task.quote { lines.append("«\(quote)»" + (task.timestamp.map { " · \($0.clockString)" } ?? "")) }
        return lines.joined(separator: "\n")
    }
}
