import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    /// Sign in with a ChatGPT account (plan credits).
    case chatGPT
    /// An OpenAI API key (billed per token).
    case openAIKey
    /// Any other service that speaks OpenAI's Responses API: a hosted one, or a local server.
    case custom
    /// Claude through Anthropic's own API with an API key, without Codex.
    case anthropic
}

/// Which AI serves the analysis. Secrets are not stored here: an OpenAI key lives in Codex's own credential store,
/// a custom provider's key in the macOS Keychain.
public struct ProviderSettings: Codable, Equatable, Sendable {
    public var kind: ProviderKind
    public var customName: String
    public var customBaseURL: String
    /// The Claude model to use; `nil` means `AnthropicClient.defaultModel`. Kept apart from the prompt's model, which
    /// names a model of the other providers.
    public var claudeModel: String?

    /// The environment variable the Codex process reads a custom provider's key from.
    public static let keyEnvironmentVariable = "TRANSCRIBATION_PROVIDER_KEY"
    public static let `default` = ProviderSettings(kind: .chatGPT, customName: "", customBaseURL: "")

    public init(kind: ProviderKind, customName: String, customBaseURL: String, claudeModel: String? = nil) {
        self.kind = kind
        self.customName = customName
        self.customBaseURL = customBaseURL
        self.claudeModel = claudeModel
    }

    /// HTTPS with a host, or plain HTTP only to this Mac (a local model server). Anything else is refused so a key is
    /// never sent in clear text over the network.
    public var validatedBaseURL: URL? {
        let trimmed = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        if url.scheme == "https" { return url }
        let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host)
        return url.scheme == "http" && isLocal ? url : nil
    }

    public var isCustomConfigured: Bool {
        kind == .custom && validatedBaseURL != nil
    }

    /// Config overrides for one Codex thread; `nil` unless a valid custom provider is chosen.
    public func threadConfig() -> JSONValue? {
        guard kind == .custom, let url = validatedBaseURL else { return nil }
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return .object([
            "model_provider": .string("custom"),
            "model_providers": .object([
                "custom": .object([
                    "name": .string(name.isEmpty ? "Custom" : name),
                    "base_url": .string(url.absoluteString),
                    "env_key": .string(Self.keyEnvironmentVariable),
                    "wire_api": .string("responses"),
                ]),
            ]),
        ])
    }
}
