import CallLibrary
import Foundation
import Localization

/// Naming recordings after the calendar event they were made during.
extension AppModel {
    /// Asks for calendar access when the person turns the option on; turns it back off if they say no.
    func enableCalendar() async {
        guard await calendar.requestAccess() else {
            preferences.usesCalendar = false
            report(tr("Нет доступа к Календарю. Разрешите его в Системных настройках → Конфиденциальность и безопасность → Календари.", "No access to Calendar. Allow it in System Settings → Privacy & Security → Calendars."))
            return
        }
        preferences.usesCalendar = true
    }

    /// Looks the recording up in the calendar and keeps what it finds in `meeting.json`. `announcing` says the
    /// result out loud, for when the person asked for it.
    func findMeeting(for recordingID: UUID, announcing: Bool) async {
        guard preferences.usesCalendar,
              let recording = realRecordings.first(where: { $0.id == recordingID }),
              let directory = recording.directory
        else { return }
        guard let meeting = await calendar.meeting(
            recordingStart: recording.startedAt, duration: recording.duration, appBundleID: recording.appBundleID
        ) else {
            if announcing { announce(tr("В Календаре нет встречи на это время", "Calendar has no meeting at that time")) }
            return
        }
        do {
            try MeetingInfoStore.save(meeting, in: directory)
            await reload()
            if announcing { announce(tr("Нашли встречу «\(meeting.title)»", "Found the meeting “\(meeting.title)”")) }
        } catch {
            report(error, doing: tr("Не удалось сохранить встречу", "Could not save the meeting"))
        }
    }

    /// The meetings of the calendar around a recording, to pick the right one by hand.
    func meetingChoices(for recording: RecordingItem) async -> [CalendarEvent] {
        guard preferences.usesCalendar else { return [] }
        return await calendar.choices(
            recordingStart: recording.startedAt, duration: recording.duration, appBundleID: recording.appBundleID
        )
    }

    /// Links the recording to the meeting the person picked, replacing whatever was found before.
    func link(_ event: CalendarEvent, to recordingID: UUID) async {
        guard let directory = realRecordings.first(where: { $0.id == recordingID })?.directory else { return }
        do {
            try MeetingInfoStore.save(MeetingInfo(event: event), in: directory)
            await reload()
            announce(tr("Запись связана со встречей «\(event.title)»", "Linked to the meeting “\(event.title)”"))
        } catch {
            report(error, doing: tr("Не удалось сохранить встречу", "Could not save the meeting"))
        }
    }

    /// Takes a wrongly found meeting away: the recording goes back to its own name.
    func unlinkMeeting(from recordingID: UUID) async {
        guard let directory = realRecordings.first(where: { $0.id == recordingID })?.directory else { return }
        do {
            try MeetingInfoStore.remove(from: directory)
            await reload()
            announce(tr("Встреча отвязана", "Meeting unlinked"))
        } catch {
            report(error, doing: tr("Не удалось отвязать встречу", "Could not unlink the meeting"))
        }
    }

    /// Looks up the meeting going on now for the chosen app, for the recording screen.
    func refreshMeetingNow() async {
        guard preferences.usesCalendar else {
            meetingNow = nil
            return
        }
        let bundleID = selectedBundleID
        meetingNow = await calendar.meetingNow(appBundleID: bundleID)
    }
}
