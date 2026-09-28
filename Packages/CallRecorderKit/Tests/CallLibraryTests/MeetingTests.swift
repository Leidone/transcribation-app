import Foundation
import Testing
@testable import AudioCapture
@testable import CallLibrary

struct MeetingMatcherTests {
    private let nine = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ title: String, from start: TimeInterval, minutes: Double = 30, allDay: Bool = false,
        attendees: [String] = [], link: String = "", skipped: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            title: title, start: nine + start, end: nine + start + minutes * 60, isAllDay: allDay,
            attendees: attendees, linkText: link, isSkipped: skipped
        )
    }

    @Test("the event going on when the recording started is chosen")
    func picksOverlappingEvent() {
        let events = [event("Вчерашнее", from: -86_400), event("Планёрка", from: -120), event("Обед", from: 7_200)]

        let match = MeetingMatcher.bestMatch(recordingStart: nine, duration: 1_200, appBundleID: nil, among: events)

        #expect(match?.title == "Планёрка")
    }

    @Test("a recording started a few minutes early still belongs to the meeting")
    func earlyStart() {
        let match = MeetingMatcher.bestMatch(
            recordingStart: nine, duration: 1_800, appBundleID: nil, among: [event("Созвон", from: 300)]
        )

        #expect(match?.title == "Созвон")
    }

    @Test("all-day events and events that do not overlap are never chosen")
    func ignoresAllDayAndDistant() {
        let events = [event("Отпуск", from: -3_600, minutes: 1_440, allDay: true), event("Вечером", from: 3 * 3_600)]

        #expect(MeetingMatcher.bestMatch(recordingStart: nine, duration: 1_200, appBundleID: nil, among: events) == nil)
    }

    @Test("with two events at once, the one with a link to the recorded app wins")
    func prefersLinkToTheApp() {
        let events = [
            event("Фокус-время", from: -600, minutes: 120),
            event("Ретро", from: 0, link: "https://telemost.yandex.ru/j/123"),
            event("Синк с Zoom", from: 0, link: "https://us02web.zoom.us/j/555"),
        ]

        let match = MeetingMatcher.bestMatch(
            recordingStart: nine, duration: 1_200, appBundleID: "ru.yandex.desktop.telemost", among: events
        )

        #expect(match?.title == "Ретро")
    }

    @Test("events that are not the person's meetings are never chosen: subscribed calendars, declined, cancelled")
    func ignoresSkippedEvents() {
        let events = [event("Подписка на «Ежегодное изменение карты»", from: -60, skipped: true)]

        #expect(MeetingMatcher.bestMatch(recordingStart: nine, duration: 600, appBundleID: nil, among: events) == nil)
    }

    @Test("a long block with no call link and nobody invited is not a meeting")
    func ignoresLongEmptyBlocks() {
        let block = event("Рабочий день", from: -3_600, minutes: 9 * 60)
        let call = event("Созвон", from: -3_600, minutes: 9 * 60, link: "https://telemost.yandex.ru/j/1")

        #expect(MeetingMatcher.bestMatch(recordingStart: nine, duration: 600, appBundleID: nil, among: [block]) == nil)
        #expect(MeetingMatcher.bestMatch(recordingStart: nine, duration: 600, appBundleID: nil, among: [block, call])?.title == "Созвон")
    }

    @Test("the choices for a recording are the nearby meetings, the likeliest first")
    func choicesAroundTheRecording() {
        let events = [
            event("Утром", from: -2 * 3_600, attendees: ["Анна"]),
            event("Ретро", from: 0, link: "https://telemost.yandex.ru/j/1"),
            event("Подписка", from: 0, skipped: true),
            event("Отпуск", from: -3_600, minutes: 1_440, allDay: true),
            event("Завтра", from: 86_400),
        ]

        let choices = MeetingMatcher.choices(
            recordingStart: nine, duration: 600, appBundleID: "ru.yandex.desktop.telemost", among: events
        )

        #expect(choices.map(\.title) == ["Ретро", "Утром"])
    }

    @Test("without links, the event with people in it beats a private block")
    func prefersEventWithAttendees() {
        let events = [event("Фокус-время", from: -60, minutes: 120), event("1:1 с Анной", from: 0, attendees: ["Анна"])]

        let match = MeetingMatcher.bestMatch(recordingStart: nine, duration: 1_200, appBundleID: nil, among: events)

        #expect(match?.title == "1:1 с Анной")
    }
}

struct MeetingInfoTests {
    private func makeStored(title: String? = nil) -> StoredRecording {
        StoredRecording(
            id: UUID(), title: title, appName: "Телемост", appBundleID: "ru.yandex.desktop.telemost",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000), directory: URL(fileURLWithPath: "/tmp/x"),
            duration: 60, audio: .single(URL(fileURLWithPath: "/tmp/x/a.m4a"))
        )
    }

    @Test("meeting.json round-trips, and no file means no meeting")
    func storeRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "meeting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try MeetingInfoStore.load(from: folder) == nil)

        let meeting = MeetingInfo(title: "Планёрка", attendees: ["Анна", "Борис"])
        try MeetingInfoStore.save(meeting, in: folder)

        #expect(try MeetingInfoStore.load(from: folder) == meeting)
    }

    @Test("a recording is named after its meeting")
    func titleComesFromMeeting() {
        let named = RecordingItem(stored: makeStored(), meeting: MeetingInfo(title: "Планёрка", attendees: []))
        let plain = RecordingItem(stored: makeStored())

        #expect(named.title == "Планёрка")
        #expect(plain.title == "Запись — Телемост")
    }

    @Test("the AI is told the meeting and who was invited, before the transcript")
    func analysisTextCarriesMeeting() {
        let lines = [TranscriptLine(id: 0, time: 1, speaker: "Я", isMe: true, text: "Начнём")]
        let meeting = MeetingInfo(title: "Планёрка", attendees: ["Анна", "Борис"])
        let base = RecordingItem(stored: makeStored(), meeting: meeting)
        let recording = RecordingItem(
            id: base.id, title: base.title, appName: base.appName, appBundleID: base.appBundleID,
            startedAt: base.startedAt, duration: base.duration, status: .transcribed, directory: base.directory,
            isSample: false, transcript: lines, analysis: nil, meeting: meeting
        )

        let text = recording.analysisText

        #expect(text.hasPrefix("Встреча: Планёрка\nПриглашены: Анна, Борис\n\n"))
        #expect(text.hasSuffix(recording.transcriptText))
        #expect(recording.with(meeting: .some(nil)).analysisText == recording.transcriptText)
    }
}
