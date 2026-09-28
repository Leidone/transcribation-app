import CallLibrary
import CodexClient
import SwiftUI

/// Which AI serves the analysis — Claude, an OpenAI API key, or another OpenAI-compatible server — and its key.
/// The iOS counterpart of the macOS app's `AccountSheet`, minus the ChatGPT-account tab: that sign-in is
/// Codex's own OAuth flow, and Codex cannot run on iOS at all (no arbitrary process spawning in the sandbox).
struct SettingsView: View {
    @Environment(AIAccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(spacing: 22) {
                        ProviderPicker(account: account)
                            .staggeredAppear(0)

                        StatusHeader(state: account.state)
                            .staggeredAppear(1)

                        ProviderActions(account: account, key: $key)
                            .staggeredAppear(2)
                            .transition(.blurReplace)

                        if account.isSignedIn {
                            ModelCard(account: account, binding: modelBinding)
                                .staggeredAppear(3)
                                .transition(.blurReplace)
                        }

                        Text(privacyNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .staggeredAppear(4)

                        Text("Вход через аккаунт ChatGPT есть только в приложении для Mac: он идёт через встроенный Codex, а iOS не позволяет приложениям запускать сторонние процессы.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .staggeredAppear(5)

                        GeneralCard(settings: account.settings)
                            .staggeredAppear(6)
                        VoicesCard()
                            .staggeredAppear(7)
                    }
                    .padding()
                    .animation(Motion.smooth, value: account.state)
                    .animation(Motion.smooth, value: account.settings.provider.kind)
                }
            }
            .navigationTitle("ИИ для итогов")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private var modelBinding: Binding<String?> {
        Binding(
            get: { account.settings.selectedModel },
            set: { account.settings.selectedModel = $0 }
        )
    }

    private var privacyNote: String {
        if account.settings.provider.kind == .custom {
            let host = account.settings.provider.validatedBaseURL?.host() ?? "выбранный сервер"
            return "Текст расшифровки уйдёт на \(host). Аудио остаётся на этом iPhone."
        }
        return "В облако уходит только текст расшифровки, чтобы получить итоги и задачи. Аудио остаётся на этом iPhone."
    }
}

private struct ProviderPicker: View {
    let account: AIAccountModel

    var body: some View {
        GlassTabBar(
            tabs: [
                (ProviderKind.anthropic, "Claude"),
                (ProviderKind.openAIKey, "API-ключ OpenAI"),
                (ProviderKind.custom, "Другой ИИ"),
            ],
            selection: Binding(
                get: { account.settings.provider.kind },
                set: { account.select($0) }
            )
        )
    }
}

private struct StatusHeader: View {
    let state: AIAccountModel.State

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: state == .checking)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var title: String {
        switch state {
        case .unavailable: "Недоступно на iOS"
        case .checking: "Проверяем ключ…"
        case .signedOut: "Ключ не добавлен"
        case .signedIn(let plan): plan ?? "Подключено"
        case .failed(let message): message
        }
    }

    private var icon: String {
        switch state {
        case .signedIn: "checkmark.seal.fill"
        case .failed, .unavailable: "exclamationmark.triangle.fill"
        case .checking, .signedOut: "key.fill"
        }
    }

    private var color: Color {
        switch state {
        case .signedIn: .green
        case .failed, .unavailable: .orange
        case .checking, .signedOut: .accentColor
        }
    }
}

private struct ProviderActions: View {
    let account: AIAccountModel
    @Binding var key: String

    var body: some View {
        if account.isSignedIn {
            Button("Удалить ключ", role: .destructive) { account.signOut() }
                .buttonStyle(.glass)
        } else if account.settings.provider.kind == .custom {
            CustomProviderCard(account: account, key: $key)
        } else {
            KeyEntryCard(
                placeholder: account.settings.provider.kind == .anthropic ? "sk-ant-…" : "sk-…",
                note: keyNote,
                key: $key,
                isBusy: account.state == .checking,
                submit: submit
            )
        }
    }

    private var keyNote: String {
        switch account.settings.provider.kind {
        case .anthropic:
            "Нужен ключ API с console.anthropic.com: подписка Claude Pro или Max доступа к API не даёт. Ключ хранится в Связке ключей."
        case .openAIKey:
            "Ключ можно получить на platform.openai.com. Запросы оплачиваются по тарифу API OpenAI. Ключ хранится в Связке ключей."
        default:
            ""
        }
    }

    private func submit() {
        let value = key
        key = ""
        Task { await account.saveKey(value) }
    }
}

private struct KeyEntryCard: View {
    let placeholder: String
    let note: String
    @Binding var key: String
    let isBusy: Bool
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField(placeholder, text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            Button(action: submit) {
                Label("Проверить и сохранить", systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
            if !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct CustomProviderCard: View {
    let account: AIAccountModel
    @Binding var key: String

    var body: some View {
        @Bindable var settings = account.settings

        VStack(alignment: .leading, spacing: 12) {
            TextField("Название (необязательно)", text: $settings.provider.customName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { account.customProviderChanged() }
            TextField("Адрес, например https://openrouter.ai/api/v1", text: $settings.provider.customBaseURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { account.customProviderChanged() }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if addressLooksWrong {
                Text("Нужен адрес с https://.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            SecureField("Ключ доступа", text: $key)
                .textFieldStyle(.roundedBorder)
            Button {
                let value = key
                key = ""
                Task { await account.saveKey(value) }
            } label: {
                Label("Проверить и сохранить", systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || account.state == .checking)
            Text("Сервер должен поддерживать OpenAI Chat Completions API (OpenAI, OpenRouter, Ollama, LM Studio и похожие).")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .animation(Motion.quick, value: addressLooksWrong)
    }

    private var addressLooksWrong: Bool {
        let address = account.settings.provider.customBaseURL.trimmingCharacters(in: .whitespaces)
        return !address.isEmpty && account.settings.provider.validatedBaseURL == nil
    }
}

private struct ModelCard: View {
    let account: AIAccountModel
    let binding: Binding<String?>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Модель")
                .font(.headline)
            Picker("Модель", selection: binding) {
                Text("По умолчанию").tag(String?.none)
                ForEach(account.models) { model in
                    Text(model.name).tag(String?.some(model.id))
                }
            }
            .pickerStyle(.menu)
            .task(id: account.settings.provider.kind) { await account.loadModels() }
            if let error = account.modelsError {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// The meeting template new summaries are written for.
private struct GeneralCard: View {
    @Bindable var settings: AISettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Тип встречи по умолчанию").font(.headline)
            Picker("Тип встречи", selection: $settings.defaultTemplate) {
                ForEach(AnalysisTemplate.allCases) { template in
                    Label(template.title, systemImage: template.systemImage).tag(template)
                }
            }
            .pickerStyle(.menu)
            Text("Подсказывает ИИ, на что обратить внимание в итогах. Для отдельной записи можно выбрать другой.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// People whose voices were named once and are recognised in new recordings; each can be forgotten.
private struct VoicesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Запомненные голоса").font(.headline)
            if model.voiceBook.profiles.isEmpty {
                Text("Пока никого. Переименуйте собеседника в расшифровке, и его голос будет узнан в следующих записях.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.voiceBook.profiles) { profile in
                    HStack {
                        Circle().fill(Theme.speakerColor(profile.name, isMe: false)).frame(width: 9, height: 9)
                        Text(profile.name).font(.body.weight(.medium))
                        Text("· записей: \(profile.samples)").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Забыть", role: .destructive) {
                            withAnimation(Motion.smooth) { model.forgetVoice(profile.id) }
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            Text("Хранится только числовой «отпечаток» голоса, не аудио, и только на этом iPhone.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
