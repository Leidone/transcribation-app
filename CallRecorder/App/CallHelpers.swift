import CallLibrary
import Localization
import Observation
import os

private let helpersLog = Logger(subsystem: "app.callrecorder.dev", category: "call-helpers")

/// The Mac's call helpers — the offer to record when a call starts, the recording shortcut and the shortcut that
/// marks an important moment. `HelperControl` (in the shared package, where tests check it) keeps them in step with
/// the settings by itself; this class only supplies the real hot keys and the call detector. Views reach it through
/// the environment: under SwiftUI, `NSApp.delegate` is SwiftUI's own object, not `AppDelegate`.
@Observable
@MainActor
final class CallHelpers {
    @ObservationIgnored private let control: HelperControl

    init(
        preferences: AppPreferences,
        onCallStarted: @escaping (_ bundleID: String, _ appName: String) -> Void,
        onRecordShortcut: @escaping @MainActor () -> Void,
        onMarkShortcut: @escaping @MainActor () -> Void
    ) {
        let detector = CallDetector()
        detector.onCallStarted = onCallStarted
        control = HelperControl(
            preferences: preferences, detector: detector,
            recordKey: GlobalHotKey(action: onRecordShortcut), markKey: GlobalHotKey(action: onMarkShortcut)
        )
        control.onRefused = { role, shortcut in
            helpersLog.error("the \(role.rawValue, privacy: .public) shortcut \(shortcut.display, privacy: .public) was refused")
        }
    }

    /// Starts following the settings; from then on every change reaches the helpers by itself.
    func start() {
        control.follow()
        helpersLog.notice("helpers follow the settings; held: \(self.heldDescription, privacy: .public)")
    }

    /// Applies the settings now. Returns the roles whose combination macOS refused.
    @discardableResult
    func apply() -> Set<HelperShortcut> {
        let refused = control.apply()
        helpersLog.notice("helpers applied; held: \(self.heldDescription, privacy: .public)")
        return refused
    }

    /// Lets go of both shortcuts while a new one is being typed, so pressing an old one does nothing.
    func suspendShortcuts() {
        control.suspend()
    }

    func resumeShortcuts() {
        control.resume()
    }

    /// The mark shortcut is held only while recording.
    func recordingChanged(_ isRecording: Bool) {
        control.isRecording = isRecording
    }

    private var heldDescription: String {
        let held = control.held.map { "\($0.key.rawValue)=\($0.value.display)" }.sorted()
        return held.isEmpty ? "none" : held.joined(separator: ", ")
    }
}

extension CallDetector: CallDetecting {}
extension GlobalHotKey: ShortcutRegistering {}
