#if os(macOS)
import Foundation

/// Finds the `codex` executable the app should run.
public enum CodexLocator {
    public static let defaultFallbacks: [URL] = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        .map { URL(fileURLWithPath: $0) }

    /// The copy shipped inside the app comes first, so people need nothing installed; the installed copies are
    /// only a fallback for development builds. `nil` when none is executable.
    public static func find(
        bundleHelpersDirectory: URL? = Bundle.main.bundleURL.appending(path: "Contents/Helpers", directoryHint: .isDirectory),
        fallbacks: [URL] = defaultFallbacks,
        isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) -> URL? {
        let bundled = bundleHelpersDirectory.map { $0.appending(path: "codex") }
        return ([bundled].compactMap { $0 } + fallbacks).first(where: isExecutable)
    }
}

extension LoginChallenge {
    /// The sign-in page must be an HTTPS page on openai.com; the address comes from another process,
    /// so it is checked before the browser is opened.
    public static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return host == "openai.com" || host.hasSuffix(".openai.com")
    }
}
#endif
