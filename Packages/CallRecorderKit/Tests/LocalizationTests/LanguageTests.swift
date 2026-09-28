import Foundation
import Testing
@testable import Localization

@Test(arguments: [
    (["ru-RU", "en-US"], Language.russian),
    (["en-GB", "ru"], Language.english),
    (["de-DE", "ru-KZ", "en"], Language.russian),
    (["uk-UA", "en-US"], Language.english),
    (["fr-FR", "de"], Language.english),
    ([], Language.english),
    (["zh-Hans-CN", "ru"], Language.russian),
])
func theFirstSupportedPreferredLanguageWins(preferred: [String], expected: Language) {
    #expect(Language.resolve(preferredLanguages: preferred) == expected)
}

@Test func russianCountsTakeTheRightForm() {
    #expect(plural(1, "задача", "задачи", "задач", "task", "tasks") == "1 задача")
    #expect(plural(3, "задача", "задачи", "задач", "task", "tasks") == "3 задачи")
    #expect(plural(5, "задача", "задачи", "задач", "task", "tasks") == "5 задач")
    #expect(plural(11, "задача", "задачи", "задач", "task", "tasks") == "11 задач")
    #expect(plural(21, "задача", "задачи", "задач", "task", "tasks") == "21 задача")
    #expect(plural(112, "задача", "задачи", "задач", "task", "tasks") == "112 задач")
}

@Test func textsAreRussianUntilTheAppPicksALanguage() {
    // Nothing in the tests calls `adoptSystemLanguage()`, so the texts read as written.
    #expect(Language.current == .russian)
    #expect(tr("Итоги", "Summary") == "Итоги")
}
