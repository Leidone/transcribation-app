import AVFoundation
import CallLibrary
import Localization
import SwiftUI

/// First launch: what the app does with sound, the microphone permission, the speech models downloaded ahead of
/// the first call, and the AI for summaries. Every step can be skipped and done later.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(AppPreferences.self) private var preferences
    @State private var step = 0
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var download: Double?
    @State private var modelsReady = false
    @State private var downloadError: String?
    let onConnectAI: () -> Void

    private let lastStep = 3

    var body: some View {
        ZStack {
            AmbientBackground()
            content
        }
        .frame(width: 580, height: 640)
    }

    private var content: some View {
        VStack(spacing: 26) {
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: index == step ? 28 : 8, height: 8)
                }
            }
            .animation(Motion.quick, value: step)

            Group {
                switch step {
                case 0: welcome
                case 1: microphoneStep
                case 2: modelsStep
                default: aiStep
                }
            }
            .id(step)
            .transition(.blurReplace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if step > 0 {
                    Button(tr("Назад", "Back")) { withAnimation(Motion.smooth) { step -= 1 } }
                        .buttonStyle(.glass)
                }
                Spacer()
                Button(step == lastStep ? tr("Начать", "Start") : tr("Дальше", "Next")) {
                    if step == lastStep {
                        preferences.hasCompletedOnboarding = true
                    } else {
                        withAnimation(Motion.smooth) { step += 1 }
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(34)
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            GradientTitle(text: tr("Добро пожаловать\nв Transcribation", "Welcome\nto Transcribation"), size: 34)
            Text(tr("Приложение записывает звук выбранного приложения и ваш микрофон, расшифровывает всё на этом Mac и готовит итоги с задачами.", "The app records the sound of the app you choose and your microphone, transcribes everything on this Mac and writes a summary with tasks."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(tr("Аудио и расшифровки не покидают Mac. В ИИ уходит только текст, и только когда вы попросите итоги.", "Audio and transcripts never leave the Mac. Only text goes to the AI, and only when you ask for a summary."), systemImage: "lock.shield")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 16, padding: 14)
            Label(tr("Записывать разговор можно только с согласия собеседников. Предупредите их в начале звонка.", "Record a conversation only with the others' consent. Tell them at the start of the call."), systemImage: "person.2.wave.2")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 16, padding: 14)
        }
    }

    private var microphoneStep: some View {
        StepCard(
            icon: "mic.fill", title: tr("Микрофон", "Microphone"),
            text: tr("Нужен, чтобы записывать ваш голос отдельной дорожкой — так в расшифровке сразу понятно, где говорите вы. Доступ к звуку других приложений macOS спросит при первой записи.", "Needed to record your voice as a separate track, so the transcript knows at once where you speak. macOS asks for access to other apps' sound at the first recording.")
        ) {
            switch microphone {
            case .authorized:
                Label(tr("Доступ разрешён", "Access allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .denied, .restricted:
                VStack(spacing: 8) {
                    Label(tr("Доступ запрещён", "Access denied"), systemImage: "xmark.octagon.fill").foregroundStyle(.orange)
                    Button(tr("Открыть настройки конфиденциальности", "Open Privacy Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.glass)
                }
            default:
                Button(tr("Разрешить микрофон", "Allow the Microphone")) {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .audio)
                        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var modelsStep: some View {
        StepCard(
            icon: "cpu", title: tr("Модели распознавания", "Recognition models"),
            text: tr("Распознавание речи и голосов работает без интернета, но модели нужно один раз скачать — несколько сотен мегабайт. Лучше сейчас, чем перед первой расшифровкой.", "Speech and voice recognition work offline, but the models have to be downloaded once — a few hundred megabytes. Better now than before the first transcript.")
        ) {
            if modelsReady {
                Label(tr("Модели готовы", "Models ready"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if let download {
                VStack(spacing: 6) {
                    ProgressView(value: download)
                        .frame(width: 280)
                    Text(download < 1 ? tr("Скачиваем… \(Int(download * 100))%", "Downloading… \(Int(download * 100))%") : tr("Готовим модели к работе…", "Getting the models ready…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            } else {
                VStack(spacing: 8) {
                    Button(tr("Скачать модели", "Download Models")) { prepareModels() }
                        .buttonStyle(.glassProminent)
                    if let downloadError {
                        Text(downloadError).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var aiStep: some View {
        StepCard(
            icon: "sparkles", title: tr("ИИ для итогов", "AI for summaries"),
            text: tr("Итоги, решения и задачи пишет ИИ, который вы выберете: аккаунт ChatGPT, ключ OpenAI, Claude или свой сервер. Без него расшифровка всё равно работает.", "The summary, decisions and tasks are written by the AI you choose: a ChatGPT account, an OpenAI key, Claude or your own server. Transcription works without it.")
        ) {
            Button(tr("Подключить ИИ", "Connect an AI")) {
                preferences.hasCompletedOnboarding = true
                onConnectAI()
            }
            .buttonStyle(.glassProminent)
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
                downloadError = tr(
                    "Не получилось: \(error.localizedDescription). Можно продолжить — модели скачаются при первой расшифровке.",
                    "That did not work: \(error.localizedDescription). You can go on — the models download at the first transcript."
                )
            }
            download = nil
        }
    }
}

private struct StepCard<Action: View>: View {
    let icon: String
    let title: String
    let text: String
    @ViewBuilder let action: Action

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .glassEffect(.regular.tint(.accentColor), in: .circle)
            Text(title).font(.title2.weight(.semibold))
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action
                .padding(.top, 6)
        }
    }
}
