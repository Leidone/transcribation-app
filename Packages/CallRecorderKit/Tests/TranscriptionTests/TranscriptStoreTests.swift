import Foundation
import Testing
@testable import Transcription

struct TranscriptStoreTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transcript-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private let transcript = StoredTranscript(
        engine: "parakeet-tdt-v3",
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        utterances: [
            Utterance(start: 0, end: 2.5, speaker: "Собеседник 1", text: "Добрый день"),
            Utterance(start: 3, end: 4, speaker: "Я", text: "Здравствуйте"),
        ]
    )

    @Test("a saved transcript loads back unchanged")
    func roundTrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try TranscriptStore.save(transcript, in: directory)

        #expect(try TranscriptStore.load(from: directory) == transcript)
    }

    @Test("a recording without a transcript loads as nil")
    func missingFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try TranscriptStore.load(from: directory) == nil)
    }

    @Test("a corrupt file is an error, not an empty transcript")
    func corruptFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ not json".utf8).write(to: directory.appending(path: TranscriptStore.fileName))

        #expect(throws: DecodingError.self) { try TranscriptStore.load(from: directory) }
    }

    @Test("saving again replaces the previous transcript")
    func overwrite() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try TranscriptStore.save(transcript, in: directory)
        let updated = StoredTranscript(engine: "other", createdAt: transcript.createdAt, utterances: [])

        try TranscriptStore.save(updated, in: directory)

        #expect(try TranscriptStore.load(from: directory) == updated)
    }
}
