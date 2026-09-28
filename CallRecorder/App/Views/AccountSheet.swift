import CallLibrary
import CodexClient
import Localization
import SwiftUI

enum SettingsTab: Hashable {
    case account
    case prompt
    case general
}

/// Which AI serves the analysis (sign-in or API key) and what it is told.
struct AccountSheet: View {
    @Environment(CodexAccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var tab: SettingsTab = .account

    var body: some View {
        VStack(spacing: 20) {
            GlassTabBar(
                tabs: [(SettingsTab.account, tr("Аккаунт", "Account")), (SettingsTab.prompt, tr("Промпт", "Prompt")), (SettingsTab.general, tr("Общие", "General"))],
                selection: $tab
            )

            ScrollView {
                Group {
                    switch tab {
                    case .account: AccountTab()
                    case .prompt: PromptSettingsView()
                    case .general: GeneralSettingsView()
                    }
                }
                .id(tab)
                .transition(.blurReplace)
            }
            .scrollIndicators(.hidden)
            .animation(Motion.smooth, value: tab)

            Button(tr("Готово", "Done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glass)
        }
        .padding(28)
        .frame(width: 600, height: 660)
        .task { await account.refresh() }
    }
}

private struct AccountTab: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        VStack(spacing: 26) {
            ProviderPicker()
            StatusHeader()
            ProviderActions()
            ModelField()
            if account.isSignedIn {
                AnalysisCheck()
                    .transition(.blurReplace)
            }
            Text(privacyNote)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .animation(Motion.smooth, value: account.state)
        .animation(Motion.smooth, value: account.settings.provider.kind)
    }

    private var privacyNote: String {
        if account.settings.provider.kind == .anthropic {
            return tr("Текст расшифровки уйдёт в Anthropic (api.anthropic.com). Аудио остаётся на этом Mac.", "The transcript text goes to Anthropic (api.anthropic.com). Audio stays on this Mac.")
        }
        if account.settings.provider.kind == .custom {
            let host = account.settings.provider.validatedBaseURL?.host() ?? tr("выбранный сервер", "the chosen server")
            return tr("Текст расшифровки уйдёт на \(host). Аудио остаётся на этом Mac.", "The transcript text goes to \(host). Audio stays on this Mac.")
        }
        return tr("В OpenAI уходит только текст расшифровки, чтобы получить итоги и задачи. Аудио остаётся на этом Mac.", "Only the transcript text goes to OpenAI, to get the summary and tasks. Audio stays on this Mac.")
    }
}

// MARK: Provider

private struct ProviderPicker: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        GlassTabBar(
            tabs: [
                (ProviderKind.chatGPT, "ChatGPT"),
                (ProviderKind.openAIKey, tr("API-ключ OpenAI", "OpenAI API key")),
                (ProviderKind.custom, tr("Другой ИИ", "Other AI")),
                (ProviderKind.anthropic, "Claude"),
            ],
            selection: Binding(
                get: { account.settings.provider.kind },
                set: { kind in Task { await account.select(kind) } }
            )
        )
    }
}

private struct StatusHeader: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(iconColor)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: account.state == .signingIn || account.state == .checking)
            Text(title)
                .font(.title.weight(.semibold))
                .contentTransition(.opacity)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3, reservesSpace: true)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
    }

    private var kind: ProviderKind { account.settings.provider.kind }

    private var icon: String {
        switch account.state {
        case .signedIn: "checkmark.seal.fill"
        case .unavailable, .failed: "exclamationmark.triangle"
        case .checking, .signingIn, .signedOut: "person.crop.circle"
        }
    }

    private var iconColor: Color {
        switch account.state {
        case .signedIn: .green
        case .unavailable, .failed: .orange
        case .checking, .signingIn, .signedOut: .accentColor
        }
    }

    private var title: String {
        switch account.state {
        case .checking: tr("Проверяем…", "Checking…")
        case .unavailable: tr("Codex не найден", "Codex not found")
        case .signedOut:
            switch kind {
            case .chatGPT: tr("Войдите через OpenAI", "Sign in with OpenAI")
            case .openAIKey: tr("Введите API-ключ", "Enter an API key")
            case .custom: tr("Настройте сервер", "Set up the server")
            case .anthropic: tr("Введите ключ Claude", "Enter a Claude key")
            }
        case .signingIn: tr("Завершите вход в браузере", "Finish signing in in the browser")
        case .signedIn: tr("Подключено", "Connected")
        case .failed: tr("Не получилось", "Something went wrong")
        }
    }

    private var subtitle: String {
        switch account.state {
        case .checking:
            kind == .anthropic ? tr("Проверяем ключ в Anthropic.", "Checking the key with Anthropic.") : tr("Запускаем Codex и читаем состояние.", "Starting Codex and reading its state.")
        case .unavailable:
            tr("В приложении нет Codex, и он не установлен на этом Mac. Соберите dmg с вложенным Codex или установите его через brew.", "The app has no Codex inside and it is not installed on this Mac. Build the dmg with Codex bundled, or install it with brew.")
        case .signedOut:
            switch kind {
            case .chatGPT: tr("Итоги и задачи готовит Codex от имени вашего аккаунта ChatGPT.", "Codex prepares the summary and tasks on behalf of your ChatGPT account.")
            case .openAIKey: tr("Запросы будут оплачиваться по тарифу API OpenAI.", "Requests are billed at OpenAI API rates.")
            case .custom: tr("Укажите адрес сервера, совместимого с OpenAI Responses API, и ключ.", "Enter the address of a server compatible with the OpenAI Responses API, and a key.")
            case .anthropic: tr("Итоги и задачи готовит Claude напрямую через API Anthropic, без Codex.", "Claude prepares the summary and tasks directly through the Anthropic API, without Codex.")
            }
        case .signingIn:
            tr("Мы открыли страницу входа. Как только вы подтвердите вход, окно обновится.", "We opened the sign-in page. Once you confirm, this window updates.")
        case .signedIn(let email, let plan):
            [email, plan.map { kind == .chatGPT ? tr("план \($0)", "\($0) plan") : $0 }].compactMap { $0 }.joined(separator: " · ")
        case .failed(let message):
            message
        }
    }
}

private struct ProviderActions: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        switch account.settings.provider.kind {
        case .chatGPT: ChatGPTActions()
        case .openAIKey: APIKeyActions()
        case .custom: CustomProviderActions()
        case .anthropic: ClaudeActions()
        }
    }
}

private struct ChatGPTActions: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        switch account.state {
        case .checking, .unavailable:
            EmptyView()
        case .signedOut, .failed:
            Button {
                account.startSignIn()
            } label: {
                Label(tr("Войти через OpenAI", "Sign in with OpenAI"), systemImage: "person.crop.circle.badge.checkmark")
                    .frame(minWidth: 240)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        case .signingIn:
            Button(tr("Отменить вход", "Cancel sign-in")) { account.cancelSignIn() }
                .buttonStyle(.glass)
        case .signedIn:
            SignOutButton()
        }
    }
}

private struct SignOutButton: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        Button(tr("Выйти из аккаунта", "Sign out"), role: .destructive) {
            Task { await account.signOut() }
        }
        .buttonStyle(.glass)
    }
}

private struct APIKeyActions: View {
    @Environment(CodexAccountModel.self) private var account
    @State private var key = ""

    var body: some View {
        if account.isSignedIn {
            SignOutButton()
        } else if account.state != .unavailable {
            VStack(spacing: 12) {
                SecureField("sk-…", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                    .onSubmit(submit)
                Button(action: submit) {
                    Label(tr("Войти по ключу", "Sign in with the key"), systemImage: "key.fill")
                        .frame(minWidth: 240)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Text(tr("Ключ хранит Codex в своей папке на этом Mac, приложение его не читает.", "Codex keeps the key in its own folder on this Mac; the app never reads it."))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func submit() {
        let value = key
        key = ""
        Task { await account.signInWithAPIKey(value) }
    }
}

private struct ClaudeActions: View {
    @Environment(CodexAccountModel.self) private var account
    @State private var key = ""

    var body: some View {
        if account.isSignedIn {
            Button(tr("Удалить ключ", "Remove key"), role: .destructive) {
                Task { await account.signOut() }
            }
            .buttonStyle(.glass)
        } else {
            VStack(spacing: 12) {
                SecureField("sk-ant-…", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                    .onSubmit(submit)
                Button(action: submit) {
                    Label(tr("Проверить и сохранить", "Check and save"), systemImage: "key.fill")
                        .frame(minWidth: 240)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || account.state == .checking)
                Text(tr("Нужен ключ API с console.anthropic.com: подписка Claude Pro или Max доступа к API не даёт. Ключ хранится в Связке ключей.", "You need an API key from console.anthropic.com: a Claude Pro or Max subscription does not include API access. The key is kept in the Keychain."))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
    }

    private func submit() {
        let value = key
        key = ""
        Task { await account.saveAnthropicKey(value) }
    }
}

private struct CustomProviderActions: View {
    @Environment(CodexAccountModel.self) private var account
    @State private var key = ""

    var body: some View {
        @Bindable var settings = account.settings

        VStack(alignment: .leading, spacing: 12) {
            TextField(tr("Название (необязательно)", "Name (optional)"), text: $settings.provider.customName)
                .textFieldStyle(.roundedBorder)
            TextField(tr("Адрес, например https://openrouter.ai/api/v1", "Address, e.g. https://openrouter.ai/api/v1"), text: $settings.provider.customBaseURL)
                .textFieldStyle(.roundedBorder)
            if addressLooksWrong {
                Text(tr("Нужен адрес с https://. Обычный http:// разрешён только для localhost.", "The address needs https://. Plain http:// is allowed only for localhost."))
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            SecureField(account.hasCustomKey ? tr("Ключ сохранён в Связке ключей", "The key is saved in the Keychain") : tr("Ключ доступа", "Access key"), text: $key)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button {
                    let value = key
                    key = ""
                    Task {
                        if value.isEmpty { await account.customProviderChanged() } else { await account.saveCustomKey(value) }
                    }
                } label: {
                    Label(tr("Сохранить", "Save"), systemImage: "checkmark")
                }
                .buttonStyle(.glassProminent)
                if account.hasCustomKey {
                    Button(tr("Удалить ключ", "Remove key"), role: .destructive) { Task { await account.removeCustomKey() } }
                        .buttonStyle(.glass)
                }
            }
            Text(tr("Сервер должен поддерживать OpenAI Responses API (OpenAI, OpenRouter, Ollama, LM Studio и похожие). Ключ хранится в Связке ключей.", "The server must support the OpenAI Responses API (OpenAI, OpenRouter, Ollama, LM Studio and the like). The key is kept in the Keychain."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 440)
        .animation(Motion.quick, value: addressLooksWrong)
    }

    private var addressLooksWrong: Bool {
        let address = account.settings.provider.customBaseURL.trimmingCharacters(in: .whitespaces)
        return !address.isEmpty && account.settings.provider.validatedBaseURL == nil
    }
}

// MARK: Model and check

/// Reload the model list when the account state or the provider changes.
private struct ModelListKey: Hashable {
    let state: CodexAccountModel.State
    let kind: ProviderKind
}

private struct ModelField: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        @Bindable var settings = account.settings

        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Модель", "Model"))
                .font(.headline)
            HStack(spacing: 10) {
                TextField(tr("По умолчанию", "Default"), text: Binding(
                    get: { settings.selectedModel ?? "" },
                    set: { settings.selectedModel = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Menu {
                    ForEach(account.models) { model in
                        Button(model.name + (model.isDefault ? tr(" · по умолчанию", " · default") : "")) {
                            settings.selectedModel = model.id
                        }
                    }
                    if !account.models.isEmpty { Divider() }
                    Button(tr("Обновить список", "Refresh the list")) { Task { await account.loadModels() } }
                } label: {
                    Label(tr("Выбрать", "Choose"), systemImage: "list.bullet")
                }
                .menuStyle(.button)
                .disabled(!account.isSignedIn)
            }
            Text(account.modelsError ?? tr("Меньшая модель тратит меньше токенов. Пусто: модель по умолчанию.", "A smaller model spends fewer tokens. Empty: the default model."))
                .font(.footnote)
                .foregroundStyle(account.modelsError == nil ? Color.secondary : Color.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 16)
        .task(id: ModelListKey(state: account.state, kind: account.settings.provider.kind)) {
            if account.isSignedIn, account.models.isEmpty { await account.loadModels() }
        }
    }
}

/// Runs the built-in sample transcript through the chosen AI, to see that sign-in, the protocol and the schema work.
private struct AnalysisCheck: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("Проверка анализа", "Analysis check"))
                    .font(.headline)
                Spacer()
                Button {
                    Task { await account.analyze(transcript: SampleData.recordings[0].transcriptText) }
                } label: {
                    if account.isAnalyzing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(tr("Проанализировать пример", "Analyse the example"), systemImage: "sparkles")
                    }
                }
                .buttonStyle(.glass)
                .disabled(account.isAnalyzing)
            }

            if let error = account.analysisError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            if let run = account.lastRun {
                VStack(alignment: .leading, spacing: 10) {
                    Text(runSummary(run))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text(run.analysis.summary)
                        .font(.callout)
                    ForEach(Array(run.analysis.tasks.enumerated()), id: \.offset) { _, task in
                        Label(task.title + (task.owner.map { " — \($0)" } ?? ""), systemImage: "circle")
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.blurReplace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
        .animation(Motion.smooth, value: account.lastRun)
        .animation(Motion.smooth, value: account.isAnalyzing)
    }

    private func runSummary(_ run: CodexAccountModel.AnalysisRun) -> String {
        let seconds = run.seconds.formatted(.number.precision(.fractionLength(1)))
        var parts = [
            tr("Готово за \(seconds) с", "Done in \(seconds) s"),
            tr("задач: \(run.analysis.tasks.count)", "tasks: \(run.analysis.tasks.count)"),
        ]
        if let usage = run.usage {
            parts.append(tr("токены: вход \(usage.input), выход \(usage.output)", "tokens: \(usage.input) in, \(usage.output) out"))
        }
        return parts.joined(separator: " · ")
    }
}
