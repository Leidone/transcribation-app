import Foundation
import Testing
@testable import CallLibrary

private func shortcut(_ modifiers: Set<KeyShortcut.Modifier>, _ name: String, code: UInt32 = 15) -> KeyShortcut {
    KeyShortcut(keyCode: code, modifiers: modifiers, keyName: name)
}

@Test func modifiersArePrintedInTheMacOrder() {
    #expect(KeyShortcut.defaultRecordToggle.display == "⌃⌥⌘R")
    #expect(shortcut([.command, .shift, .option, .control], "K").display == "⌃⌥⇧⌘K")
    #expect(shortcut([.option], "R").display == "⌥R")
}

@Test(arguments: [
    shortcut([.option], "R"), shortcut([.control], "R"), shortcut([.control, .shift], "R"),
    shortcut([.command, .option], "R"), shortcut([], "F5", code: 96), shortcut([.command], "F12", code: 111),
])
func shortCombinationsThatDoNotStealTypingAreAllowed(candidate: KeyShortcut) {
    #expect(candidate.problem == nil)
}

@Test(arguments: [
    shortcut([], "R"), shortcut([.shift], "R"), shortcut([.command], "C", code: 8), shortcut([.command, .shift], "R"),
])
func combinationsThatWouldBreakOtherAppsAreRefused(candidate: KeyShortcut) {
    #expect(candidate.problem != nil)
}

@Test func functionKeysAreRecognisedByName() {
    #expect(shortcut([], "F5").isFunctionKey)
    #expect(shortcut([], "F12").isFunctionKey)
    #expect(!shortcut([], "F").isFunctionKey)
    #expect(!shortcut([], "R").isFunctionKey)
    #expect(!shortcut([], "FX").isFunctionKey)
}

@MainActor
@Test func theChosenShortcutIsRemembered() throws {
    let suite = "shortcut-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(AppPreferences(defaults: defaults).recordShortcut == .defaultRecordToggle)
    AppPreferences(defaults: defaults).recordShortcut = shortcut([.option], "R")
    #expect(AppPreferences(defaults: defaults).recordShortcut == shortcut([.option], "R"))
}
