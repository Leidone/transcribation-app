import AppKit
import CoreAudio
import Localization
import os

private let detectorLog = Logger(subsystem: "app.callrecorder.dev", category: "call-detector")

/// Notices that a call has probably started: the microphone went live while a known call app is running. It only
/// reads whether the microphone is in use by any app (never what it hears) and which apps are open.
@MainActor
final class CallDetector {
    /// Desktop apps whose microphone use almost always means a call. Browsers are left out: a live microphone in a
    /// browser is as often a voice message or dictation as a Meet call, and would make the offer a nuisance.
    static let callApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.apple.FaceTime": "FaceTime",
        "ru.keepcoder.Telegram": "Telegram",
        "com.tdesktop.Telegram": "Telegram",
        "one.ayugram.AyuGramDesktop": "AyuGram",
        "ru.yandex.desktop.telemost": tr("Яндекс Телемост", "Yandex Telemost"),
        "com.hnc.Discord": "Discord",
        "com.tinyspeck.slackmacgap": "Slack",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.skype.skype": "Skype",
    ]

    /// Called with the call app's bundle id and name, once per stretch of microphone use.
    var onCallStarted: ((_ bundleID: String, _ name: String) -> Void)?
    var isEnabled = true

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var wasRunning = false
    private let queue = DispatchQueue(label: "app.callrecorder.call-detector")
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
    }

    func start() {
        guard deviceListener == nil else { return }
        let onDeviceChange: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.followDefaultInput() }
        }
        deviceListener = onDeviceChange
        var defaultInput = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultInput, queue, onDeviceChange
        )
        if status != noErr { detectorLog.error("cannot follow the default input device: \(status)") }
        followDefaultInput()
    }

    /// Listens to whichever microphone is the default now; the old one's listener is removed.
    private func followDefaultInput() {
        var running = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        if device != kAudioObjectUnknown, let runningListener {
            AudioObjectRemovePropertyListenerBlock(device, &running, queue, runningListener)
        }
        var defaultInput = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var found = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultInput, 0, nil, &size, &found
        )
        guard status == noErr, found != kAudioObjectUnknown else {
            device = AudioObjectID(kAudioObjectUnknown)
            return
        }
        device = found
        let onRunningChange: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.microphoneStateChanged() }
        }
        runningListener = onRunningChange
        let added = AudioObjectAddPropertyListenerBlock(found, &running, queue, onRunningChange)
        if added != noErr { detectorLog.error("cannot follow the microphone state: \(added)") }
        wasRunning = isMicrophoneRunning()
    }

    private func isMicrophoneRunning() -> Bool {
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private func microphoneStateChanged() {
        let running = isMicrophoneRunning()
        defer { wasRunning = running }
        guard running, !wasRunning, isEnabled, let call = runningCallApp() else { return }
        onCallStarted?(call.bundleID, call.name)
    }

    /// The frontmost known call app if there is one, else any running one.
    private func runningCallApp() -> (bundleID: String, name: String)? {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier.map { Self.callApps[$0] != nil } ?? false
        }
        guard let app = running.first(where: \.isActive) ?? running.first, let id = app.bundleIdentifier else { return nil }
        return (id, Self.callApps[id] ?? app.localizedName ?? id)
    }
}
