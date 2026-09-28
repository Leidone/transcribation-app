import Foundation
import Testing
@testable import CallLibrary

struct FollowUpEmailTests {
    /// The release sample: a summary, two decisions and four tasks with owners and deadlines.
    private var release: RecordingItem {
        SampleData.recordings[0]
    }

    @Test("the draft carries the summary, the decisions and who does what by when")
    func draftCarriesTheResult() throws {
        // Arrange
        let recording = release
        let analysis = try #require(recording.analysis)

        // Act
        let draft = try #require(FollowUpEmail.draft(for: recording))

        // Assert
        #expect(draft.subject == "Итоги встречи: \(recording.title)")
        #expect(draft.body.contains(analysis.summary))
        for decision in analysis.decisions {
            #expect(draft.body.contains("- \(decision)"))
        }
        let firstTask = try #require(analysis.tasks.first { $0.owner != nil && $0.due != nil })
        let owner = recording.displayName(try #require(firstTask.owner))
        #expect(draft.body.contains("- \(owner): \(firstTask.title) (\(try #require(firstTask.due)))"))
    }

    @Test("the invited people from the calendar are the recipients; without a meeting there are none")
    func recipientsComeFromTheMeeting() throws {
        let meeting = MeetingInfo(title: "Weekly", attendees: ["Анна", "Борис"], emails: ["anna@example.com", "boris@example.com"])

        let withMeeting = try #require(FollowUpEmail.draft(for: release.with(meeting: .some(meeting))))
        let withoutMeeting = try #require(FollowUpEmail.draft(for: release))

        #expect(withMeeting.recipients == ["anna@example.com", "boris@example.com"])
        #expect(withoutMeeting.recipients.isEmpty)
    }

    @Test("tasks already done are left out of the letter")
    func doneTasksAreLeftOut() throws {
        let recording = release
        let task = try #require(recording.analysis?.tasks.first)

        let draft = try #require(FollowUpEmail.draft(for: recording.togglingTask(task.id)))

        #expect(!draft.body.contains(task.title))
    }

    @Test("a recording without a summary has nothing to send")
    func noSummaryNoDraft() {
        let bare = release.with(analysis: .some(nil))

        #expect(FollowUpEmail.draft(for: bare) == nil)
    }

    @Test("a meeting.json written before addresses were kept still reads, with no addresses")
    func oldMeetingFileStillReads() throws {
        let old = Data(#"{"attendees":["Анна"],"title":"Планёрка"}"#.utf8)

        let meeting = try JSONDecoder().decode(MeetingInfo.self, from: old)

        #expect(meeting.attendees == ["Анна"])
        #expect(meeting.emails.isEmpty)
    }
}
