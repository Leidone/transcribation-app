import CallLibrary
import Foundation
import Observation
import Sparkle
import os

private let updateLog = Logger(subsystem: "app.callrecorder.dev", category: "updates")

/// Offers new versions of the app (Sparkle). Every update is checked against the developer's EdDSA public key
/// before it is installed, so only files signed by the developer can replace the app. It is off until the build
/// names where updates are published (`UPDATE_FEED_URL`) and the key (`SPARKLE_PUBLIC_KEY`); see docs/UPDATES.md.
@Observable
@MainActor
final class Updater {
    /// Both the address of the update feed and the public key are in this build.
    let isConfigured: Bool
    /// Checks automatically once a day; the person can turn it off.
    var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let driverDelegate: QuietUpdateReminders

    init(bundle: Bundle = .main) {
        let configured = UpdateConfiguration(infoDictionary: bundle.infoDictionary ?? [:]).isComplete
        let delegate = QuietUpdateReminders()
        isConfigured = configured
        driverDelegate = delegate
        if configured {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: delegate
            )
            self.controller = controller
            checksAutomatically = controller.updater.automaticallyChecksForUpdates
        } else {
            controller = nil
            checksAutomatically = false
            updateLog.notice("updates are not configured in this build")
        }
    }

    /// False while a check is already running.
    var canCheck: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// The app lives in the menu bar most of the time, so a new version found in the background is offered gently,
/// the next time the person looks, instead of a window popping up during a call.
final class QuietUpdateReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
