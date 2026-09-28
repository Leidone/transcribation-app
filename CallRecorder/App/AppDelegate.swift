import AppKit
import AudioCapture
import CallLibrary
import Localization
import UserNotifications

/// Dock icon only while the main window is open; a menu bar agent otherwise.
@MainActor
enum DockPresence {
    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func hide() {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model: AppModel
    let settings: AISettings
    let account: CodexAccountModel
    let preferences: AppPreferences
    let reporter: ProblemReporter
    let lock: AppLock
    let updater = Updater()

    private(set) var helpers: CallHelpers!

    private nonisolated static let callCategory = "call-started"
    private nonisolated static let recordAction = "record"
    private nonisolated static let bundleIDKey = "bundleID"
    private nonisolated static let callEndedCategory = "call-ended"
    private nonisolated static let stopAction = "stop"

    override init() {
        // Before any text is made: the interface language follows the system's, and stays for this run.
        Language.adoptSystemLanguage()
        let settings = AISettings()
        let preferences = AppPreferences()
        self.settings = settings
        self.preferences = preferences
        account = CodexAccountModel(settings: settings)
        model = AppModel(preferences: preferences)
        reporter = ProblemReporter(model: model, settings: settings, preferences: preferences)
        lock = AppLock(preferences: preferences)
        super.init()
        IntentTarget.model = model
        IntentTarget.lock = lock
        helpers = CallHelpers(
            preferences: preferences,
            onCallStarted: { [weak self] bundleID, name in self?.offerRecording(bundleID: bundleID, appName: name) },
            onRecordShortcut: { [weak self] in
                guard let self else { return }
                Task { await self.model.toggleRecording() }
            },
            onMarkShortcut: { [weak self] in
                guard let self else { return }
                Task { await self.model.markImportant() }
            }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The library follows the folder for the whole life of the app, also with the window closed.
        Task { await model.watchLibrary() }
        setUpNotifications()
        model.onRecordingChanged = { [weak self] isRecording in self?.helpers.recordingChanged(isRecording) }
        helpers.start()
        lock.start()
        model.followPreferences()
        model.onCallEnded = { [weak self] ending, appName, stopped in
            self?.tellCallEnded(ending, appName: appName, stopped: stopped)
        }
        model.onOthersNotHeard = { [weak self] appName in self?.tellOthersNotHeard(appName: appName) }
    }

    /// A Spotlight hit on a recording opens it.
    func application(
        _ application: NSApplication, continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard let id = SpotlightIndex.recordingID(from: userActivity) else { return false }
        Task {
            if !model.hasLoadedLibraryOnce { await model.reload() }
            model.open(id)
            DockPresence.show()
            model.openMainWindow?()
        }
        return true
    }

    /// Closing the window must not end the app: recording and the menu bar item keep running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isRecording else {
            account.shutdown()
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = tr("Идёт запись", "Recording in progress")
        alert.informativeText = tr("Остановить запись, сохранить её и выйти?", "Stop the recording, save it and quit?")
        alert.addButton(withTitle: tr("Остановить и выйти", "Stop and Quit"))
        alert.addButton(withTitle: tr("Отмена", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        Task {
            await model.stopRecording()
            account.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Call offers

    private func setUpNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let record = UNNotificationAction(identifier: Self.recordAction, title: tr("Записать", "Record"), options: [])
        let stop = UNNotificationAction(identifier: Self.stopAction, title: tr("Остановить запись", "Stop Recording"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.callCategory, actions: [record], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.callEndedCategory, actions: [stop], intentIdentifiers: []),
        ])
    }

    /// The recording runs, but nothing comes from the call app: most often another app was chosen by mistake.
    private func tellOthersNotHeard(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("Не слышно собеседников", "The other side is not heard")
        content.body = tr(
            "Из \(appName) за полминуты не пришло ни звука. Если разговор уже идёт, проверьте, что выбрано нужное приложение.",
            "Not a sound from \(appName) in half a minute. If the call is already going, check that the right app is chosen."
        )
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(UNNotificationRequest(identifier: "others-not-heard", content: content, trigger: nil))
        }
    }

    /// Says that the recording was stopped because the call ended, or asks whether to stop it.
    private func tellCallEnded(_ ending: CallEndWatch.Ending, appName: String, stopped: Bool) {
        let content = UNMutableNotificationContent()
        switch (ending, stopped) {
        case (.appQuit, _):
            content.title = tr("\(appName) закрыт — запись сохранена", "\(appName) closed — recording saved")
            content.body = tr("Расшифровка уже началась.", "Transcription has already started.")
        case (.callFinished, true):
            content.title = tr("Звонок закончился — запись сохранена", "The call ended — recording saved")
            content.body = tr("Расшифровка уже началась.", "Transcription has already started.")
        case (.longSilence, true):
            content.title = tr("Запись остановлена после 15 минут тишины", "Recording stopped after 15 minutes of silence")
            content.body = tr("Всё записанное сохранено, расшифровка уже началась.", "Everything recorded is saved; transcription has already started.")
        case (.callFinished, false), (.longSilence, false):
            content.title = ending == .callFinished ? tr("Похоже, звонок закончился", "The call seems to have ended") : tr("Уже 15 минут тишина", "15 minutes of silence")
            content.body = tr("Запись всё ещё идёт. Остановить её?", "Still recording. Stop it?")
            content.categoryIdentifier = Self.callEndedCategory
        }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(UNNotificationRequest(identifier: "call-ended", content: content, trigger: nil))
        }
    }

    /// A banner with a tr("Записать", "Record") button. Nothing is recorded unless the person presses it.
    private func offerRecording(bundleID: String, appName: String) {
        guard model.phase == .idle else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = tr("Похоже, начался звонок в \(appName)", "A call seems to have started in \(appName)")
            content.body = tr("Записать его? Не забудьте предупредить собеседников.", "Record it? Remember to tell the others.")
            content.categoryIdentifier = Self.callCategory
            content.userInfo = [Self.bundleIDKey: bundleID]
            let request = UNNotificationRequest(identifier: "call-\(bundleID)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == Self.stopAction {
            await model.stopRecording()
            return
        }
        guard response.notification.request.content.categoryIdentifier == Self.callCategory else { return }
        let bundleID = response.notification.request.content.userInfo[Self.bundleIDKey] as? String
        let wantsRecording = response.actionIdentifier == Self.recordAction
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        guard wantsRecording, let bundleID else { return }
        await model.startRecording(bundleID: bundleID)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
