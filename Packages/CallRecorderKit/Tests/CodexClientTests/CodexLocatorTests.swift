import Foundation
import Testing
@testable import CodexClient

struct CodexLocatorTests {
    private let helpers = URL(fileURLWithPath: "/App/Contents/Helpers")
    private let bundled = URL(fileURLWithPath: "/App/Contents/Helpers/codex")
    private let brew = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
    private let local = URL(fileURLWithPath: "/usr/local/bin/codex")

    @Test("prefers the copy shipped inside the app")
    func prefersBundled() {
        let found = CodexLocator.find(bundleHelpersDirectory: helpers, fallbacks: [brew, local]) { _ in true }

        #expect(found == bundled)
    }

    @Test("falls back to an installed copy when nothing is bundled")
    func fallsBack() {
        let found = CodexLocator.find(bundleHelpersDirectory: helpers, fallbacks: [brew, local]) { $0 == local }

        #expect(found == local)
    }

    @Test("skips files that are not executable and returns nil when nothing is usable")
    func nothingUsable() {
        let found = CodexLocator.find(bundleHelpersDirectory: helpers, fallbacks: [brew, local]) { _ in false }

        #expect(found == nil)
    }

    @Test("works without an app bundle directory")
    func withoutBundle() {
        let found = CodexLocator.find(bundleHelpersDirectory: nil, fallbacks: [brew]) { $0 == brew }

        #expect(found == brew)
    }

    @Test("only https pages on openai.com are trusted for sign-in", arguments: [
        ("https://auth.openai.com/oauth/authorize?x=1", true),
        ("https://openai.com/login", true),
        ("http://auth.openai.com/oauth", false),
        ("https://auth.openai.com.evil.example/oauth", false),
        ("https://evilopenai.com/oauth", false),
        ("file:///etc/passwd", false),
    ])
    func trustedAuthURLs(address: String, expected: Bool) throws {
        let url = try #require(URL(string: address))

        #expect(LoginChallenge.isTrusted(url) == expected)
    }
}
