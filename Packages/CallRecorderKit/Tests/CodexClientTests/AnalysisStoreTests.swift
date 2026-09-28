import Foundation
import Testing
@testable import CodexClient

struct AnalysisStoreTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "analysis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private let analysis = CallAnalysis(
        summary: "Обсудили релиз",
        decisions: ["Релиз в пятницу"],
        tasks: [
            AnalysisTask(title: "Проверить тесты", owner: "Борис", due: "до среды", quote: "проверю", timestampSeconds: 14),
            AnalysisTask(title: "Написать в поддержку", owner: nil, due: nil, quote: nil, timestampSeconds: nil),
        ]
    )
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a fresh answer becomes a stored analysis with distinct ids and nothing done")
    func conversion() {
        let stored = StoredAnalysis(analysis: analysis, createdAt: createdAt)

        #expect(stored.tasks.map(\.title) == ["Проверить тесты", "Написать в поддержку"])
        #expect(Set(stored.tasks.map(\.id)).count == 2)
        #expect(stored.tasks.allSatisfy { !$0.isDone })
        #expect(stored.tasks[0].owner == "Борис")
        #expect(stored.tasks[1].owner == nil)
    }

    @Test("a saved analysis loads back unchanged")
    func roundTrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stored = StoredAnalysis(analysis: analysis, createdAt: createdAt)

        try AnalysisStore.save(stored, in: directory)

        #expect(try AnalysisStore.load(from: directory) == stored)
    }

    @Test("a recording without an analysis loads as nil")
    func missingFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try AnalysisStore.load(from: directory) == nil)
    }

    @Test("a corrupt file is an error, not an empty analysis")
    func corruptFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ nope".utf8).write(to: directory.appending(path: AnalysisStore.fileName))

        #expect(throws: DecodingError.self) { try AnalysisStore.load(from: directory) }
    }

    @Test("toggling a task returns a copy and leaves the original alone")
    func togglingIsImmutable() throws {
        let stored = StoredAnalysis(analysis: analysis, createdAt: createdAt)
        let taskID = try #require(stored.tasks.first?.id)

        let toggled = stored.togglingTask(taskID)

        #expect(stored.tasks[0].isDone == false)
        #expect(toggled.tasks[0].isDone == true)
        #expect(toggled.tasks[1].isDone == false)
        #expect(toggled.togglingTask(taskID) == stored)
    }

    @Test("toggling an unknown task changes nothing")
    func unknownTask() {
        let stored = StoredAnalysis(analysis: analysis, createdAt: createdAt)

        #expect(stored.togglingTask(UUID()) == stored)
    }
}
