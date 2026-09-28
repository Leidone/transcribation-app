import CoreAudio
import os

private let microphoneLog = Logger(subsystem: "app.callrecorder.dev", category: "microphone-use")

/// Whether a given app is using a microphone right now, from Core Audio's list of audio processes. Only the fact
/// of use is read, never the sound. Apps capture through helper processes (`<bundle id>.helper…`), and Safari
/// through WebKit's GPU process, so those count as the app too.
enum MicrophoneUse {
    /// `nil` when Core Audio knows no audio process of the app, so nothing can be said.
    static func isActive(for bundleID: String) -> Bool? {
        let processes = audioProcesses().filter { belongs($0.bundleID, to: bundleID) }
        guard !processes.isEmpty else { return nil }
        return processes.contains(where: \.isRunningInput)
    }

    private struct AudioProcess {
        let bundleID: String
        let isRunningInput: Bool
    }

    private static func belongs(_ processBundleID: String, to appBundleID: String) -> Bool {
        processBundleID == appBundleID
            || processBundleID.hasPrefix(appBundleID + ".")
            || (appBundleID == "com.apple.Safari" && processBundleID == "com.apple.WebKit.GPU")
    }

    private static func audioProcesses() -> [AudioProcess] {
        var address = globalAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids)
        guard status == noErr else {
            microphoneLog.error("cannot list audio processes: \(status)")
            return []
        }
        return ids.compactMap { id in
            bundleID(of: id).map { AudioProcess(bundleID: $0, isRunningInput: isRunningInput(id)) }
        }
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = globalAddress(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        let bundleID = value.takeRetainedValue() as String
        return bundleID.isEmpty ? nil : bundleID
    }

    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        var address = globalAddress(kAudioProcessPropertyIsRunningInput)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
    }
}
