import CodexClient
import Foundation
import Testing
@testable import CallLibrary

// Every setting must reach the part of the app it controls, and must survive a restart. These tests stand in for
// the Mac's real hot keys and call detector with fakes that record what they were told.

@MainActor
private final class FakeKey: ShortcutRegistering {
    private(set) var held: KeyShortcut?
    private(set) var registrations = 0
    /// Combinations the "system" refuses, as when another app holds them.
    var refused: Set<KeyShortcut> = []

    func register(_ shortcut: KeyShortcut) -> Bool {
        registrations += 1
        guard !refused.contains(shortcut) else {
            held = nil
            return false
        }
        held = shortcut
        return true
    }

    func unregister() {
        held = nil
    }
}

@MainActor
private final class FakeDetector: CallDetecting {
    var isEnabled = false
    private(set) var starts = 0

    func start() {
        starts += 1
    }
}

@MainActor
private final class Rig {
    let preferences: AppPreferences
    let detector: FakeDetector
    let recordKey: FakeKey
    let markKey: FakeKey
    let control: HelperControl

    init(defaults: UserDefaults) {
        preferences = AppPreferences(defaults: defaults)
        detector = FakeDetector()
        recordKey = FakeKey()
        markKey = FakeKey()
        control = HelperControl(preferences: preferences, detector: detector, recordKey: recordKey, markKey: markKey)
    }
}

private func freshDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "wiring-test-\(UUID().uuidString)"))
}

/// Waits (up to a second) for a change that arrives on a later turn of the main actor.
@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<100 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

private let optionR = KeyShortcut(keyCode: 15, modifiers: [.option], keyName: "R")
private let controlF5 = KeyShortcut(keyCode: 96, modifiers: [.control], keyName: "F5")

// MARK: The helpers follow the settings by themselves

@MainActor
@Test func theRecordingShortcutIsHeldFromTheStart() throws {
    let rig = Rig(defaults: try freshDefaults())
    rig.control.follow()
    #expect(rig.recordKey.held == .defaultRecordToggle)
    #expect(rig.detector.isEnabled)
    #expect(rig.detector.starts >= 1)
}

@MainActor
@Test func aNewRecordingShortcutIsTakenWithoutARestart() async throws {
    let rig = Rig(defaults: try freshDefaults())
    rig.control.follow()
    rig.preferences.recordShortcut = optionR
    try await eventually { rig.recordKey.held == optionR }
}

@MainActor
@Test func turningTheShortcutOffLetsItGo() async throws {
    let rig = Rig(defaults: try freshDefaults())
    rig.control.follow()
    rig.preferences.usesGlobalHotKey = false
    try await eventually { rig.recordKey.held == nil }
    rig.preferences.usesGlobalHotKey = true
    try await eventually { rig.recordKey.held == .defaultRecordToggle }
}

@MainActor
@Test func theCallOfferFollowsItsSwitch() async throws {
    let rig = Rig(defaults: try freshDefaults())
    rig.control.follow()
    rig.preferences.suggestsRecordingOnCalls = false
    try await eventually { !rig.detector.isEnabled }
    rig.preferences.suggestsRecordingOnCalls = true
    try await eventually { rig.detector.isEnabled }
}

@MainActor
@Test func theMarkShortcutIsHeldOnlyWhileRecording() async throws {
    let rig = Rig(defaults: try freshDefaults())
    rig.control.follow()
    #expect(rig.markKey.held == nil)
    rig.control.isRecording = true
    #expect(rig.markKey.held == .defaultMarkImportant)
    rig.preferences.markShortcut = controlF5
    try await eventually { rig.markKey.held == controlF5 }
    rig.control.isRecording = false
    #expect(rig.markKey.held == nil)
}

@MainActor
@Test func theMarkShortcutIsNotTakenWhenItEqualsTheRecordingOne() throws {
    let rig = Rig(defaults: try freshDefaults())
    rig.preferences.markShortcut = .defaultRecordToggle
    rig.control.isRecording = true
    rig.control.apply()
    #expect(rig.recordKey.held == .defaultRecordToggle)
    #expect(rig.markKey.held == nil)
}

@MainActor
@Test func aRefusedShortcutIsReportedAndTheOldOneCanComeBack() throws {
    let rig = Rig(defaults: try freshDefaults())
    var reported: [HelperShortcut] = []
    rig.control.onRefused = { role, _ in reported.append(role) }
    rig.control.apply()
    rig.recordKey.refused = [optionR]
    rig.preferences.recordShortcut = optionR
    #expect(rig.control.apply() == [.record])
    #expect(reported == [.record])
    #expect(rig.recordKey.held == nil)
    rig.preferences.recordShortcut = .defaultRecordToggle
    #expect(rig.control.apply().isEmpty)
    #expect(rig.recordKey.held == .defaultRecordToggle)
}

@MainActor
@Test func nothingIsHeldWhileANewShortcutIsBeingTyped() throws {
    let rig = Rig(defaults: try freshDefaults())
    rig.control.isRecording = true
    rig.control.apply()
    rig.control.suspend()
    #expect(rig.recordKey.held == nil)
    #expect(rig.markKey.held == nil)
    rig.control.resume()
    #expect(rig.recordKey.held == .defaultRecordToggle)
    #expect(rig.markKey.held == .defaultMarkImportant)
}

@MainActor
@Test func anUnchangedShortcutIsNotTakenAgain() throws {
    let rig = Rig(defaults: try freshDefaults())
    rig.control.apply()
    rig.control.apply()
    rig.control.apply()
    #expect(rig.recordKey.registrations == 1)
}

// MARK: Settings survive a restart

@MainActor
@Test func everyPreferenceSurvivesARestart() throws {
    let defaults = try freshDefaults()
    let first = AppPreferences(defaults: defaults)
    first.hasCompletedOnboarding = true
    first.suggestsRecordingOnCalls = false
    first.usesGlobalHotKey = false
    first.recordShortcut = optionR
    first.showsSamples = false
    first.compressesAudio = false
    first.stopsWhenCallEnds = false
    first.usesCalendar = true
    first.usesMarkShortcut = false
    first.markShortcut = controlF5
    first.indexesInSpotlight = false
    first.transcribesLive = true

    let second = AppPreferences(defaults: defaults)
    #expect(second.hasCompletedOnboarding)
    #expect(!second.suggestsRecordingOnCalls)
    #expect(!second.usesGlobalHotKey)
    #expect(second.recordShortcut == optionR)
    #expect(!second.showsSamples)
    #expect(!second.compressesAudio)
    #expect(!second.stopsWhenCallEnds)
    #expect(second.usesCalendar)
    #expect(!second.usesMarkShortcut)
    #expect(second.markShortcut == controlF5)
    #expect(!second.indexesInSpotlight)
    #expect(second.transcribesLive)
}

@MainActor
@Test func aFreshInstallStartsWithTheDocumentedDefaults() throws {
    let preferences = AppPreferences(defaults: try freshDefaults())
    #expect(!preferences.hasCompletedOnboarding)
    #expect(preferences.suggestsRecordingOnCalls)
    #expect(preferences.usesGlobalHotKey)
    #expect(preferences.recordShortcut == .defaultRecordToggle)
    #expect(preferences.showsSamples)
    #expect(preferences.compressesAudio)
    #expect(preferences.stopsWhenCallEnds)
    #expect(!preferences.usesCalendar)
    #expect(preferences.usesMarkShortcut)
    #expect(preferences.markShortcut == .defaultMarkImportant)
    #expect(preferences.indexesInSpotlight)
    #expect(!preferences.transcribesLive)
}

@MainActor
@Test func aiSettingsSurviveARestart() throws {
    let defaults = try freshDefaults()
    let first = AISettings(defaults: defaults)
    first.provider = ProviderSettings(kind: .anthropic, customName: "", customBaseURL: "", claudeModel: "claude-x")
    first.defaultTemplate = .standup
    first.prompt.effort = .high
    first.prompt.instructions = "Short."

    let second = AISettings(defaults: defaults)
    #expect(second.provider.kind == .anthropic)
    #expect(second.selectedModel == "claude-x")
    #expect(second.defaultTemplate == .standup)
    #expect(second.prompt.effort == .high)
    #expect(second.prompt.instructions == "Short.")
}
