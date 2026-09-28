import Foundation
import Testing
@testable import CodexClient

struct ExecFallbackTests {
    private func makeScript(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "fake-codex-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeFallback(script: URL) -> ExecFallback {
        ExecFallback(executable: script, codexHome: FileManager.default.temporaryDirectory.appending(path: "codex-home-test"))
    }

    private let succeedingBody = """
    out=""
    while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; fi; shift; done
    cat > /dev/null
    printf '%s' '{"summary":"ok","decisions":[],"tasks":[]}' > "$out"
    """

    @Test("returns the analysis written by codex")
    func returnsAnalysis() async throws {
        // Arrange
        let script = try makeScript(succeedingBody)
        defer { try? FileManager.default.removeItem(at: script) }

        // Act
        let analysis = try await makeFallback(script: script).analyze(transcript: "[00:00] Я: привет")

        // Assert
        #expect(analysis == CallAnalysis(summary: "ok", decisions: [], tasks: []))
    }

    @Test("a non-zero exit becomes a typed error")
    func nonZeroExit() async throws {
        let script = try makeScript("cat > /dev/null; exit 3")
        defer { try? FileManager.default.removeItem(at: script) }

        await #expect(throws: CodexError.turnFailed("codex exec exited with status 3")) {
            try await makeFallback(script: script).analyze(transcript: "x")
        }
    }

    @Test("a process that exits without reading a large prompt does not crash the caller")
    func earlyExitWithLargeInput() async throws {
        // Arrange: the child exits at once, so writing >1 MB to its stdin hits a closed pipe (EPIPE).
        let script = try makeScript("exit 3")
        defer { try? FileManager.default.removeItem(at: script) }
        let transcript = String(repeating: "слово ", count: 300_000)

        // Act / Assert
        await #expect(throws: CodexError.turnFailed("codex exec exited with status 3")) {
            try await makeFallback(script: script).analyze(transcript: transcript)
        }
    }

    @Test("a missing executable is reported as failing to start")
    func missingExecutable() async {
        let fallback = ExecFallback(
            executable: URL(fileURLWithPath: "/nonexistent/codex"),
            codexHome: FileManager.default.temporaryDirectory
        )

        await #expect(throws: CodexError.self) { try await fallback.analyze(transcript: "x") }
    }
}
