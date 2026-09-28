import Foundation
import Testing
@testable import AudioCapture

struct SpeakerNamesTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "speakers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("a renamed speaker shows the new name, the others keep their label")
    func displayNames() {
        let names = SpeakerNames.empty.renaming("Собеседник 1", to: "Анна")

        #expect(names.displayName(for: "Собеседник 1") == "Анна")
        #expect(names.displayName(for: "Собеседник 2") == "Собеседник 2")
    }

    @Test("surrounding spaces are ignored")
    func trimming() {
        #expect(SpeakerNames.empty.renaming("Я", to: "  Александр \n").displayName(for: "Я") == "Александр")
    }

    @Test("an empty name or the original label takes the rename back")
    func takingBack() {
        let named = SpeakerNames.empty.renaming("Спикер 1", to: "Борис")

        #expect(named.renaming("Спикер 1", to: "").names.isEmpty)
        #expect(named.renaming("Спикер 1", to: "   ").names.isEmpty)
        #expect(named.renaming("Спикер 1", to: "Спикер 1").names.isEmpty)
    }

    @Test("renaming returns a copy and leaves the original alone")
    func immutability() {
        let original = SpeakerNames.empty.renaming("Спикер 1", to: "Борис")

        let updated = original.renaming("Спикер 2", to: "Вера")

        #expect(original.names == ["Спикер 1": "Борис"])
        #expect(updated.names == ["Спикер 1": "Борис", "Спикер 2": "Вера"])
    }

    @Test("saved names load back unchanged")
    func roundTrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = SpeakerNames.empty.renaming("Собеседник 1", to: "Анна").renaming("Я", to: "Александр")

        try SpeakerNamesStore.save(names, in: directory)

        #expect(try SpeakerNamesStore.load(from: directory) == names)
    }

    @Test("no file means no names")
    func missingFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try SpeakerNamesStore.load(from: directory) == .empty)
    }

    @Test("saving no names removes the file instead of leaving an empty one")
    func emptyRemovesFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try SpeakerNamesStore.save(SpeakerNames.empty.renaming("Я", to: "Саша"), in: directory)

        try SpeakerNamesStore.save(.empty, in: directory)

        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: SpeakerNamesStore.fileName).path))
    }

    @Test("a corrupt file is an error, not silently empty")
    func corruptFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ nope".utf8).write(to: directory.appending(path: SpeakerNamesStore.fileName))

        #expect(throws: DecodingError.self) { try SpeakerNamesStore.load(from: directory) }
    }
}
