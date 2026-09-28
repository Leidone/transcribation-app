import AudioCapture
import Foundation
import Testing
@testable import CallLibrary

private func item(
    title: String = "Weekly по релизу",
    lines: [(String, String)] = [("Анна", "Всем привет, начинаем weekly по релизу."), ("Борис", "Бюджет утвердили ещё вчера.")],
    summary: String? = "Обсудили сроки релиза.",
    tasks: [TaskItem] = [],
    names: [String: String] = [:]
) -> RecordingItem {
    RecordingItem(
        id: UUID(), title: title, appName: "Zoom", appBundleID: nil,
        startedAt: Date(timeIntervalSince1970: 1_790_000_000), duration: 125, status: .ready, directory: nil,
        isSample: false,
        transcript: lines.enumerated().map {
            TranscriptLine(id: $0.offset, time: Double($0.offset * 30), speaker: $0.element.0, isMe: false, text: $0.element.1)
        },
        analysis: summary.map { AnalysisResult(summary: $0, decisions: ["Релиз в пятницу"], tasks: tasks) },
        speakerNames: SpeakerNames(names: names)
    )
}

private func task(_ title: String, owner: String? = nil, due: String? = nil, done: Bool = false) -> TaskItem {
    TaskItem(id: UUID(), title: title, owner: owner, due: due, quote: nil, timestamp: nil, isDone: done)
}

// MARK: Search

@Test func anEmptyQueryKeepsEverything() {
    let all = [item(), item(title: "Другое")]
    #expect(LibrarySearch.filter(all, query: "   ") == all)
}

@Test func searchIgnoresCaseAndYo() {
    let recording = item(lines: [("Анна", "Всё решили, ЕЩЁ созвонимся")])
    #expect(LibrarySearch.filter([recording], query: "еще").count == 1)
    #expect(LibrarySearch.filter([recording], query: "всё РЕШИЛИ").count == 1)
}

@Test func everyWordMustOccurSomewhereInTheRecording() {
    let recording = item()
    #expect(LibrarySearch.filter([recording], query: "бюджет релиз").count == 1)
    #expect(LibrarySearch.filter([recording], query: "бюджет отпуск").isEmpty)
}

@Test func searchFindsGivenSpeakerNamesAndTaskOwners() {
    let recording = item(tasks: [task("Проверить тесты", owner: "Собеседник 2")], names: ["Собеседник 1": "Катя"])
    #expect(LibrarySearch.filter([recording], query: "катя").count == 1)
    #expect(LibrarySearch.filter([recording], query: "собеседник 2").count == 1)
}

@Test func hitsPointAtTheTranscriptMoment() throws {
    let hits = LibrarySearch.hits(in: item(), query: "бюджет")
    let hit = try #require(hits.first)
    #expect(hit.place == .transcript(lineID: 1, time: 30))
    #expect(hit.snippet.contains("Бюджет утвердили"))
}

@Test func snippetsAreCutAtWordsButNeverThroughTheMatch() {
    let long = String(repeating: "слово ", count: 30) + "ключевое" + String(repeating: " хвост", count: 30)
    let range = long.range(of: "ключевое")!
    let snippet = LibrarySearch.snippet(of: long, around: range)
    #expect(snippet.contains("ключевое"))
    #expect(snippet.hasPrefix("…слово"))
    #expect(snippet.hasSuffix("хвост…"))

    let glued = String(repeating: "а", count: 60) + "ключ" + String(repeating: "б", count: 60)
    #expect(LibrarySearch.snippet(of: glued, around: glued.range(of: "ключ")!).contains("ключ"))
}

// MARK: Export

@Test func markdownHasTheSummaryTasksAndTranscriptWithGivenNames() {
    let recording = item(tasks: [task("Проверить тесты", owner: "Анна", due: "до среды"), task("Готово", done: true)], names: ["Анна": "Аня"])
    let text = RecordingExport.markdown(of: recording)

    #expect(text.hasPrefix("# Weekly по релизу\n"))
    #expect(text.contains("## Итоги\n\nОбсудили сроки релиза."))
    #expect(text.contains("- Релиз в пятницу"))
    #expect(text.contains("- [ ] Проверить тесты — Аня, срок: до среды"))
    #expect(text.contains("- [x] Готово"))
    #expect(text.contains("**0:00 Аня:** Всем привет"))
}

@Test func markdownCanLeaveTheTranscriptOut() {
    let text = RecordingExport.markdown(of: item(), options: .init(includesTranscript: false))
    #expect(!text.contains("Расшифровка"))
    #expect(text.contains("Итоги"))
}

@Test func htmlEscapesWhatPeopleSaid() {
    let recording = item(lines: [("Анна", "<script>alert(1)</script> & \"цитата\"")], summary: nil)
    let html = RecordingExport.html(of: recording)
    #expect(!html.contains("<script>"))
    #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;цитата&quot;"))
}

@Test func fileNamesLoseCharactersFileSystemsReject() {
    #expect(RecordingExport.fileName(of: item(title: "Q3: план/бюджет?"), extension: "md") == "Q3 план бюджет.md")
    #expect(RecordingExport.fileName(of: item(title: "///"), extension: "pdf") == "Запись.pdf")
}

// MARK: Voices

private let anna: [Float] = [1, 0, 0, 0]
private let boris: [Float] = [0, 1, 0, 0]

@Test func aRememberedVoiceIsNamedInTheNextRecording() {
    let book = VoiceBook.empty.remembering("Анна", embedding: anna)
    let names = book.names(for: ["Собеседник 1": [0.95, 0.1, 0, 0], "Собеседник 2": [0, 0, 1, 0]])
    #expect(names == ["Собеседник 1": "Анна"])
}

@Test func twoVoicesNeverGetTheSameName() {
    let book = VoiceBook.empty.remembering("Анна", embedding: anna)
    let names = book.names(for: ["Собеседник 1": [0.99, 0.05, 0, 0], "Собеседник 2": [0.97, 0.1, 0, 0]])
    #expect(names == ["Собеседник 1": "Анна"])
}

@Test func theClosestPairsWinWhenPeopleCompete() {
    let book = VoiceBook.empty.remembering("Анна", embedding: anna).remembering("Борис", embedding: boris)
    let names = book.names(for: ["Собеседник 1": [0.2, 1, 0, 0], "Собеседник 2": [1, 0.3, 0, 0]])
    #expect(names == ["Собеседник 1": "Борис", "Собеседник 2": "Анна"])
}

@Test func rememberingTheSameNameRefinesOneProfile() throws {
    let book = VoiceBook.empty.remembering("Анна", embedding: anna).remembering(" анна ", embedding: [0, 1, 0, 0])
    let profile = try #require(book.profiles.first)
    #expect(book.profiles.count == 1)
    #expect(profile.samples == 2)
    #expect(abs(profile.embedding[0] - profile.embedding[1]) < 0.0001)
    #expect(abs(profile.embedding.reduce(0) { $0 + $1 * $1 } - 1) < 0.0001)
}

@Test func unusableInputChangesNothing() {
    let book = VoiceBook.empty.remembering("Анна", embedding: anna)
    #expect(book.remembering("   ", embedding: boris) == book)
    #expect(book.remembering("Борис", embedding: [0, 0, 0, 0]) == book)
    #expect(book.remembering("Анна", embedding: [1, 0]) == book)
    #expect(VoiceBook.distance(anna, [1, 0]) == .infinity)
}

@Test func forgettingRemovesOnlyThatPerson() throws {
    let book = VoiceBook.empty.remembering("Анна", embedding: anna).remembering("Борис", embedding: boris)
    let first = try #require(book.profiles.first)
    #expect(book.forgetting(first.id).profiles.map(\.name) == ["Борис"])
}

@Test func theVoiceBookSurvivesARoundTripOnDisk() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "voicebook-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(try VoiceBookStore.load(from: folder) == .empty)
    let book = VoiceBook.empty.remembering("Анна", embedding: anna, at: Date(timeIntervalSince1970: 1_790_000_000))
    try VoiceBookStore.save(book, in: folder)
    #expect(try VoiceBookStore.load(from: folder) == book)
}

// MARK: Deadlines

@Test func exactDatesBecomeDueDates() {
    #expect(TaskDueDate.components(from: "2026-09-30") == DateComponents(year: 2026, month: 9, day: 30))
    #expect(TaskDueDate.components(from: "2026-09-30T14:05") == DateComponents(year: 2026, month: 9, day: 30, hour: 14, minute: 5))
}

@Test(arguments: [nil, "", "до среды", "30.09.2026", "2026-02-30", "2026-13-01", "2026-09-30T25:00"])
func wordsAndImpossibleDatesStayText(due: String?) {
    #expect(TaskDueDate.components(from: due) == nil)
}

@Test func aReminderNoteKeepsWhatDidNotBecomeADate() {
    let note = RemindersExporter.note(for: task("Позвонить", owner: "Анна", due: "до среды"), in: item(names: ["Анна": "Аня"]))
    #expect(note.contains("Из записи «Weekly по релизу»"))
    #expect(note.contains("Исполнитель: Аня"))
    #expect(note.contains("Срок: до среды"))
}
