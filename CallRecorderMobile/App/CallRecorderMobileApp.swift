import AVFAudio
import AudioCapture
import CallLibrary
import SwiftUI

@main
struct CallRecorderMobileApp: App {
    @State private var model = AppModel()
    @State private var settings = AISettings()
    @State private var account: AIAccountModel
    @State private var preferences = AppPreferences()
    @Environment(\.scenePhase) private var scenePhase
    /// Kept alive for as long as the app runs; the Darwin-notification observer is removed if this deallocates.
    @State private var signalToken: AnyObject?

    init() {
        let settings = AISettings()
        _settings = State(initialValue: settings)
        _account = State(initialValue: AIAccountModel(settings: settings))
        // Playback of a recording follows the silent switch like any audio app, and keeps going on a locked screen.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    var body: some Scene {
        WindowGroup {
            RecordingListView(model: model)
                .environment(model)
                .environment(account)
                .environment(preferences)
                .onChange(of: scenePhase) { _, phase in
                    // The reliable path: a broadcast that finished while the app was backgrounded or killed is
                    // always picked up here, whether or not the Darwin notification below ever arrived.
                    if phase == .active { Task { await model.reload() } }
                }
                .onAppear {
                    guard signalToken == nil else { return }
                    signalToken = RecordingAvailableSignal.observe {
                        Task { @MainActor in await model.reload() }
                    }
                }
        }
    }
}
