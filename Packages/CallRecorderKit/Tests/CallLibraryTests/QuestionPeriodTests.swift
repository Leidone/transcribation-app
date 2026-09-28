import Foundation
import Testing
@testable import CallLibrary

struct QuestionPeriodTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    /// An afternoon in late September 2026.
    private let now = Date(timeIntervalSince1970: 1_790_769_600)

    @Test("a question about the week covers the last seven days")
    func week() throws {
        let period = try #require(QuestionPeriod.interval(in: "Итоги недели: что решили?", now: now, calendar: calendar))

        #expect(period.end == now)
        #expect(period.duration == 7 * 86_400)
        #expect(QuestionPeriod.interval(in: "What did we decide this week?", now: now, calendar: calendar) == period)
    }

    @Test("today and yesterday are whole calendar days")
    func todayAndYesterday() throws {
        let today = try #require(QuestionPeriod.interval(in: "Что обсуждали сегодня?", now: now, calendar: calendar))
        let yesterday = try #require(QuestionPeriod.interval(in: "а вчера?", now: now, calendar: calendar))

        #expect(today.start == calendar.startOfDay(for: now))
        #expect(yesterday.end == today.start)
        #expect(yesterday.duration == 86_400)
    }

    @Test("a question without a period is about the whole library")
    func noPeriod() {
        #expect(QuestionPeriod.interval(in: "Когда обсуждали бюджет?", now: now, calendar: calendar) == nil)
    }

    @Test("the library context for a weekly question holds only that week's meetings")
    func libraryContextKeepsThePeriod() throws {
        // Arrange: one meeting two days ago, one a month ago
        let base = SampleData.recordings[0]
        let recent = copy(of: base, startedAt: now.addingTimeInterval(-2 * 86_400))
        let old = copy(of: base, startedAt: now.addingTimeInterval(-30 * 86_400))

        // Act
        let context = MeetingContext.library([recent, old], question: "Итоги недели", now: now, calendar: calendar)

        // Assert
        #expect(Set(context.references.values) == [recent.id])
    }

    private func copy(of recording: RecordingItem, startedAt: Date) -> RecordingItem {
        RecordingItem(
            id: UUID(), title: recording.title, appName: recording.appName, appBundleID: recording.appBundleID,
            startedAt: startedAt, duration: recording.duration, status: recording.status, directory: nil,
            isSample: false, transcript: recording.transcript, analysis: recording.analysis
        )
    }
}
