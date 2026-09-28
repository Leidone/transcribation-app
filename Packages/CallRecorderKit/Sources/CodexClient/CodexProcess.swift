#if os(macOS)
import Foundation
import os

extension Logger {
    static let codex = Logger(subsystem: "app.callrecorder.dev", category: "codex")
}

enum SignalSafety {
    /// Writing to a pipe whose reader has exited must fail with EPIPE instead of killing the app with SIGPIPE.
    static let ignoreBrokenPipe: Void = { _ = signal(SIGPIPE, SIG_IGN) }()
}

/// Runs `codex app-server` with stdio pipes and an app-owned `CODEX_HOME`.
public final class CodexProcess: @unchecked Sendable {
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let continuation: AsyncStream<Data>.Continuation
    private let lineStream: AsyncStream<Data>

    /// Complete stdout lines; finishes when the process exits.
    public var lines: AsyncStream<Data> { lineStream }

    /// `extraEnvironment` is added to the process environment (used for a custom provider's key).
    public init(
        executable: URL,
        codexHome: URL,
        arguments: [String] = CodexLockdown.appServerArguments,
        extraEnvironment: [String: String] = [:]
    ) {
        (lineStream, continuation) = AsyncStream<Data>.makeStream()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome.path
        environment.merge(extraEnvironment) { _, added in added }
        process.environment = environment
    }

    public func start() throws {
        SignalSafety.ignoreBrokenPipe
        let buffer = LockedLineBuffer()
        let continuation = continuation
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            for line in buffer.append(chunk) { continuation.yield(line) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Logger.codex.debug("stderr bytes=\(chunk.count)")
        }
        process.terminationHandler = { [stdout, stderr] _ in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            continuation.finish()
        }
        do {
            // The directory holds the sign-in tokens: private to the user, also when it already existed.
            let home = URL(fileURLWithPath: process.environment?["CODEX_HOME"] ?? "")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
            try process.run()
        } catch {
            throw CodexError.processFailedToStart(error.localizedDescription)
        }
    }

    public func send(_ payload: Data) throws {
        try stdin.fileHandleForWriting.write(contentsOf: payload + Data([0x0A]))
    }

    public func terminate() {
        if process.isRunning { process.terminate() }
    }
}
#endif
