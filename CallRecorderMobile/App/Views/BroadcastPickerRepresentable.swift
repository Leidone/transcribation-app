import ReplayKit
import SwiftUI

/// Wraps `RPSystemBroadcastPickerView` — the only way to start a ReplayKit broadcast. iOS refuses to let an app
/// start one programmatically; the person must tap this system-provided button themselves.
struct BroadcastPickerRepresentable: UIViewRepresentable {
    /// The Broadcast Upload Extension's bundle identifier, so the picker offers Transcribation (not some other
    /// broadcast-capable app) by default.
    static let extensionBundleID = "app.callrecorder.dev.ios.broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        picker.preferredExtension = Self.extensionBundleID
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
