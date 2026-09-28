import Foundation
import Testing
@testable import CallLibrary

struct DiagnosticSummaryTests {
    private let machine = DiagnosticSummary.Machine(
        appVersion: "0.3.0", build: "5", system: "Version 26.0 (Build 25A354)", model: "Mac14,2",
        chip: "Apple M2", memoryBytes: 16 * 1_073_741_824, freeDiskBytes: 46_000_000_000
    )

    /// The samples, turned into the person's own recordings: they have real-looking titles, text and names.
    private var ownRecordings: [RecordingItem] {
        SampleData.recordings.map { sample in
            RecordingItem(
                id: sample.id, title: sample.title, appName: sample.appName, appBundleID: sample.appBundleID,
                startedAt: sample.startedAt, duration: sample.duration, status: sample.status,
                directory: URL(fileURLWithPath: "/tmp/\(sample.id)"), isSample: false,
                transcript: sample.transcript, analysis: sample.analysis, speakerNames: sample.speakerNames
            )
        }
    }

    @Test("names the app, the Mac and the library in numbers")
    func describesAppMacAndLibrary() {
        // Act
        let text = DiagnosticSummary.text(
            machine: machine, recordings: ownRecordings, settings: [("ИИ", "chatgpt")],
            recentProblems: ["11:02 Не удалось открыть аудио"], generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        // Assert
        #expect(text.contains("Transcribation 0.3.0 (5)"))
        #expect(text.contains("Version 26.0 (Build 25A354)"))
        #expect(text.contains("Mac14,2 · Apple M2 · 16 ГБ"))
        #expect(text.contains("Записей: \(ownRecordings.count)"))
        #expect(text.contains("ИИ: chatgpt"))
        #expect(text.contains("11:02 Не удалось открыть аудио"))
    }

    @Test("never contains what was said, titles or people's names")
    func keepsContentPrivate() {
        let recordings = ownRecordings
        let text = DiagnosticSummary.text(
            machine: machine, recordings: recordings, settings: [], recentProblems: [], generatedAt: Date()
        )

        let secrets = recordings.flatMap { recording in
            [recording.title] + recording.transcript.map(\.text) + recording.transcript.map(\.speaker)
                + (recording.analysis.map { [$0.summary] } ?? [])
        }
        let leaked = secrets.filter { $0.count > 2 && text.contains($0) }
        #expect(leaked.isEmpty, "leaked: \(leaked)")
    }

    @Test("the illustrative samples are not counted as the person's recordings")
    func samplesAreNotCounted() {
        let text = DiagnosticSummary.text(
            machine: machine, recordings: SampleData.recordings, settings: [], recentProblems: [], generatedAt: Date()
        )

        #expect(text.contains("Записей: 0"))
    }
}
