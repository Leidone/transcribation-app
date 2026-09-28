import AudioCapture
import Foundation
import Testing
import Transcription
@testable import CallLibrary

private func temporaryLibrary() throws -> (library: URL, recording: URL) {
    let library = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID().uuidString)")
    let recording = library.appending(path: "2026-09-25_10-00-00")
    try FileManager.default.createDirectory(at: recording, withIntermediateDirectories: true)
    return (library, recording)
}

private func result(voices: [String: [Float]]) -> TranscriptionResult {
    TranscriptionResult(
        transcript: StoredTranscript(
            engine: "test", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            utterances: [
                Utterance(start: 0, end: 2, speaker: "Собеседник 1", text: "Привет"),
                Utterance(start: 3, end: 5, speaker: "Собеседник 2", text: "Здравствуйте"),
            ],
            processingSeconds: 1.5
        ),
        voiceprints: Voiceprints(voices: voices)
    )
}

@Test func aNamedVoiceIsRecognisedInTheNextTranscription() throws {
    let (library, first) = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: library) }

    try LibraryStore.saveTranscription(result(voices: ["Собеседник 1": [1, 0, 0]]), in: first, library: library)
    #expect(try LibraryStore.rememberVoice("Собеседник 1", as: "Анна", from: first, library: library) != nil)

    let second = library.appending(path: "2026-09-26_10-00-00")
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    let given = try LibraryStore.saveTranscription(
        result(voices: ["Собеседник 1": [0, 0, 1], "Собеседник 2": [0.98, 0.1, 0]]), in: second, library: library
    )

    #expect(given == ["Собеседник 2": "Анна"])
    #expect(try SpeakerNamesStore.load(from: second).names == ["Собеседник 2": "Анна"])
    #expect(try TranscriptStore.load(from: second)?.processingSeconds == 1.5)
}

@Test func aGuessNeverReplacesANameThePersonGave() throws {
    let (library, recording) = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: library) }
    try VoiceBookStore.save(VoiceBook.empty.remembering("Анна", embedding: [1, 0, 0]), in: library)
    try SpeakerNamesStore.save(SpeakerNames(names: ["Собеседник 1": "Катя"]), in: recording)

    try LibraryStore.saveTranscription(result(voices: ["Собеседник 1": [1, 0, 0]]), in: recording, library: library)

    #expect(try SpeakerNamesStore.load(from: recording).names == ["Собеседник 1": "Катя"])
}

@Test func nothingIsRememberedWithoutAVoiceprintOrAName() throws {
    let (library, recording) = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: library) }
    try LibraryStore.saveTranscription(result(voices: ["Собеседник 1": [1, 0, 0]]), in: recording, library: library)

    #expect(try LibraryStore.rememberVoice("Я", as: "Саша", from: recording, library: library) == nil)
    #expect(try LibraryStore.rememberVoice("Собеседник 1", as: "  ", from: recording, library: library) == nil)
    #expect(try VoiceBookStore.load(from: library) == .empty)
}

@Test func anEditKeepsTimingAndSpeaker() throws {
    let (library, recording) = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: library) }
    try LibraryStore.saveTranscription(result(voices: [:]), in: recording, library: library)
    let when = Date(timeIntervalSince1970: 1_790_000_100)

    try LibraryStore.saveEdit(lineID: 1, text: " Добрый день ", in: recording, at: when)

    let saved = try #require(try TranscriptStore.load(from: recording))
    #expect(saved.utterances[1] == Utterance(start: 3, end: 5, speaker: "Собеседник 2", text: "Добрый день"))
    #expect(saved.utterances[0].text == "Привет")
    #expect(saved.editedAt == when)
    #expect(saved.processingSeconds == 1.5)
}

@Test func transcriptsWrittenBeforeTheNewFieldsStillLoad() throws {
    let (library, recording) = try temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: library) }
    let old = #"{"createdAt":"2026-09-21T10:00:00Z","engine":"x","utterances":[{"end":1,"speaker":"Я","start":0,"text":"да"}],"version":1}"#
    try Data(old.utf8).write(to: recording.appending(path: TranscriptStore.fileName))

    let loaded = try #require(try TranscriptStore.load(from: recording))
    #expect(loaded.editedAt == nil)
    #expect(loaded.processingSeconds == nil)
    #expect(loaded.utterances.count == 1)
}
