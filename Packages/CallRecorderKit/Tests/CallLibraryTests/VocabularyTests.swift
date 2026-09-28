import Foundation
import Testing
import Transcription
@testable import CallLibrary

struct VocabularyTests {
    @Test("a heard word becomes the written one, whatever its case, and only as a whole word")
    func replacesWholeWords() {
        let vocabulary = Vocabulary(rules: [.init(heard: "эквайринг", written: "эквайринг Сбера")])

        #expect(vocabulary.apply(to: "Эквайринг готов") == "эквайринг Сбера готов")
        #expect(vocabulary.apply(to: "эквайринга нет") == "эквайринга нет", "part of a longer word stays")
    }

    @Test("names and terms in Latin letters are fixed too, several in one line")
    func severalRules() {
        let vocabulary = Vocabulary(rules: [
            .init(heard: "джира", written: "Jira"),
            .init(heard: "анна шульц", written: "Анна Шульц"),
        ])

        #expect(vocabulary.apply(to: "анна шульц заведёт задачу в джира") == "Анна Шульц заведёт задачу в Jira")
    }

    @Test("a longer phrase wins over a word inside it")
    func longerPhraseFirst() {
        let vocabulary = Vocabulary(rules: [
            .init(heard: "релиз", written: "Release"),
            .init(heard: "релиз два четыре", written: "релиз 2.4"),
        ])

        #expect(vocabulary.apply(to: "релиз два четыре в пятницу") == "релиз 2.4 в пятницу")
    }

    @Test("empty rules and special characters change nothing unexpected")
    func emptyAndSpecial() {
        let vocabulary = Vocabulary(rules: [.init(heard: "  ", written: "x"), .init(heard: "c++", written: "C++")])

        #expect(vocabulary.apply(to: "пишем на c++ и c") == "пишем на C++ и c")
        #expect(Vocabulary(rules: []).apply(to: "как есть") == "как есть")
    }

    @Test("a saved transcript is fixed in place, marked as edited, and a second pass changes nothing")
    func fixesASavedTranscript() throws {
        // Arrange
        let folder = FileManager.default.temporaryDirectory.appending(path: "vocabulary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let utterances = [
            Utterance(start: 0, end: 2, speaker: "Я", text: "заведи в джира"),
            Utterance(start: 2, end: 4, speaker: "Собеседник 1", text: "хорошо"),
        ]
        try TranscriptStore.save(StoredTranscript(engine: "test", createdAt: Date(), utterances: utterances), in: folder)
        let vocabulary = Vocabulary(rules: [.init(heard: "джира", written: "Jira")])

        // Act
        let changed = try LibraryStore.applyVocabulary(vocabulary, in: folder, at: Date(timeIntervalSince1970: 1_800_000_000))
        let again = try LibraryStore.applyVocabulary(vocabulary, in: folder)

        // Assert
        let saved = try #require(try TranscriptStore.load(from: folder))
        #expect(changed)
        #expect(!again)
        #expect(saved.utterances.map(\.text) == ["заведи в Jira", "хорошо"])
        #expect(saved.utterances[0].end == 2, "timing stays as recognised")
        #expect(saved.editedAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test("the rules survive a restart")
    @MainActor
    func rulesArePersisted() throws {
        let suite = "vocabulary-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        AppPreferences(defaults: defaults).vocabulary = Vocabulary(rules: [.init(heard: "джира", written: "Jira")])

        #expect(AppPreferences(defaults: defaults).vocabulary.rules == [.init(heard: "джира", written: "Jira")])
    }
}
