#if os(macOS)
import Foundation
import os

/// Fallback path: one `codex exec` call per analysis (read-only, ephemeral, schema-constrained output).
public struct ExecFallback: Sendable {
    public let executable: URL
    public let codexHome: URL

    public init(executable: URL, codexHome: URL) {
        self.executable = executable
        self.codexHome = codexHome
    }

    public func analyze(transcript: String) async throws -> CallAnalysis {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("callrecorder-exec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let schemaURL = workDirectory.appendingPathComponent("schema.json")
        let outputURL = workDirectory.appendingPathComponent("answer.json")
        try Data(CallAnalysis.outputSchemaJSON.utf8).write(to: schemaURL)

        let prompt = CallAnalysis.instructions + "\n\nTRANSCRIPT:\n" + transcript
        let status = try await run(
            arguments: [
                "exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only",
                "--output-schema", schemaURL.path, "-o", outputURL.path, "-C", workDirectory.path,
            ] + CodexLockdown.flags + ["-"],
            standardInput: Data(prompt.utf8)
        )
        guard status == 0 else { throw CodexError.turnFailed("codex exec exited with status \(status)") }
        return try CallAnalysis.decode(from: String(contentsOf: outputURL, encoding: .utf8))
    }

    private func run(arguments: [String], standardInput: Data) async throws -> Int32 {
        SignalSafety.ignoreBrokenPipe
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome.path
        process.environment = environment
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // The exit status travels through a stream, so it can be delivered at most once by construction.
        let (exitStatuses, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        do {
            try process.run()
        } catch {
            throw CodexError.processFailedToStart(error.localizedDescription)
        }

        // Feed the prompt off the cooperative pool; a child that exits early only makes the write fail.
        let writer = input.fileHandleForWriting
        let feeder = Task.detached {
            do {
                try writer.write(contentsOf: standardInput)
                try writer.close()
            } catch {
                Logger.codex.notice("codex closed its stdin before the whole prompt was written")
            }
        }
        for await status in exitStatuses {
            await feeder.value
            return status
        }
        throw CodexError.processExited
    }
}
#endif
