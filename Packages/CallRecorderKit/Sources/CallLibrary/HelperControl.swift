import Foundation
import Observation

/// Something that holds one system-wide key combination (on the Mac, a Carbon hot key).
@MainActor
public protocol ShortcutRegistering: AnyObject {
    /// Takes `shortcut`, letting go of the one held before. `false` when the system refuses it.
    func register(_ shortcut: KeyShortcut) -> Bool
    func unregister()
}

/// Something that notices a call starting and offers to record it.
@MainActor
public protocol CallDetecting: AnyObject {
    var isEnabled: Bool { get set }
    /// Starts listening; calling it again changes nothing.
    func start()
}

/// The two system-wide combinations the app can hold.
public enum HelperShortcut: String, CaseIterable, Sendable {
    /// Starts and stops a recording from any app.
    case record
    /// Marks the current moment of a recording as important; held only while recording.
    case mark
}

/// Keeps the Mac's call helpers — the offer to record when a call starts, and the two key combinations — in step
/// with the settings. It follows the settings by itself: whatever changes a preference, the change reaches the
/// helpers without anyone having to remember to pass it on. (An earlier version relied on the settings screen to
/// do that, and a new recording shortcut silently did nothing until the app was restarted.)
@MainActor
public final class HelperControl {
    private let preferences: AppPreferences
    private let detector: any CallDetecting
    private let keys: [HelperShortcut: any ShortcutRegistering]

    /// The combinations held right now, by role.
    public private(set) var held: [HelperShortcut: KeyShortcut] = [:]
    /// While the person types a new combination, none is held, so pressing the old one does not act.
    public private(set) var isSuspended = false
    /// The mark combination is held only while a recording runs; outside a call it would only steal the keys.
    public var isRecording = false {
        didSet { if isRecording != oldValue { apply() } }
    }
    /// Told whenever a combination the settings ask for could not be taken.
    public var onRefused: ((HelperShortcut, KeyShortcut) -> Void)?

    private var isFollowing = false

    public init(
        preferences: AppPreferences, detector: any CallDetecting,
        recordKey: any ShortcutRegistering, markKey: any ShortcutRegistering
    ) {
        self.preferences = preferences
        self.detector = detector
        keys = [.record: recordKey, .mark: markKey]
    }

    /// What the settings ask to be held now.
    public var wanted: [HelperShortcut: KeyShortcut] {
        guard !isSuspended else { return [:] }
        var result: [HelperShortcut: KeyShortcut] = [:]
        if preferences.usesGlobalHotKey { result[.record] = preferences.recordShortcut }
        if preferences.usesMarkShortcut, isRecording, preferences.markShortcut != result[.record] {
            result[.mark] = preferences.markShortcut
        }
        return result
    }

    /// Brings the helpers in line with the settings. Returns the roles whose combination the system refused.
    @discardableResult
    public func apply() -> Set<HelperShortcut> {
        detector.isEnabled = preferences.suggestsRecordingOnCalls
        if preferences.suggestsRecordingOnCalls { detector.start() }

        let wanted = wanted
        var refused: Set<HelperShortcut> = []
        for role in HelperShortcut.allCases {
            guard let key = keys[role], held[role] != wanted[role] else { continue }
            guard let shortcut = wanted[role] else {
                key.unregister()
                held[role] = nil
                continue
            }
            if key.register(shortcut) {
                held[role] = shortcut
            } else {
                held[role] = nil
                refused.insert(role)
                onRefused?(role, shortcut)
            }
        }
        return refused
    }

    /// Lets go of every combination until `resume()`.
    public func suspend() {
        isSuspended = true
        apply()
    }

    public func resume() {
        isSuspended = false
        apply()
    }

    /// Applies the settings now and again after every change of the ones the helpers depend on.
    public func follow() {
        guard !isFollowing else { return }
        isFollowing = true
        apply()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = preferences.suggestsRecordingOnCalls
            _ = preferences.usesGlobalHotKey
            _ = preferences.recordShortcut
            _ = preferences.usesMarkShortcut
            _ = preferences.markShortcut
        } onChange: { [weak self] in
            // Called before the new value is stored; the next turn of the main actor sees it.
            Task { @MainActor in
                guard let self else { return }
                self.apply()
                self.observe()
            }
        }
    }
}
