import CallLibrary
import Localization
import SwiftUI

@main
struct CallRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Transcribation", id: MainWindow.id) {
            MainWindow(model: delegate.model)
                .environment(delegate.model)
                .environment(delegate.account)
                .environment(delegate.settings)
                .environment(delegate.preferences)
                .environment(delegate.helpers)
                .environment(delegate.reporter)
                .environment(delegate.updater)
                .environment(delegate.lock)
                .onAppear { DockPresence.show() }
                .onDisappear { DockPresence.hide() }
        }
        .defaultSize(width: 1160, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(tr("Проверить обновления…", "Check for Updates…")) { delegate.updater.checkForUpdates() }
                    .disabled(!delegate.updater.isConfigured)
            }
            CommandGroup(after: .help) {
                Button(tr("Сообщить о проблеме…", "Report a Problem…")) { delegate.reporter.collect() }
                    .disabled(delegate.reporter.isCollecting)
            }
        }

        MenuBarExtra {
            MenuBarPanel(model: delegate.model)
                .environment(delegate.account)
                .environment(delegate.preferences)
                .environment(delegate.lock)
        } label: {
            MenuBarLabel(model: delegate.model, symbol: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    /// A star for a moment after a mark confirms it without a sound that the microphone could pick up.
    private var menuBarSymbol: String {
        if delegate.model.justMarked { return "star.fill" }
        return delegate.model.isRecording ? "record.circle.fill" : "waveform"
    }
}

/// The menu bar icon. It is on screen for the whole run, so it also hands the app a way to open the main window
/// for a Spotlight hit or an intent, even when the window was never opened in this run.
private struct MenuBarLabel: View {
    let model: AppModel
    let symbol: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol)
            .onAppear {
                if model.openMainWindow == nil {
                    model.openMainWindow = { [openWindow] in openWindow(id: MainWindow.id) }
                }
            }
    }
}
