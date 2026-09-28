import CallLibrary
import CoreSpotlight
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import Localization
import SwiftUI

struct MainWindow: View {
    static let id = "main"

    @Bindable var model: AppModel
    @Environment(CodexAccountModel.self) private var account
    @Environment(AppPreferences.self) private var preferences
    @Environment(ProblemReporter.self) private var reporter
    @Environment(AppLock.self) private var lock
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false
    @State private var showsAccountAfterOnboarding = false

    private enum Route: Hashable {
        case recorder
        case page(AppModel.LibraryPage)
        case recording(UUID)
        case empty
    }

    private var route: Route {
        if model.showsRecorder { return .recorder }
        if let page = model.libraryPage { return .page(page) }
        if let recording = model.selectedRecording { return .recording(recording.id) }
        return .empty
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            ZStack {
                AmbientBackground()
                detail
                    .id(route)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .animation(Motion.smooth, value: route)
        }
        .frame(minWidth: 940, minHeight: 620)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.importAudio(urls) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 22))
                    .overlay {
                        Label(tr("Отпустите, чтобы импортировать аудио", "Drop to import the audio"), systemImage: "square.and.arrow.down")
                            .font(.title2.weight(.semibold))
                    }
                    .padding(10)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: isDropTargeted)
        .task {
            model.openMainWindow = { [openWindow] in openWindow(id: MainWindow.id) }
            model.refreshApps()
            await model.reload()
            await account.refresh()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = SpotlightIndex.recordingID(from: activity) { model.open(id) }
        }
        .overlay {
            if lock.isLocked {
                LockScreen()
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: lock.isLocked)
        .sheet(isPresented: onboardingIsPresented) {
            OnboardingView(model: model) { showsAccountAfterOnboarding = true }
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showsAccountAfterOnboarding) {
            AccountSheet()
        }
        .alert(tr("Не получилось", "Something went wrong"), isPresented: errorIsPresented) {
            Button(tr("Понятно", "OK"), role: .cancel) { model.dismissError() }
            Button(tr("Сообщить о проблеме…", "Report a Problem…")) {
                model.dismissError()
                reporter.collect()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch route {
        case .recorder:
            RecorderView(model: model)
        case .page(.tasks):
            TasksOverviewView(model: model)
        case .page(.questions):
            QuestionsView(model: model, scope: .library)
        case .recording:
            if let recording = model.selectedRecording {
                RecordingDetailView(model: model, recording: recording)
            }
        case .empty:
            EmptyStateView(model: model)
        }
    }

    private var onboardingIsPresented: Binding<Bool> {
        Binding(get: { !preferences.hasCompletedOnboarding }, set: { if !$0 { preferences.hasCompletedOnboarding = true } })
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.dismissError() } }
        )
    }
}

private struct EmptyStateView: View {
    @Bindable var model: AppModel
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 68, weight: .light))
                .foregroundStyle(.tint)
                .offset(y: floating ? -8 : 8)
                .staggeredAppear(0)
            // Two lines are reserved (inside GradientTitle) instead of using `.fixedSize(vertical:)`: that made the
            // split view report a ~2400 pt height and pushed the sidebar list off screen.
            GradientTitle(text: tr("Ваши созвоны —\nвсегда под рукой", "Your calls,\nalways at hand"))
                .frame(maxWidth: .infinity)
                .staggeredAppear(1)
            VStack(spacing: 2) {
                Text(tr("Запишите разговор, и здесь появятся", "Record a conversation, and here you get"))
                Text(tr("расшифровка, итоги и задачи.", "the transcript, summary and tasks."))
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .staggeredAppear(2)
            Button {
                model.showsRecorder = true
            } label: {
                Label(tr("Новая запись", "New Recording"), systemImage: "mic.fill")
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .staggeredAppear(3)
        }
        .padding(40)
        .frame(maxWidth: 560)
        .onAppear {
            guard !reduceMotion else { return }
                // Started a moment after appearing: a repeating animation begun in the same update as the view's
                // own layout would repeat that layout too (a sheet's content kept sliding back and forth).
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    withAnimation(Motion.ambient) { floating = true }
                }
        }
    }
}

/// Covers the window until Touch ID (or the Mac's password) says it is the owner.
private struct LockScreen: View {
    @Environment(AppLock.self) private var lock
    @Environment(AppModel.self) private var model
    @State private var sensor: LAContext?

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                if let sensor {
                    TouchIDSensor(context: sensor) { Task { await lock.unlockWithSensor(sensor) } }
                        .id(ObjectIdentifier(sensor))
                        .frame(width: 56, height: 56)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(tr("Записи защищены", "Your recordings are protected"))
                    .font(.title2.weight(.semibold))
                if sensor != nil {
                    Text(tr("Приложите палец к Touch ID", "Touch the Touch ID sensor"))
                        .foregroundStyle(.secondary)
                }
                if model.isRecording {
                    Text(tr("Запись продолжается.", "The recording goes on."))
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label(tr("Разблокировать", "Unlock"), systemImage: "touchid")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: lock.sensorAttempt, initial: true) {
            sensor = lock.canUseSensor ? lock.makeSensorContext() : nil
        }
    }
}

/// Apple's own Touch ID glyph for the lock screen. While it is shown, checking a finger needs no system panel:
/// the context paired with it reports right here. The wait starts once the view is in the window.
private struct TouchIDSensor: NSViewRepresentable {
    let context: LAContext
    let onShown: () -> Void

    func makeNSView(context _: Context) -> SensorHost {
        SensorHost(context: context, onShown: onShown)
    }

    func updateNSView(_: SensorHost, context _: Context) {}

    final class SensorHost: NSView {
        private let onShown: () -> Void
        private var hasStarted = false

        init(context: LAContext, onShown: @escaping () -> Void) {
            self.onShown = onShown
            super.init(frame: .zero)
            let glyph = LAAuthenticationView(context: context, controlSize: .large)
            glyph.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glyph)
            NSLayoutConstraint.activate([
                glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
                glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("not used from a storyboard") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !hasStarted else { return }
            hasStarted = true
            onShown()
        }
    }
}
