import Foundation
import Testing
@testable import CodexClient

struct ProviderSettingsTests {
    private func custom(_ url: String, name: String = "Мой сервер") -> ProviderSettings {
        ProviderSettings(kind: .custom, customName: name, customBaseURL: url)
    }

    @Test("the default provider is a ChatGPT account and adds no config")
    func defaultProvider() {
        #expect(ProviderSettings.default.kind == .chatGPT)
        #expect(ProviderSettings.default.threadConfig() == nil)
    }

    @Test("an OpenAI key needs no config either: Codex keeps that key itself")
    func openAIKey() {
        #expect(ProviderSettings(kind: .openAIKey, customName: "", customBaseURL: "").threadConfig() == nil)
    }

    @Test("a custom provider becomes a model_providers entry that reads its key from the environment")
    func customConfig() throws {
        let config = try #require(custom("https://api.example.com/v1").threadConfig())
        let entry = try #require(config["model_providers"]?["custom"])

        #expect(config["model_provider"]?.stringValue == "custom")
        #expect(entry["base_url"]?.stringValue == "https://api.example.com/v1")
        #expect(entry["env_key"]?.stringValue == ProviderSettings.keyEnvironmentVariable)
        #expect(entry["wire_api"]?.stringValue == "responses")
        #expect(entry["name"]?.stringValue == "Мой сервер")
    }

    @Test("the key itself never appears in the config")
    func noSecretInConfig() throws {
        let config = try #require(custom("https://api.example.com/v1").threadConfig())
        let data = try JSONEncoder().encode(config)

        #expect(!String(decoding: data, as: UTF8.self).contains("sk-"))
    }

    @Test("a missing name falls back to a default one")
    func defaultName() throws {
        let config = try #require(custom("https://api.example.com", name: "  ").threadConfig())

        #expect(config["model_providers"]?["custom"]?["name"]?.stringValue == "Custom")
    }

    @Test("plain http is allowed only for this Mac", arguments: [
        ("https://api.example.com/v1", true),
        ("http://localhost:11434/v1", true),
        ("http://127.0.0.1:1234/v1", true),
        ("http://api.example.com/v1", false),
        ("http://localhost.evil.example/v1", false),
        ("ftp://example.com", false),
        ("not a url", false),
        ("", false),
    ])
    func urlValidation(address: String, accepted: Bool) {
        #expect((custom(address).validatedBaseURL != nil) == accepted)
        #expect((custom(address).threadConfig() != nil) == accepted)
    }

    @Test("only the custom kind counts as a configured custom provider")
    func configuredFlag() {
        #expect(custom("https://api.example.com").isCustomConfigured)
        #expect(!ProviderSettings(kind: .chatGPT, customName: "", customBaseURL: "https://api.example.com").isCustomConfigured)
        #expect(!custom("http://api.example.com").isCustomConfigured)
    }
}
