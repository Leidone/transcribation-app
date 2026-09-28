import AppIntents
import CallLibrary
import Foundation
import Localization

/// The app's model as the intents see it. Intents run inside the app (macOS starts it first if needed); the
/// delegate sets this at launch.
@MainActor
enum IntentTarget {
    static weak var model: AppModel?
    static weak var lock: AppLock?
}

/// Starts recording the call app, as the recording shortcut does.
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Starts recording the call app and your microphone in Transcribation.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = IntentTarget.model else { return .result(dialog: Dialogs.notReady) }
        guard !model.isRecording else {
            return .result(dialog: Dialogs.text(tr("Запись уже идёт.", "Already recording.")))
        }
        model.refreshApps()
        await model.startRecording()
        guard model.isRecording else {
            let reason = model.errorMessage ?? tr("Запись не началась.", "The recording did not start.")
            return .result(dialog: Dialogs.text(reason))
        }
        let app = model.apps.first { $0.bundleID == model.selectedBundleID }?.name ?? ""
        return .result(dialog: Dialogs.text(tr("Запись началась: \(app).", "Recording \(app).")))
    }
}

/// Stops and saves the running recording; transcription starts by itself.
struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stops and saves the running recording in Transcribation.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = IntentTarget.model else { return .result(dialog: Dialogs.notReady) }
        guard model.isRecording else {
            return .result(dialog: Dialogs.text(tr("Сейчас ничего не записывается.", "Nothing is being recorded.")))
        }
        await model.stopRecording()
        return .result(dialog: Dialogs.text(tr(
            "Запись сохранена, расшифровка началась.", "The recording is saved and is being transcribed."
        )))
    }
}

/// Marks the current moment of the running recording as important.
struct MarkImportantIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Important Moment"
    static let description = IntentDescription("Marks the current moment of the running recording as important.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = IntentTarget.model else { return .result(dialog: Dialogs.notReady) }
        guard model.isRecording else {
            return .result(dialog: Dialogs.text(tr("Сейчас ничего не записывается.", "Nothing is being recorded.")))
        }
        await model.markImportant()
        return .result(dialog: Dialogs.text(tr("Отмечено.", "Marked.")))
    }
}

/// Reads out the summary of the latest meeting that has one, and returns it for use in a shortcut.
struct LastMeetingSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Last Meeting Summary"
    static let description = IntentDescription("Returns the summary, decisions and tasks of your latest summarised meeting.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let model = IntentTarget.model else { return .result(value: "", dialog: Dialogs.notReady) }
        // Protected recordings are read out only after the same Touch ID the window asks for.
        if let lock = IntentTarget.lock, lock.isLocked, !(await lock.unlock()) {
            let locked = tr("Записи защищены Touch ID.", "Your recordings are protected with Touch ID.")
            return .result(value: "", dialog: Dialogs.text(locked))
        }
        if !model.hasLoadedLibraryOnce { await model.reload() }
        guard let text = LastMeetingSummary.text(from: model.recordings) else {
            let none = tr("Итогов пока нет: сначала получите итоги встречи.", "No summary yet: summarise a meeting first.")
            return .result(value: "", dialog: Dialogs.text(none))
        }
        return .result(value: text.full, dialog: Dialogs.text(text.spoken))
    }
}

struct TranscribationShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: ["Start recording in \(.applicationName)", "Record the call in \(.applicationName)"],
            shortTitle: "Start Recording", systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: ["Stop recording in \(.applicationName)"],
            shortTitle: "Stop Recording", systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: LastMeetingSummaryIntent(),
            phrases: ["Last meeting summary in \(.applicationName)", "What was decided in \(.applicationName)"],
            shortTitle: "Last Meeting Summary", systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: MarkImportantIntent(),
            phrases: ["Mark this moment in \(.applicationName)"],
            shortTitle: "Mark Important Moment", systemImageName: "star"
        )
    }
}

private enum Dialogs {
    static var notReady: IntentDialog {
        text(tr("Transcribation ещё запускается, попробуйте через пару секунд.", "Transcribation is still starting, try again in a moment."))
    }

    static func text(_ text: String) -> IntentDialog {
        IntentDialog(LocalizedStringResource(stringLiteral: text))
    }
}
