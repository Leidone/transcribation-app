import CallLibrary
import CodexClient
import Foundation
import Observation

/// The AI behind the analysis on iOS: Claude, an OpenAI API key, or another OpenAI-compatible server — all
/// called directly by HTTP, because iOS cannot spawn the `codex` subprocess the macOS app uses (apps cannot
/// spawn arbitrary executables in the iOS sandbox). ChatGPT-account sign-in is the one macOS option with no
/// iOS equivalent: it is Codex's own OAuth flow, registered to Codex's own app identity — not something this
/// app can reimplement or intercept, so it is never offered here (`ProviderKind.chatGPT` maps to `.unavailable`).
@Observable
@MainActor
final class AIAccountModel {
    enum State: Equatable {
        /// The provider picked is `.chatGPT`, which iOS cannot offer.
        case unavailable
        case checking
        case signedOut
        case signedIn(plan: String?)
        case failed(String)
    }

    struct AnalysisRun: Equatable {
        let analysis: CallAnalysis
        let seconds: Double
        let usage: TokenUsage?
    }

    let settings: AISettings

    private(set) var state: State = .signedOut
    private(set) var isAnalyzing = false
    private(set) var lastRun: AnalysisRun?
    private(set) var analysisError: String?
    private(set) var lastUsage: TokenUsage?
    private(set) var models: [ModelChoice] = []
    private(set) var isLoadingModels = false
    private(set) var modelsError: String?

    init(settings: AISettings) {
        self.settings = settings
        refreshState()
    }

    var isSignedIn: Bool {
        if case .signedIn = state { true } else { false }
    }

    // MARK: Provider

    /// Switches the AI that serves the analysis and re-reads its state.
    func select(_ kind: ProviderKind) {
        guard kind != .chatGPT, settings.provider.kind != kind else { return }
        settings.provider.kind = kind
        models = []
        modelsError = nil
        refreshState()
    }

    /// Call after the custom provider's name or address changed.
    func customProviderChanged() {
        refreshState()
    }

    // MARK: Account

    /// Checks the key against the provider before storing it, so a wrong one is never saved; the model list
    /// comes back for free with the same request.
    func saveKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state != .checking, let slot = keychainSlot else { return }
        if settings.provider.kind == .custom, !settings.provider.isCustomConfigured {
            state = .failed("Сначала укажите адрес сервера.")
            return
        }
        state = .checking
        do {
            let found = try await fetchModels(apiKey: trimmed)
            try ProviderKeychain.save(trimmed, slot: slot)
            models = found
            modelsError = nil
            refreshState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        guard let slot = keychainSlot else { return }
        ProviderKeychain.delete(slot)
        models = []
        lastRun = nil
        refreshState()
    }

    func loadModels() async {
        guard isSignedIn, !isLoadingModels, let key = currentKey else { return }
        isLoadingModels = true
        modelsError = nil
        defer { isLoadingModels = false }
        do {
            models = try await fetchModels(apiKey: key)
        } catch {
            modelsError = error.localizedDescription
        }
    }

    // MARK: Analysis

    /// The analysis of one transcript with the chosen prompt and provider; the caller stores it.
    func analysis(of transcript: String, template: AnalysisTemplate = .general) async throws -> AnalysisOutcome {
        guard let key = currentKey else { throw AccountError.notSignedIn }
        var prompt = settings.prompt(for: template)
        prompt.model = settings.selectedModel
        let outcome: AnalysisOutcome
        switch settings.provider.kind {
        case .anthropic:
            outcome = try await AnthropicClient(apiKey: key).analyze(transcript: transcript, prompt: prompt)
        case .openAIKey:
            outcome = try await OpenAICompatibleClient(apiKey: key).analyze(transcript: transcript, prompt: prompt)
        case .custom:
            guard let url = settings.provider.validatedBaseURL else { throw AccountError.notSignedIn }
            outcome = try await OpenAICompatibleClient(apiKey: key, baseURL: url).analyze(transcript: transcript, prompt: prompt)
        case .chatGPT:
            throw AccountError.notSignedIn
        }
        lastUsage = outcome.usage
        return outcome
    }

    /// Sends a transcript through the chosen AI and keeps the result, the time it took and the token usage —
    /// used by the settings screen's own "try it" check.
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

    // MARK: Plumbing

    private enum AccountError: LocalizedError {
        case notSignedIn
        var errorDescription: String? { "Сначала подключите ИИ в настройках." }
    }

    private var keychainSlot: ProviderKeychain.Slot? {
        switch settings.provider.kind {
        case .anthropic: .anthropic
        case .openAIKey: .openAIKey
        case .custom: .custom
        case .chatGPT: nil
        }
    }

    private var currentKey: String? {
        keychainSlot.flatMap { ProviderKeychain.read($0) }
    }

    private func fetchModels(apiKey: String) async throws -> [ModelChoice] {
        switch settings.provider.kind {
        case .anthropic:
            return try await AnthropicClient(apiKey: apiKey).availableModels()
        case .openAIKey:
            return try await OpenAICompatibleClient(apiKey: apiKey).availableModels()
        case .custom:
            guard let url = settings.provider.validatedBaseURL else { throw AccountError.notSignedIn }
            return try await OpenAICompatibleClient(apiKey: apiKey, baseURL: url).availableModels()
        case .chatGPT:
            throw AccountError.notSignedIn
        }
    }

    private func refreshState() {
        switch settings.provider.kind {
        case .chatGPT:
            state = .unavailable
        case .anthropic:
            state = ProviderKeychain.read(.anthropic) != nil ? .signedIn(plan: "Claude API") : .signedOut
        case .openAIKey:
            state = ProviderKeychain.read(.openAIKey) != nil ? .signedIn(plan: nil) : .signedOut
        case .custom:
            guard settings.provider.isCustomConfigured else {
                state = .signedOut
                return
            }
            state = ProviderKeychain.read(.custom) != nil ? .signedIn(plan: customPlanLabel) : .signedOut
        }
    }

    private var customPlanLabel: String? {
        let name = settings.provider.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? settings.provider.validatedBaseURL?.host() : name
    }
}
