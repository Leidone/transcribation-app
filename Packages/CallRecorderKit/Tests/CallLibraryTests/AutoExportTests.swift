import Foundation
import Testing
@testable import CallLibrary

struct AutoExportTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("the summary lands in the folder as Markdown, named by date and title")
    func writesMarkdown() throws {
        // Arrange
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let recording = SampleData.recordings[0]

        // Act
        let file = try AutoExport.write(recording, to: folder, includesTranscript: false)

        // Assert
        #expect(file.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(file.lastPathComponent.hasSuffix("\(recording.title).md"))
        #expect(file.lastPathComponent.hasPrefix(AutoExport.datePrefix(recording.startedAt)))
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains(try #require(recording.analysis?.summary)))
        #expect(!text.contains(recording.transcript[0].text), "no transcript unless asked")
    }

    @Test("writing again replaces the same note instead of adding another")
    func replacesTheSameNote() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let recording = SampleData.recordings[0]

        let first = try AutoExport.write(recording, to: folder, includesTranscript: false)
        let second = try AutoExport.write(recording, to: folder, includesTranscript: true)

        #expect(first == second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
        #expect(try String(contentsOf: second, encoding: .utf8).contains(recording.transcript[0].text))
    }

    @Test("two meetings with the same title on different days are two notes")
    func sameTitleDifferentDays() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let monday = SampleData.recordings[0]
        let tuesday = RecordingItem(
            id: UUID(), title: monday.title, appName: monday.appName, appBundleID: monday.appBundleID,
            startedAt: monday.startedAt.addingTimeInterval(86_400), duration: monday.duration, status: monday.status,
            directory: nil, isSample: false, transcript: monday.transcript, analysis: monday.analysis
        )

        let one = try AutoExport.write(monday, to: folder, includesTranscript: false)
        let two = try AutoExport.write(tuesday, to: folder, includesTranscript: false)

        #expect(one != two)
    }
}
