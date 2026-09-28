import CallLibrary
import Localization
import SwiftUI

/// Quick controls that work with the main window closed.
struct MenuBarPanel: View {
    @Bindable var model: AppModel
    @Environment(CodexAccountModel.self) private var account
    @Environment(\.openWindow) private var openWindow
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isRecording ? Color.red : Color.secondary.opacity(0.5))
                    .frame(width: 9, height: 9)
                Text(model.isPaused ? tr("Пауза", "Paused")
                     : model.isRecording ? tr("Идёт запись", "Recording") : tr("Готов к записи", "Ready to record"))
                    .font(.headline)
                Spacer()
                if model.isRecording {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(max(0, model.recordedTime(at: context.date)).clockString)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            AppPicker(model: model)

            if let warning = model.soundWarning {
                Label(warning, systemImage: "speaker.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                Task {
                    if model.isRecording { await model.stopRecording() } else { await model.startRecording() }
                }
            } label: {
                Label(model.isRecording ? tr("Остановить и сохранить", "Stop and Save") : tr("Начать запись", "Start Recording"),
                      systemImage: model.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(model.isRecording ? .red : .accentColor)
            .controlSize(.large)
            .disabled(model.isBusy || (!model.isRecording && model.apps.isEmpty))

            if model.isRecording {
                Button {
                    Task { await model.togglePause() }
                } label: {
                    Label(model.isPaused ? tr("Продолжить запись", "Resume recording") : tr("Пауза", "Pause"),
                          systemImage: model.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                Button {
                    Task { await model.markImportant() }
                } label: {
                    Label(
                        model.currentMarks.isEmpty
                            ? tr("Отметить важное", "Mark as important")
                            : tr("Отметить важное · \(model.currentMarks.count)", "Mark as important · \(model.currentMarks.count)"),
                        systemImage: model.justMarked ? "star.fill" : "star"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Label(account.isSignedIn ? tr("ИИ подключён", "AI connected") : tr("ИИ не подключён — настройте в окне приложения", "No AI connected — set it up in the app window"),
                  systemImage: account.isSignedIn ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(account.isSignedIn ? Color.green : Color.orange)

            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !model.isRecording, !lock.isLocked, let last = LastMeetingSummary.latest(in: model.recordings) {
                LastMeetingButton(recording: last) {
                    showWindow()
                    model.open(last.id)
                }
            }

            Divider()

            Button {
                showWindow()
            } label: {
                Label(tr("Открыть Transcribation", "Open Transcribation"), systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(tr("Выйти", "Quit"), systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            model.openMainWindow = { [openWindow] in openWindow(id: MainWindow.id) }
            model.refreshApps()
        }
    }

    private func showWindow() {
        DockPresence.show()
        openWindow(id: MainWindow.id)
        NSApp.activate()
    }
}

/// The latest summarised meeting at a glance; a click opens it in the window.
private struct LastMeetingButton: View {
    let recording: RecordingItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Последняя встреча", "Latest meeting"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(recording.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(recording.analysis?.summary ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                let open = recording.analysis?.tasks.filter { !$0.isDone }.count ?? 0
                if open > 0 {
                    Label(plural(open, "открытая задача", "открытые задачи", "открытых задач", "open task", "open tasks"),
                          systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(tr("Открыть встречу", "Open the meeting"))
    }
}
