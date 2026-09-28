import AppKit
import CallLibrary
import CodexClient
import Localization
import Observation
import SwiftUI

/// The AI behind the analysis: a ChatGPT account, an OpenAI API key, another provider, or Claude by API key
/// (called directly, without `codex`). Sign-in runs through the
/// `codex` app-server; the app never sees ChatGPT tokens or an OpenAI key, `codex` keeps them in its own
/// `CODEX_HOME`. A custom provider's key is in the Keychain and reaches `codex` through its environment.
@Observable
@MainActor
final class CodexAccountModel {
    enum State: Hashable {
        case checking
        /// No `codex` executable was found (neither bundled nor installed).
        case unavailable
        case signedOut
        case signingIn
        case signedIn(email: String?, plan: String?)
        case failed(String)
    }

    struct AnalysisRun: Equatable {
        let analysis: CallAnalysis
        let seconds: Double
        let usage: TokenUsage?
    }

    let settings: AISettings

    private(set) var state: State = .checking
    private(set) var isAnalyzing = false
    private(set) var lastRun: AnalysisRun?
    private(set) var analysisError: String?
    /// What the latest analysis cost, from any recording.
    private(set) var lastUsage: TokenUsage?
    private(set) var models: [ModelChoice] = []
    private(set) var isLoadingModels = false
    private(set) var modelsError: String?
    private(set) var hasCustomKey: Bool
    private(set) var hasAnthropicKey: Bool

    private var client: AppServerClient?
    private var signInTask: Task<Void, Never>?

    init(settings: AISettings) {
        self.settings = settings
        hasCustomKey = ProviderKeychain.read(.custom) != nil
        hasAnthropicKey = ProviderKeychain.read(.anthropic) != nil
    }

    static var codexHome: URL {
        URL.applicationSupportDirectory.appending(path: "CallRecorder/codex", directoryHint: .isDirectory)
    }

    var isSignedIn: Bool {
        if case .signedIn = state { true } else { false }
    }

    // MARK: Provider

    /// Switches the AI that serves the analysis and re-reads the account state.
    func select(_ kind: ProviderKind) async {
        guard settings.provider.kind != kind else { return }
        settings.provider.kind = kind
        models = []
        modelsError = nil
        await discardClient()
        await refresh()
    }

    /// Call after the custom provider's name or address changed.
    func customProviderChanged() async {
        await discardClient()
        await refresh()
    }

    func saveCustomKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try ProviderKeychain.save(trimmed, slot: .custom)
            hasCustomKey = true
            await customProviderChanged()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func removeCustomKey() async {
        ProviderKeychain.delete(.custom)
        hasCustomKey = false
        await customProviderChanged()
    }

    /// Checks the key with Anthropic first, so a wrong one is never stored; the model list comes back with it.
    func saveAnthropicKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state != .checking else { return }
        state = .checking
        do {
            let found = try await AnthropicClient(apiKey: trimmed).availableModels()
            try ProviderKeychain.save(trimmed, slot: .anthropic)
            hasAnthropicKey = true
            models = found
            modelsError = nil
            state = anthropicState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Account

    func refresh() async {
        guard state != .signingIn else { return }
        switch settings.provider.kind {
        case .custom:
            state = customProviderState()
            return
        case .anthropic:
            state = anthropicState()
            return
        case .chatGPT, .openAIKey:
            break
        }
        do {
            let account = try await ensureClient().readAccount()
            if account.isSignedIn {
                state = .signedIn(email: account.email, plan: account.planType ?? (account.method == .apiKey ? tr("API-ключ", "API key") : nil))
            } else {
                state = .signedOut
            }
        } catch CodexClientFailure.notInstalled {
            state = .unavailable
        } catch {
            await discardClient()
            state = .failed(error.localizedDescription)
        }
    }

    func startSignIn() {
        guard state != .signingIn else { return }
        signInTask = Task { await signIn() }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    func signInWithAPIKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .checking
        do {
            try await ensureClient().loginWithAPIKey(trimmed)
            await refresh()
        } catch CodexClientFailure.notInstalled {
            state = .unavailable
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
        if settings.provider.kind == .anthropic {
            ProviderKeychain.delete(.anthropic)
            hasAnthropicKey = false
            models = []
            lastRun = nil
            await refresh()
            return
        }
        do {
            try await ensureClient().logout()
            lastRun = nil
            await refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The models the current account can use, for the model picker.
    func loadModels() async {
        guard isSignedIn, !isLoadingModels else { return }
        isLoadingModels = true
        modelsError = nil
        defer { isLoadingModels = false }
        do {
            models = try await modelChoices()
        } catch {
            modelsError = error.localizedDescription
        }
    }

    // MARK: Analysis

    /// The analysis of one transcript with the chosen prompt and provider; the caller stores it.
    func analysis(of transcript: String, template: AnalysisTemplate = .general) async throws -> AnalysisOutcome {
        guard isSignedIn else { throw CodexClientFailure.notSignedIn }
        let outcome: AnalysisOutcome
        var prompt = settings.prompt(for: template)
        if settings.provider.kind == .anthropic {
            guard let key = ProviderKeychain.read(.anthropic) else { throw CodexClientFailure.notSignedIn }
            prompt.model = settings.provider.claudeModel
            outcome = try await AnthropicClient(apiKey: key).analyze(transcript: transcript, prompt: prompt)
        } else {
            outcome = try await ensureClient().analyze(
                transcript: transcript, prompt: prompt, provider: settings.provider
            )
        }
        lastUsage = outcome.usage
        return outcome
    }

    /// Answers a question about meetings with the chosen provider and model.
    func answer(_ question: MeetingQuestion) async throws -> AnswerOutcome {
        guard isSignedIn else { throw CodexClientFailure.notSignedIn }
        let outcome: AnswerOutcome
        if settings.provider.kind == .anthropic {
            guard let key = ProviderKeychain.read(.anthropic) else { throw CodexClientFailure.notSignedIn }
            outcome = try await AnthropicClient(apiKey: key).answer(question, model: settings.provider.claudeModel)
        } else {
            outcome = try await ensureClient().answer(question, prompt: settings.prompt, provider: settings.provider)
        }
        lastUsage = outcome.usage
        return outcome
    }

    /// Sends a transcript through the chosen AI and keeps the result, the time it took and the token usage.
    func analyze(transcript: String) async {
        guard isSignedIn, !isAnalyzing else { return }
        isAnalyzing = true
        analysisError = nil
        defer { isAnalyzing = false }

        let clock = ContinuousClock()
        let start = clock.now
        do {
            let outcome = try await analysis(of: transcript)
            let elapsed = clock.now - start
            lastRun = AnalysisRun(
                analysis: outcome.analysis,
                seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
                usage: outcome.usage
            )
        } catch {
            analysisError = error.localizedDescription
        }
    }

    func shutdown() {
        signInTask?.cancel()
        guard let client else { return }
        self.client = nil
        Task { await client.stop() }
    }

    // MARK: Plumbing

    private enum CodexClientFailure: LocalizedError {
        case notInstalled
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .notInstalled: tr("Codex не найден на этом Mac.", "Codex is not found on this Mac.")
            case .notSignedIn: tr("Сначала подключите ИИ в настройках.", "Connect an AI in the settings first.")
            }
        }
    }

    /// Claude is called directly, so all it needs is a key: no Codex, no sign-in.
    private func anthropicState() -> State {
        hasAnthropicKey ? .signedIn(email: nil, plan: "Claude API") : .signedOut
    }

    private func modelChoices() async throws -> [ModelChoice] {
        if settings.provider.kind == .anthropic {
            guard let key = ProviderKeychain.read(.anthropic) else { throw CodexClientFailure.notSignedIn }
            return try await AnthropicClient(apiKey: key).availableModels()
        }
        return try await ensureClient().availableModels()
    }

    /// A custom provider needs an address and a key, and `codex` to run the request.
    private func customProviderState() -> State {
        guard CodexLocator.find() != nil else { return .unavailable }
        let provider = settings.provider
        guard provider.isCustomConfigured, hasCustomKey else { return .signedOut }
        let name = provider.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return .signedIn(email: nil, plan: name.isEmpty ? provider.validatedBaseURL?.host() : name)
    }

    private func signIn() async {
        state = .signingIn
        var challenge: LoginChallenge?
        do {
            let client = try await ensureClient()
            let events = await client.notifications()
            let started = try await client.beginChatGPTLogin()
            challenge = started
            guard LoginChallenge.isTrusted(started.authURL) else {
                throw CodexError.malformedMessage("unexpected sign-in address")
            }
            NSWorkspace.shared.open(started.authURL)
            try await client.awaitLogin(started, notifications: events)
            state = .checking
            await refresh()
        } catch is CancellationError {
            await cancelPendingLogin(challenge)
            state = .signedOut
        } catch CodexClientFailure.notInstalled {
            state = .unavailable
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func cancelPendingLogin(_ challenge: LoginChallenge?) async {
        guard let challenge, let client else { return }
        await client.cancelLogin(challenge)
    }

    private func ensureClient() async throws -> AppServerClient {
        if let client { return client }
        guard let executable = CodexLocator.find() else { throw CodexClientFailure.notInstalled }

        var environment: [String: String] = [:]
        if settings.provider.kind == .custom, let key = ProviderKeychain.read(.custom) {
            environment[ProviderSettings.keyEnvironmentVariable] = key
        }
        let created = AppServerClient(
            process: CodexProcess(executable: executable, codexHome: Self.codexHome, extraEnvironment: environment),
            scratchDirectory: FileManager.default.temporaryDirectory
        )
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        try await created.start(clientName: "Transcribation", clientVersion: version)
        client = created
        return created
    }

    private func discardClient() async {
        guard let client else { return }
        self.client = nil
        await client.stop()
    }
}
