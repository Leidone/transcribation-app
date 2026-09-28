import Foundation
import Testing
@testable import CallLibrary

struct TagsTests {
    @Test("tags round-trip in tags.json; no tags means no file")
    func storeRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tags-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try TagStore.load(from: folder).isEmpty)

        try TagStore.save(["проект Альфа", "клиент"], in: folder)
        #expect(try TagStore.load(from: folder) == ["проект Альфа", "клиент"])

        try TagStore.save([], in: folder)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: TagStore.fileName).path))
    }

    @Test("adding trims the tag, ignores an empty one and a repeat in another case")
    func adding() {
        #expect(TagStore.adding("  клиент ", to: ["проект"]) == ["проект", "клиент"])
        #expect(TagStore.adding("   ", to: ["проект"]) == ["проект"])
        #expect(TagStore.adding("ПРОЕКТ", to: ["проект"]) == ["проект"])
    }

    @Test("every tag in use, once, most used first")
    func allTags() {
        let sample = SampleData.recordings[0]
        let recordings = [["b", "a"], ["a"], ["c", "a"]].map { tags in
            RecordingItem(
                id: UUID(), title: sample.title, appName: sample.appName, appBundleID: nil, startedAt: sample.startedAt,
                duration: sample.duration, status: sample.status, directory: nil, isSample: false,
                transcript: [], analysis: nil, tags: tags
            )
        }

        #expect(TagStore.allTags(in: recordings) == ["a", "b", "c"])
    }

    @Test("a search finds a recording by its tag")
    func searchFindsTags() {
        let sample = SampleData.recordings[0]
        let tagged = RecordingItem(
            id: UUID(), title: "Звонок", appName: "Zoom", appBundleID: nil, startedAt: sample.startedAt,
            duration: 60, status: .ready, directory: nil, isSample: false, transcript: [], analysis: nil,
            tags: ["проект Альфа"]
        )

        #expect(LibrarySearch.filter([tagged], query: "альфа").map(\.id) == [tagged.id])
    }
}
