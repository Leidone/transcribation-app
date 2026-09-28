import AppKit
import CallLibrary
import LocalAuthentication
import Localization
import Observation
import os

private let lockLog = Logger(subsystem: "app.callrecorder.dev", category: "lock")

/// Keeps the recordings out of sight until the person proves it is them with Touch ID (or the Mac's password):
/// at launch, after being away longer than the chosen time, and whenever the Mac sleeps or its screen locks.
/// Recording and its controls keep working while locked; only what was said is hidden.
@Observable
@MainActor
final class AppLock {
    private(set) var isLocked: Bool
    private let preferences: AppPreferences
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingUnlock: Task<Bool, Never>?
    /// Authentications in progress, including turning the protection on or off.
    @ObservationIgnored private var authenticationsInProgress = 0
    /// The context of the Touch ID sensor view on the lock screen: a finger on the sensor unlocks without any
    /// system panel. A new one is made whenever the old one can no longer be used (the app lost the focus).
    @ObservationIgnored private(set) var sensorContext: LAContext?
    /// Changes when the lock screen needs a fresh sensor view.
    private(set) var sensorAttempt = 0

    private var isAuthenticating: Bool { authenticationsInProgress > 0 }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        isLocked = preferences.lockPolicy.isLockedAtLaunch
    }

    /// Follows the app going to the background and the Mac going to sleep.
    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.wentAway() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.cameBack() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.lockNow() }
            })
        }
    }

    func lockNow() {
        guard preferences.locksWithTouchID else { return }
        isLocked = true
        rearmSensor()
    }

    /// The Touch ID panel itself takes the focus from the app, so leaving and coming back while it is shown is not
    /// the person going away — otherwise "lock on every return" would lock again right after unlocking.
    private func wentAway() {
        guard !isAuthenticating else { return }
        leftAt = Date()
    }

    private func cameBack() {
        guard !isAuthenticating else { return }
        defer { leftAt = nil }
        if let leftAt, preferences.lockPolicy.locksAgain(leftAt: leftAt, backAt: Date()) {
            isLocked = true
        }
        // Touch ID in a view works only while the app is in front; coming back needs a fresh one.
        if isLocked { rearmSensor() }
    }

    /// Whether this Mac can read a finger now (Touch ID present, enrolled, not locked out by failed tries).
    var canUseSensor: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// A new context for the lock screen's sensor view; the view shows it and then calls `unlockWithSensor`.
    func makeSensorContext() -> LAContext {
        let context = LAContext()
        sensorContext = context
        return context
    }

    /// Waits for a finger on the sensor, shown in the lock screen's own Touch ID view instead of a system panel.
    func unlockWithSensor(_ context: LAContext) async {
        guard isLocked, context === sensorContext else { return }
        do {
            let isProven = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics, localizedReason: tr("открыть записи", "open your recordings")
            )
            guard isProven, context === sensorContext else { return }
            isLocked = false
            sensorContext = nil
        } catch let error as LAError where error.code == .authenticationFailed {
            // A finger that was not recognised: the view is spent, so offer a fresh one for another try.
            if context === sensorContext { rearmSensor() }
        } catch {
            lockLog.notice("sensor not used: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rearmSensor() {
        sensorContext?.invalidate()
        sensorContext = nil
        sensorAttempt += 1
    }

    /// Asks for Touch ID or the password in the system panel (the lock screen's button, for when the sensor is not
    /// there — a closed lid — or the password is wanted); `true` when the person proved it is them. Asking while a
    /// prompt is already shown waits for that prompt instead of showing another.
    @discardableResult
    func unlock() async -> Bool {
        if let pendingUnlock { return await pendingUnlock.value }
        let prompt = Task { await authenticate(reason: tr("открыть записи", "open your recordings")) }
        pendingUnlock = prompt
        let isProven = await prompt.value
        pendingUnlock = nil
        if isProven {
            isLocked = false
        } else {
            rearmSensor() // the panel may have cancelled the sensor view's wait
        }
        return isProven
    }

    /// Turning the protection off needs the same proof as opening the recordings.
    func setEnabled(_ isOn: Bool) async {
        if isOn {
            guard await authenticate(reason: tr("включить защиту записей", "turn on protection of your recordings")) else { return }
            preferences.locksWithTouchID = true
        } else {
            guard await authenticate(reason: tr("выключить защиту записей", "turn off protection of your recordings")) else { return }
            preferences.locksWithTouchID = false
            isLocked = false
        }
    }

    private func authenticate(reason: String) async -> Bool {
        authenticationsInProgress += 1
        defer {
            authenticationsInProgress -= 1
            leftAt = nil
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lockLog.error("cannot ask for Touch ID: \(error?.localizedDescription ?? "", privacy: .public)")
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            lockLog.notice("not unlocked: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
