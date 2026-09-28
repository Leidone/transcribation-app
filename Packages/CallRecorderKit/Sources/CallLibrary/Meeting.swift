import EventKit
import Foundation
import Localization
import os

private let calendarLog = Logger(subsystem: "app.callrecorder.dev", category: "calendar")

/// The calendar event a recording belongs to (`meeting.json`). Its title names the recording; its attendees are
/// offered when naming the voices and are given to the AI along with the transcript.
public struct MeetingInfo: Codable, Equatable, Sendable {
    public let title: String
    public let attendees: [String]
    /// The invited people's addresses, for a follow-up letter. Files written before they were kept have none.
    public let emails: [String]

    public init(title: String, attendees: [String], emails: [String] = []) {
        self.title = title
        self.attendees = attendees
        self.emails = emails
    }

    public init(event: CalendarEvent) {
        self.init(title: event.title, attendees: event.attendees, emails: event.emails)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        attendees = try container.decode([String].self, forKey: .attendees)
        emails = try container.decodeIfPresent([String].self, forKey: .emails) ?? []
    }
}

public enum MeetingInfoStore {
    public static let fileName = "meeting.json"

    public static func save(_ meeting: MeetingInfo, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(meeting).write(to: directory.appending(path: fileName), options: .atomic)
    }

    /// `nil` when the recording was never matched to a meeting.
    public static func load(from directory: URL) throws -> MeetingInfo? {
        let file = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(MeetingInfo.self, from: Data(contentsOf: file))
    }

    /// Unlinks the recording from its meeting; nothing to do when it has none.
    public static func remove(from directory: URL) throws {
        let file = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}

/// A calendar event as far as matching needs it, so the choice can be tested without EventKit.
public struct CalendarEvent: Hashable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    /// The people invited, without the calendar's owner.
    public let attendees: [String]
    /// Location, address and notes together: where a call link would be.
    public let linkText: String
    /// The invited people's email addresses, where the calendar has them.
    public let emails: [String]
    /// Not one of the person's meetings: from a subscribed or birthdays calendar, declined, or cancelled.
    public let isSkipped: Bool

    public init(
        title: String, start: Date, end: Date, isAllDay: Bool, attendees: [String], linkText: String,
        emails: [String] = [], isSkipped: Bool = false
    ) {
        self.emails = emails
        self.isSkipped = isSkipped
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.attendees = attendees
        self.linkText = linkText
    }
}

/// Picks the event a recording most likely belongs to.
public enum MeetingMatcher {
    /// People open a call a little before it is due.
    static let earlyStart: TimeInterval = 15 * 60

    /// Call links by the app that opens them.
    static let linkHosts: [String: [String]] = [
        "us.zoom.xos": ["zoom.us"],
        "com.microsoft.teams2": ["teams.microsoft.com", "teams.live.com"],
        "com.microsoft.teams": ["teams.microsoft.com", "teams.live.com"],
        "ru.yandex.desktop.telemost": ["telemost.yandex", "telemost.360.yandex"],
        "com.apple.FaceTime": ["facetime.apple.com"],
        "com.cisco.webexmeetingsapp": ["webex.com"],
    ]
    static let anyCallHost = ["meet.google.com", "whereby.com", "meet.jit.si"] + linkHosts.values.flatMap { $0 }
    /// Longer than this, an event with no call link and nobody invited is a block of time ("Working day"), not a call.
    static let longestPlainEvent: TimeInterval = 3 * 3_600
    /// How far from the recording the manual choice still offers events.
    static let choiceWindow: TimeInterval = 3 * 3_600

    public static func bestMatch(
        recordingStart: Date, duration: TimeInterval, appBundleID: String?, among events: [CalendarEvent]
    ) -> CalendarEvent? {
        let recordingEnd = recordingStart + max(duration, 60)
        let candidates = events.filter { event in
            isPlausible(event) && event.start - earlyStart <= recordingEnd && event.end >= recordingStart
        }
        return sorted(candidates, appBundleID: appBundleID, start: recordingStart).first
    }

    /// The meetings the person can pick for a recording by hand: those within a few hours of it, the likeliest
    /// (the one `bestMatch` would take) first, then the others by closeness.
    public static func choices(
        recordingStart: Date, duration: TimeInterval, appBundleID: String?, among events: [CalendarEvent]
    ) -> [CalendarEvent] {
        let recordingEnd = recordingStart + max(duration, 60)
        let nearby = events.filter { event in
            isPlausible(event) && event.start <= recordingEnd + choiceWindow && event.end >= recordingStart - choiceWindow
        }
        return sorted(nearby, appBundleID: appBundleID, start: recordingStart)
    }

    private static func isPlausible(_ event: CalendarEvent) -> Bool {
        guard !event.isAllDay, !event.isSkipped else { return false }
        let isPlainBlock = event.attendees.isEmpty && !anyCallHost.contains { event.linkText.lowercased().contains($0) }
        return !(isPlainBlock && event.end.timeIntervalSince(event.start) > longestPlainEvent)
    }

    private static func sorted(_ events: [CalendarEvent], appBundleID: String?, start: Date) -> [CalendarEvent] {
        let appHosts = appBundleID.flatMap { linkHosts[$0] } ?? []
        let overlapping = { (event: CalendarEvent) in event.start - earlyStart <= start && event.end >= start ? 1 : 0 }
        return events.sorted { lhs, rhs in
            let left = (overlapping(lhs), rank(lhs, appHosts: appHosts, start: start))
            let right = (overlapping(rhs), rank(rhs, appHosts: appHosts, start: start))
            return left.0 != right.0 ? left.0 > right.0 : left.1 > right.1
        }
    }

    /// Compared in order: a link to the recorded app, any call link, people invited, then the closest start.
    private static func rank(_ event: CalendarEvent, appHosts: [String], start: Date) -> (Int, Int, Int, Double) {
        let text = event.linkText.lowercased()
        return (
            appHosts.contains { text.contains($0) } ? 1 : 0,
            anyCallHost.contains { text.contains($0) } ? 1 : 0,
            event.attendees.isEmpty ? 0 : 1,
            -abs(event.start.timeIntervalSince(start))
        )
    }
}

/// Reads the person's calendars, only after they allowed it in the settings.
public actor CalendarLookup {
    private let store = EKEventStore()

    public init() {}

    public static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Shows the system request the first time; `false` if the person said no now or earlier.
    public func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            calendarLog.error("calendar access failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The meeting a recording belongs to, if the calendar has one at that time.
    public func meeting(recordingStart: Date, duration: TimeInterval, appBundleID: String?) -> MeetingInfo? {
        MeetingMatcher.bestMatch(
            recordingStart: recordingStart, duration: duration, appBundleID: appBundleID,
            among: events(around: recordingStart, duration: duration)
        ).map(MeetingInfo.init(event:))
    }

    /// The meetings to pick from by hand for a recording, the likeliest first.
    public func choices(recordingStart: Date, duration: TimeInterval, appBundleID: String?) -> [CalendarEvent] {
        MeetingMatcher.choices(
            recordingStart: recordingStart, duration: duration, appBundleID: appBundleID,
            among: events(around: recordingStart, duration: duration)
        )
    }

    /// The meeting a recording started now would be linked to: shown on the recording screen beforehand.
    public func meetingNow(appBundleID: String?) -> CalendarEvent? {
        let now = Date()
        return MeetingMatcher.bestMatch(
            recordingStart: now, duration: 60, appBundleID: appBundleID, among: events(around: now, duration: 60)
        )
    }

    private func events(around start: Date, duration: TimeInterval) -> [CalendarEvent] {
        guard Self.hasAccess else { return [] }
        let window = store.predicateForEvents(
            withStart: start - 12 * 3_600, end: start + duration + 6 * 3_600, calendars: nil
        )
        return store.events(matching: window).map(Self.calendarEvent)
    }

    private static func calendarEvent(_ event: EKEvent) -> CalendarEvent {
        let others = (event.attendees ?? []).filter { !$0.isCurrentUser }
        let attendees = others
            .compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("@") }
        // A participant's URL is "mailto:address" for ordinary invitations.
        let emails = others.compactMap { participant -> String? in
            let url = participant.url
            guard url.scheme?.lowercased() == "mailto" else { return nil }
            let address = String(url.absoluteString.dropFirst("mailto:".count)).removingPercentEncoding ?? ""
            return address.contains("@") ? address : nil
        }
        let linkText = [event.location, event.url?.absoluteString, event.notes].compactMap { $0 }.joined(separator: " ")
        let calendarType = event.calendar?.type
        let isDeclined = (event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined }
        return CalendarEvent(
            title: event.title ?? tr("Встреча", "Meeting"), start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
            attendees: attendees, linkText: linkText, emails: emails,
            isSkipped: calendarType == .subscription || calendarType == .birthday || event.status == .canceled || isDeclined
        )
    }
}
