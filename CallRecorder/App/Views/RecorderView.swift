import CallLibrary
import Localization
import SwiftUI
import Transcription

struct RecorderView: View {
    @Bindable var model: AppModel
    @Environment(AppPreferences.self) private var preferences
    @State private var width: CGFloat = 0

    /// While a call is transcribed live, the text gets its own panel: beside the recorder in a wide window,
    /// under it in a narrow one.
    private var showsLiveText: Bool {
        model.isRecording && preferences.transcribesLive
    }

    private var hasRoomBeside: Bool {
        width >= LiveTranscriptPanel.besideMinimumWidth
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            recorder
                .frame(maxWidth: .infinity)
            if showsLiveText, hasRoomBeside {
                LiveTranscriptPanel(model: model)
                    .frame(width: LiveTranscriptPanel.width)
                    .frame(maxHeight: .infinity)
                    .padding([.vertical, .trailing], 20)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(Motion.arrive, value: showsLiveText)
        .animation(Motion.smooth, value: hasRoomBeside)
    }

    private var recorder: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 16)
            RecordingOrb(isRecording: model.isRecording, isPaused: model.isPaused)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))

            VStack(spacing: 8) {
                TimerText(model: model)
                Text(statusLine)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                if let meeting = model.meetingNow, model.preferences.usesCalendar {
                    Label(
                        (model.isRecording ? tr("Встреча: ", "Meeting: ") : tr("Запись привяжется к встрече: ", "Will be linked to: "))
                            + meeting.title,
                        systemImage: "calendar"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(tr("Если встреча не та, её можно поменять после записи — кнопкой «Встреча из Календаря».",
                             "If it is the wrong one, change it after the call with the “Calendar meeting” button."))
                    .transition(.opacity)
                }
                if let warning = model.diskWarning {
                    Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }
                if let warning = model.soundWarning {
                    Label(warning, systemImage: "speaker.slash")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }

            if !model.isRecording || !preferences.transcribesLive {
                AppPicker(model: model)
                    .glassCard(cornerRadius: 18, padding: 12)
                    .transition(.opacity)
            }

            controls

            if model.isRecording {
                MarkControl(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if showsLiveText, !hasRoomBeside {
                LiveTranscriptPanel(model: model)
                    .frame(minHeight: 160, maxHeight: 280)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 16)
            Text(tr(
                "Записываются только выбранное приложение и ваш микрофон. Всё хранится на этом Mac.\nПредупредите собеседников о записи. ",
                "Only the chosen app and your microphone are recorded. Everything stays on this Mac.\nLet the others know they are being recorded. "
            ) + hotKeyHint)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(36)
        .frame(maxWidth: 560)
        .animation(Motion.smooth, value: model.phase)
        .animation(Motion.smooth, value: model.meetingNow?.title)
        .task(id: model.selectedBundleID) {
            // The meeting of the moment changes as time goes on: looked up again every minute.
            while !Task.isCancelled {
                await model.refreshMeetingNow()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var hotKeyHint: String {
        preferences.usesGlobalHotKey
            ? tr("Старт и стоп из любого приложения: ", "Start and stop from any app: ") + preferences.recordShortcut.display
            : ""
    }

    private var statusLine: String {
        switch model.phase {
        case .idle: tr("Выберите приложение и начните запись", "Choose an app and start recording")
        case .starting: tr("Подключаемся…", "Connecting…")
        case .recording:
            (model.isPaused ? tr("Пауза · ", "Paused · ") : tr("Идёт запись · ", "Recording · "))
                + (model.apps.first { $0.bundleID == model.selectedBundleID }?.name ?? tr("приложение", "the app"))
        case .stopping: tr("Сохраняем запись…", "Saving the recording…")
        }
    }

    @ViewBuilder
    private var controls: some View {
        Group {
            if model.isRecording {
                HStack(spacing: 12) {
                    Button {
                        Task { await model.togglePause() }
                    } label: {
                        Label(model.isPaused ? tr("Продолжить", "Resume") : tr("Пауза", "Pause"),
                              systemImage: model.isPaused ? "play.fill" : "pause.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.glass)
                    Button {
                        Task { await model.stopRecording() }
                    } label: {
                        Label(tr("Остановить и сохранить", "Stop and Save"), systemImage: "stop.fill")
                            .frame(minWidth: 240)
                    }
                    .tint(.red)
                }
            } else {
                Button {
                    Task { await model.startRecording() }
                } label: {
                    Label(tr("Начать запись", "Start Recording"), systemImage: "record.circle")
                        .frame(minWidth: 240)
                }
                .disabled(model.apps.isEmpty)
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
        .disabled(model.isBusy)
        .overlay(alignment: .trailing) {
            if model.isBusy {
                ProgressView().controlSize(.small).padding(.trailing, 16)
            }
        }
    }
}

/// "Mark as important" during a call, with the marks made so far.
private struct MarkControl: View {
    @Bindable var model: AppModel
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task { await model.markImportant() }
            } label: {
                Label(tr("Отметить важное", "Mark as important"), systemImage: model.justMarked ? "star.fill" : "star")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(.yellow)
            .help(tr(
                "Этот момент подсветится в расшифровке, и ИИ уделит ему внимание в итогах",
                "This moment will be highlighted in the transcript and weighed in the summary"
            ))
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .animation(Motion.quick, value: model.currentMarks)
        .animation(Motion.quick, value: model.justMarked)
    }

    private var caption: String {
        let hint = preferences.usesMarkShortcut ? tr("Сочетание: ", "Shortcut: ") + preferences.markShortcut.display : ""
        guard let last = model.currentMarks.last else { return hint }
        let count = tr("Отмечено: \(model.currentMarks.count)", "Marked: \(model.currentMarks.count)")
        return [count, tr("последняя \(last.clockString)", "last at \(last.clockString)"), hint]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct TimerText: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = model.recordedTime(at: context.date)
            Text(max(0, elapsed).clockString)
                .font(.system(size: 72, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(!model.isRecording || model.isPaused ? Color.secondary : Color.primary)
                .contentTransition(.numericText())
                .animation(Motion.quick, value: Int(max(0, elapsed)))
        }
    }
}

private struct RecordingOrb: View {
    let isRecording: Bool
    let isPaused: Bool

    private var isLive: Bool { isRecording && !isPaused }

    var body: some View {
        ZStack {
            if isLive {
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .frame(width: 132, height: 132)
                        .phaseAnimator([false, true]) { view, expanded in
                            view.scaleEffect(expanded ? 1.7 : 1).opacity(expanded ? 0 : 1)
                        } animation: { _ in
                            .easeOut(duration: 2.2).delay(Double(ring) * 1.1)
                        }
                }
                .transition(.opacity)
            }
            Image(systemName: isRecording ? (isPaused ? "pause.fill" : "waveform") : "mic.fill")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.variableColor.iterative.reversing, isActive: isLive)
                .frame(width: 132, height: 132)
                .glassEffect(.regular.tint(isRecording ? (isPaused ? .orange : .red) : .accentColor), in: .circle)
                .scaleEffect(isLive ? 1.04 : 1)
                .animation(Motion.arrive, value: isRecording)
                .animation(Motion.arrive, value: isPaused)
        }
        .frame(width: 132, height: 132)
    }
}
