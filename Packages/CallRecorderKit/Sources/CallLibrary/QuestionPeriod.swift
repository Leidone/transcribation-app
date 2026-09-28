import Foundation

/// The time a question is about, when it says one: "today", "yesterday", "this week", "this month" (in Russian or
/// English). Questions to the whole library then look at that period's meetings only.
public enum QuestionPeriod {
    public static func interval(in question: String, now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        let text = question.lowercased()
        let startOfToday = calendar.startOfDay(for: now)
        if text.contains("вчера") || text.contains("yesterday") {
            let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return DateInterval(start: start, end: startOfToday)
        }
        if text.contains("сегодня") || text.contains("today") {
            return DateInterval(start: startOfToday, end: max(startOfToday, now))
        }
        if text.contains("недел") || text.contains("week") {
            return DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        }
        if text.contains("месяц") || text.contains("month") {
            return DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
        }
        return nil
    }
}
