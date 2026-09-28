import Foundation

/// A model the account can use. Shared by both AI paths (Codex's `AppServerClient` on macOS and the portable
/// `AnthropicClient`), so it lives outside either's `#if os(macOS)` boundary.
public struct ModelChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

/// The analysis together with what it cost. Shared for the same reason as `ModelChoice`.
public struct AnalysisOutcome: Equatable, Sendable {
    public let analysis: CallAnalysis
    public let usage: TokenUsage?

    public init(analysis: CallAnalysis, usage: TokenUsage?) {
        self.analysis = analysis
        self.usage = usage
    }
}
