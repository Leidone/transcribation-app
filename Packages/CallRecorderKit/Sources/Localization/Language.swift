import Foundation
import os

/// The language the interface speaks. It is chosen once, when the app starts, from the languages the person set
/// in System Settings (or for this app alone, in System Settings → General → Language & Region → Applications):
/// the first of Russian and English in their list wins, and English is used when neither is there.
///
/// Every text of the interface is written in both languages next to each other, `tr("Итоги", "Summary")`, so a
/// missing translation is a compile-time matter, not a key that silently shows up on screen.
public enum Language: String, CaseIterable, Sendable {
    case russian = "ru"
    case english = "en"

    /// Russian until the app calls `adoptSystemLanguage()`: the texts were written in Russian first, and tests that
    /// never pick a language see them as written.
    public static var current: Language {
        state.withLock { $0 }
    }

    /// Makes `language` the interface language of this run.
    public static func use(_ language: Language) {
        state.withLock { $0 = language }
    }

    /// Picks the language from the system's list of preferred languages and uses it. Call once at launch, before
    /// any text is shown.
    @discardableResult
    public static func adoptSystemLanguage() -> Language {
        let language = resolve(preferredLanguages: Locale.preferredLanguages)
        use(language)
        return language
    }

    /// The first of the supported languages in the person's order of preference; English when none of them is
    /// there. Regional variants count as their language ("ru-KZ" is Russian, "en-GB" English).
    public static func resolve(preferredLanguages: [String]) -> Language {
        for identifier in preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
                ?? String(identifier.prefix(2)).lowercased()
            if let supported = Language(rawValue: code) { return supported }
        }
        return .english
    }

    /// For dates and numbers written in the interface language.
    public var locale: Locale {
        Locale(identifier: self == .russian ? "ru_RU" : "en_US")
    }

    private static let state = OSAllocatedUnfairLock(initialState: Language.russian)
}

/// The text in the interface language: `tr("Итоги", "Summary")`.
public func tr(_ russian: String, _ english: String) -> String {
    Language.current == .english ? english : russian
}

/// A count with the right form of the word: `plural(3, "задача", "задачи", "задач", "task", "tasks")` → "3 задачи".
public func plural(
    _ count: Int, _ one: String, _ few: String, _ many: String, _ englishOne: String, _ englishMany: String
) -> String {
    guard Language.current == .russian else { return "\(count) \(count == 1 ? englishOne : englishMany)" }
    let lastTwo = abs(count) % 100
    let last = abs(count) % 10
    let word: String
    if (11...14).contains(lastTwo) {
        word = many
    } else if last == 1 {
        word = one
    } else if (2...4).contains(last) {
        word = few
    } else {
        word = many
    }
    return "\(count) \(word)"
}
