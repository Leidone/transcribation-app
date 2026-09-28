import AVFAudio
import CallLibrary
import SwiftUI
import UserNotifications

/// First launch on the iPhone: privacy and consent, the microphone, a notification when a recording is saved, the
/// speech models, and the AI for summaries. Every step can be skipped.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(AppPreferences.self) private var preferences
    @State private var step = 0
    @State private var microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
    @State private var notificationsAsked = false
    @State private var download: Double?
    @State private var modelsReady = false
    @State private var downloadError: String?
    let onConnectAI: () -> Void

    private let lastStep = 3

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 24) {
                HStack(spacing: 6) {
                    ForEach(0...lastStep, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: index == step ? 28 : 8, height: 8)
                    }
                }
                .animation(Motion.quick, value: step)
                Spacer(minLength: 0)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: models
                    default: ai
                    }
                }
                .id(step)
                .transition(.blurReplace)
                Spacer(minLength: 0)
                Button(step == lastStep ? "Начать" : "Дальше") {
                    if step == lastStep {
                        preferences.hasCompletedOnboarding = true
                    } else {
                        withAnimation(Motion.smooth) { step += 1 }
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            GradientTitle(text: "Transcribation", size: 32)
            Text("Записывает разговор, расшифровывает его на этом iPhone и готовит итоги с задачами.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Label("Аудио и расшифровки остаются на iPhone. В ИИ уходит только текст, когда вы попросите итоги.", systemImage: "lock.shield")
                .font(.callout)
                .glassCard(cornerRadius: 16, padding: 14)
            Label("Записывать разговор можно только с согласия собеседников — предупредите их.", systemImage: "person.2.wave.2")
                .font(.callout)
                .glassCard(cornerRadius: 16, padding: 14)
        }
    }

    private var permissions: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .glassEffect(.regular.tint(.accentColor), in: .circle)
            Text("Разрешения").font(.title2.weight(.semibold))
            Text("Микрофон нужен, чтобы в записи был ваш голос. Уведомление скажет, что запись сохранена, если трансляция закончилась, пока приложение было закрыто.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if microphoneGranted {
                Label("Микрофон разрешён", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Разрешить микрофон") {
                    Task { microphoneGranted = await AVAudioApplication.requestRecordPermission() }
                }
                .buttonStyle(.glass)
            }
            if notificationsAsked {
                Label("Уведомления настроены", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Разрешить уведомления") {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        notificationsAsked = true
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var models: some View {
        VStack(spacing: 18) {
            Image(systemName: "cpu")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .glassEffect(.regular.tint(.accentColor), in: .circle)
            Text("Модели распознавания").font(.title2.weight(.semibold))
            Text("Распознавание работает без интернета, но модели нужно один раз скачать — несколько сотен мегабайт. Лучше по Wi-Fi.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if modelsReady {
                Label("Модели готовы", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if let download {
                ProgressView(value: download)
                Text(download < 1 ? "Скачиваем… \(Int(download * 100))%" : "Готовим модели к работе…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Скачать модели") { prepareModels() }
                    .buttonStyle(.glass)
                if let downloadError {
                    Text(downloadError).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
        }
    }

    private var ai: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .glassEffect(.regular.tint(.accentColor), in: .circle)
            Text("ИИ для итогов").font(.title2.weight(.semibold))
            Text("Итоги и задачи пишет ИИ, которого вы выберете: Claude, ключ OpenAI или свой сервер. Расшифровка работает и без него.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Подключить ИИ") {
                preferences.hasCompletedOnboarding = true
                onConnectAI()
            }
            .buttonStyle(.glass)
        }
    }

    private func prepareModels() {
        downloadError = nil
        download = 0
        Task {
            do {
                try await model.pipeline.prepareModels { fraction in
                    Task { @MainActor in download = max(download ?? 0, fraction) }
                }
                modelsReady = true
            } catch {
                downloadError = "Не получилось: \(error.localizedDescription). Модели скачаются при первой расшифровке."
            }
            download = nil
        }
    }
}
