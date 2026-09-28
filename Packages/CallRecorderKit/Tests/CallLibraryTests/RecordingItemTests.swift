import AudioCapture
import CodexClient
import Foundation
import Testing
import Transcription
@testable import CallLibrary

private func line(_ id: Int, _ time: TimeInterval, _ speaker: String = "Анна", _ text: String = "текст") -> TranscriptLine {
    TranscriptLine(id: id, time: time, speaker: speaker, isMe: speaker == "Я", text: text)
}

private func recording(
    lines: [TranscriptLine] = [line(0, 0), line(1, 10, "Я"), line(2, 20)],
    analysisCreatedAt: Date? = Date(timeIntervalSince1970: 1_000),
    editedAt: Date? = nil
) -> RecordingItem {
    RecordingItem(
        id: UUID(), title: "Созвон", appName: "Zoom", appBundleID: nil, startedAt: .now, duration: 60,
        status: .ready, directory: nil, isSample: false, transcript: lines,
        analysis: analysisCreatedAt.map {
            AnalysisResult(
                summary: "Итог", decisions: [],
                tasks: [TaskItem(id: UUID(), title: "Сделать", owner: nil, due: nil, quote: nil, timestamp: nil, isDone: false)],
                createdAt: $0
            )
        },
        transcriptEditedAt: editedAt
    )
}

@Test func editingALineReplacesOnlyItsTextAndMarksTheEdit() {
    let original = recording()
    let when = Date(timeIntervalSince1970: 2_000)

    let edited = original.editingLine(1, to: "  исправлено  ", at: when)

    #expect(edited.transcript[1].text == "исправлено")
    #expect(edited.transcript[1].speaker == "Я")
    #expect(edited.transcript[0] == original.transcript[0])
    #expect(edited.transcriptEditedAt == when)
    #expect(original.transcript[1].text == "текст")
}

@Test(arguments: ["", "   ", "текст"])
func editingWithEmptyOrUnchangedTextChangesNothing(text: String) {
    let original = recording()
    #expect(original.editingLine(1, to: text) == original)
}

@Test func editingAnUnknownLineChangesNothing() {
    let original = recording()
    #expect(original.editingLine(99, to: "новое") == original)
}

@Test func analysisIsOutdatedOnlyAfterALaterEdit() {
    #expect(!recording(editedAt: nil).isAnalysisOutdated)
    #expect(!recording(editedAt: Date(timeIntervalSince1970: 500)).isAnalysisOutdated)
    #expect(recording(editedAt: Date(timeIntervalSince1970: 1_500)).isAnalysisOutdated)
    #expect(!recording(analysisCreatedAt: nil, editedAt: .now).isAnalysisOutdated)
}

@Test func lineAtTimeIsTheLastOneThatStartedBefore() {
    let item = recording()
    #expect(item.line(at: -1) == nil)
    #expect(item.line(at: 0)?.id == 0)
    #expect(item.line(at: 9.9)?.id == 0)
    #expect(item.line(at: 10)?.id == 1)
    #expect(item.line(at: 500)?.id == 2)
}

@Test func togglingATaskKeepsEverythingElse() throws {
    let original = recording(editedAt: Date(timeIntervalSince1970: 5))
    let task = try #require(original.analysis?.tasks.first)

    let toggled = original.togglingTask(task.id)

    #expect(toggled.analysis?.tasks.first?.isDone == true)
    #expect(toggled.transcript == original.transcript)
    #expect(toggled.transcriptEditedAt == original.transcriptEditedAt)
    #expect(original.analysis?.tasks.first?.isDone == false)
}

@Test func speakersAreListedOnceInOrderOfAppearance() {
    let item = recording(lines: [line(0, 0, "Борис"), line(1, 1, "Я"), line(2, 2, "Борис"), line(3, 3, "Анна")])
    #expect(item.speakers.map(\.label) == ["Борис", "Я", "Анна"])
    #expect(item.speakers.map(\.isMe) == [false, true, false])
}

@Test func speedFactorIsAudioOverProcessingTime() {
    #expect(ProcessingStats(audioSeconds: 600, processingSeconds: 4).speedFactor == 150)
    #expect(ProcessingStats(audioSeconds: 600, processingSeconds: 0).speedFactor == nil)
}

@Test func clockStringFormatsMinutesAndHours() {
    #expect(TimeInterval(0).clockString == "0:00")
    #expect(TimeInterval(75.9).clockString == "1:15")
    #expect(TimeInterval(3_725).clockString == "1:02:05")
    #expect(TimeInterval(-3).clockString == "0:00")
}

@Test func storedAnalysisRoundTripsTheTemplate() {
    let result = AnalysisResult(
        summary: "s", decisions: ["d"], tasks: [], createdAt: Date(timeIntervalSince1970: 0), template: .sales
    )
    #expect(AnalysisResult(stored: result.stored) == result)
    #expect(result.stored.template == "sales")
}

@Test func anUnknownStoredTemplateReadsAsGeneral() {
    let stored = StoredAnalysis(createdAt: .now, summary: "s", decisions: [], tasks: [], template: "future-kind")
    #expect(AnalysisResult(stored: stored).template == nil)
}

@Test func samplesShowOnlyInAnEmptyLibraryWhenEnabled() {
    let samples = SampleData.recordings
    #expect(SampleData.visible(samples, alongside: 0, enabled: true) == samples)
    #expect(SampleData.visible(samples, alongside: 0, enabled: false).isEmpty)
    #expect(SampleData.visible(samples, alongside: 1, enabled: true).isEmpty)
    #expect(SampleData.visible(samples, alongside: 3, enabled: false).isEmpty)
}

@MainActor
@Test func theSamplesPreferenceDefaultsToOnAndIsRemembered() throws {
    let suite = "samples-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = AppPreferences(defaults: defaults)
    #expect(first.showsSamples)
    first.showsSamples = false
    #expect(!AppPreferences(defaults: defaults).showsSamples)
}

@MainActor
@Test func compressionAndAutoStopDefaultToOnAndAreRemembered() throws {
    let suite = "recording-prefs-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = AppPreferences(defaults: defaults)
    #expect(first.compressesAudio)
    #expect(first.stopsWhenCallEnds)
    first.compressesAudio = false
    first.stopsWhenCallEnds = false

    let reloaded = AppPreferences(defaults: defaults)
    #expect(!reloaded.compressesAudio)
    #expect(!reloaded.stopsWhenCallEnds)
}
