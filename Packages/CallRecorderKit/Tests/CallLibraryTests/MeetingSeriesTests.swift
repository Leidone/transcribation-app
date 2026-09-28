import Foundation
import Testing
@testable import CallLibrary

struct MeetingSeriesTests {
    private let day: TimeInterval = 86_400
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(_ title: String?, daysAgo: Double, done: Bool = false) -> RecordingItem {
        let sample = SampleData.recordings[0]
        let analysis = done ? sample.analysis.map { result in
            result.tasks.filter { !$0.isDone }.reduce(result) { $0.togglingTask($1.id) }
        } : sample.analysis
        return RecordingItem(
            id: UUID(), title: title ?? "Запись — Zoom", appName: "Zoom", appBundleID: nil,
            startedAt: base - daysAgo * day, duration: 600, status: .ready, directory: nil, isSample: false,
            transcript: sample.transcript, analysis: analysis,
            meeting: title.map { MeetingInfo(title: $0, attendees: []) }
        )
    }

    @Test("meetings of the same calendar event form a series, oldest first; others stay out")
    func membersOfTheSeries() {
        let monday = meeting("Daily", daysAgo: 2)
        let tuesday = meeting("daily ", daysAgo: 1)
        let other = meeting("Ретро", daysAgo: 1)
        let plain = meeting(nil, daysAgo: 1)

        let series = MeetingSeries.members(of: tuesday, in: [tuesday, other, plain, monday])

        #expect(series.map(\.id) == [monday.id, tuesday.id])
        #expect(MeetingSeries.members(of: plain, in: [plain, meeting(nil, daysAgo: 3)]).isEmpty, "no event, no series")
    }

    @Test("the previous meeting is the latest one before it in the series")
    func previousMeeting() {
        let first = meeting("Daily", daysAgo: 3)
        let second = meeting("Daily", daysAgo: 2)
        let third = meeting("Daily", daysAgo: 1)

        #expect(MeetingSeries.previous(of: third, in: [first, third, second])?.id == second.id)
        #expect(MeetingSeries.previous(of: first, in: [first, second, third]) == nil)
    }

    @Test("the note for the AI lists the tasks the last meeting left open, and nothing when all are done")
    func followUpNote() throws {
        let open = meeting("Daily", daysAgo: 1)
        let closed = meeting("Daily", daysAgo: 1, done: true)
        let firstTask = try #require(open.analysis?.tasks.first)

        let note = try #require(MeetingSeries.followUpNote(from: open))

        #expect(note.contains(firstTask.title))
        #expect(MeetingSeries.followUpNote(from: closed) == nil)
    }

    @Test("a question about one meeting also carries the previous one of its series, as its own source")
    func questionContextHasThePreviousMeeting() {
        let before = meeting("Daily", daysAgo: 2)
        let now = meeting("Daily", daysAgo: 1)

        let context = MeetingContext.single(now, previous: before)

        #expect(Set(context.references.values) == [now.id, before.id])
        #expect(context.text.contains("M1"))
        #expect(context.text.contains("M2"))
    }
}
