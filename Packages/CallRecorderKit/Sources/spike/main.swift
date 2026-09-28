import AudioCapture
import CodexClient
import Foundation
import Transcription

// Developer CLI for the Phase 1 spikes. Output goes to stdout on purpose (it is the tool's product).

func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

let usage = """
usage: spike <command>
  codex-probe                        handshake + account state + login URL with an empty CODEX_HOME (no sign-in)
  codex-login   [codex-home]         browser sign-in through the app-server
  codex-analyze <transcript> [home]  structured analysis through the app-server
  exec-analyze  <transcript> [home]  structured analysis through `codex exec` (fallback path)
  asr <audio> parakeet|whisper [ru|en]  transcription benchmark (prints JSON with rtfx, memory, thermal state)
  diarize <audio> [out.csv]             speaker diarization benchmark (CSV readable by Tools/eval/der.py)
  transcribe <recording-folder>         full pipeline on a recording: writes transcript.json, prints statistics
  live <audio> [--fast]                 the transcription during a call, fed from a file at the pace of speech
                                        (--fast: as quickly as it goes); prints each phrase with its delay and
                                        how many times faster than speech this Mac recognises
"""

func codexBinary() -> URL {
    URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_BIN"] ?? "/opt/homebrew/bin/codex")
}

func defaultCodexHome() -> URL {
    URL.applicationSupportDirectory.appending(path: "CallRecorder/codex", directoryHint: .isDirectory)
}

func makeClient(home: URL) -> AppServerClient {
    AppServerClient(
        process: CodexProcess(executable: codexBinary(), codexHome: home),
        scratchDirectory: FileManager.default.temporaryDirectory
    )
}

func timed<T>(_ label: String, _ body: () async throws -> T) async throws -> T {
    let clock = ContinuousClock()
    let start = clock.now
    let value = try await body()
    emit("\(label): \(clock.now - start)")
    return value
}

func openInBrowser(_ url: URL) throws {
    let opener = Process()
    opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    opener.arguments = [url.absoluteString]
    try opener.run()
}

func readTranscript(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func printAnalysis(_ analysis: CallAnalysis) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    emit(String(decoding: try encoder.encode(analysis), as: UTF8.self))
}

func probe() async throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "codex-probe-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let client = makeClient(home: home)
    try await timed("initialize") { try await client.start(clientName: "callrecorder-spike", clientVersion: "0.0.1") }
    let account = try await client.readAccount()
    emit("account: signedIn=\(account.isSignedIn) requiresOpenAIAuth=\(account.requiresOpenAIAuth)")
    let challenge = try await client.beginChatGPTLogin()
    emit("login: id=\(challenge.loginID) host=\(challenge.authURL.host() ?? "?")")
    await client.stop()
}

func signInIfNeeded(client: AppServerClient) async throws {
    let account = try await client.readAccount()
    if account.isSignedIn {
        emit("signed in: plan=\(account.planType ?? "?")")
        return
    }
    let events = await client.notifications()
    let challenge = try await client.beginChatGPTLogin()
    emit("opening browser for sign-in…")
    try openInBrowser(challenge.authURL)
    try await client.awaitLogin(challenge, notifications: events)
    emit("signed in")
}

func login(home: URL) async throws {
    let client = makeClient(home: home)
    try await client.start(clientName: "callrecorder-spike", clientVersion: "0.0.1")
    try await signInIfNeeded(client: client)
    await client.stop()
}

func analyzeWithAppServer(transcript: String, home: URL) async throws {
    let client = makeClient(home: home)
    try await client.start(clientName: "callrecorder-spike", clientVersion: "0.0.1")
    try await signInIfNeeded(client: client)
    let legacy = ProcessInfo.processInfo.environment["SPIKE_PROMPT"] == "legacy"
    let prompt: AnalysisPrompt = legacy ? .legacy : .standard
    let outcome = try await timed("analyze (app-server, \(legacy ? "legacy" : "standard") prompt)") {
        try await client.analyze(transcript: transcript, prompt: prompt)
    }
    if let usage = outcome.usage {
        emit("tokens: input \(usage.input) (cached \(usage.cachedInput)), output \(usage.output), reasoning \(usage.reasoning), total \(usage.total)")
    }
    try printAnalysis(outcome.analysis)
    await client.stop()
}

func analyzeWithExec(transcript: String, home: URL) async throws {
    let fallback = ExecFallback(executable: codexBinary(), codexHome: home)
    let analysis = try await timed("analyze (codex exec)") { try await fallback.analyze(transcript: transcript) }
    try printAnalysis(analysis)
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    emit(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func runAsr(audioPath: String, engine: String, language: String?) async throws {
    let samples = try AsrBenchmark.loadSamples(path: audioPath)
    switch engine {
    case "parakeet": try printJSON(await AsrBenchmark.runParakeet(samples: samples))
    case "whisper": try printJSON(await AsrBenchmark.runWhisper(samples: samples, language: language))
    default: fail("unknown engine \(engine); use parakeet or whisper")
    }
}

func runDiarization(audioPath: String, csvPath: String?) async throws {
    let run = try await DiarizationBenchmark.runFluidAudio(samples: AsrBenchmark.loadSamples(path: audioPath))
    if let csvPath { try run.csv.write(toFile: csvPath, atomically: true, encoding: .utf8) }
    try printJSON(run)
}

func runTranscribe(folder: String) async throws {
    let directory = URL(fileURLWithPath: folder, isDirectory: true)
    let session = try RecordingSession.decode(from: Data(contentsOf: directory.appending(path: "session.json")))
    let input = PipelineInput(
        appAudio: directory.appending(path: session.streams.app.file),
        micAudio: directory.appending(path: session.streams.mic.file),
        micOffsetSeconds: session.syncOffsetSeconds
    )

    let clock = ContinuousClock()
    let start = clock.now
    let transcript = try await TranscriptionPipeline().transcribe(input: input) { stage in emit("stage: \(stage)") }.transcript
    let elapsed = clock.now - start
    try TranscriptStore.save(transcript, in: directory)

    let speakers = Dictionary(grouping: transcript.utterances, by: \.speaker).mapValues(\.count)
    let words = transcript.utterances.reduce(0) { $0 + $1.text.split(separator: " ").count }
    emit("done in \(elapsed): \(transcript.utterances.count) phrases, \(words) words, speakers \(speakers.sorted { $0.key < $1.key })")
    for line in transcript.utterances.prefix(4) {
        emit("  " + String(line.transcriptLine.prefix(110)))
    }
}

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

/// Feeds a file to the live transcriber the way a call would, in 0.1 s pieces, and reports how it keeps up.
func runLive(audioPath: String, paced: Bool) async throws {
    let samples = try AsrBenchmark.loadSamples(path: audioPath)
    let pipeline = TranscriptionPipeline()
    emit("loading the model…")
    _ = try await pipeline.recognisePhrase([Float](repeating: 0, count: 16_000))
    let transcriber = LiveTranscriber { phrase in try await pipeline.recognisePhrase(phrase) }

    let clock = ContinuousClock()
    let start = clock.now
    let reader = Task {
        var last = LiveStats()
        var lines = 0
        for await update in transcriber.updates {
            switch update {
            case .line(let line):
                lines += 1
                let now = seconds(clock.now - start)
                emit("\(String(format: "%7.1f", now)) s  heard at \(line.time.clockText)  \(line.text)")
            case .stats(let stats):
                last = stats
            }
        }
        return (last, lines)
    }

    let piece = 1_600
    var index = 0
    while index < samples.count {
        let end = min(samples.count, index + piece)
        await transcriber.feed(LiveAudio(stream: .app, samples: Array(samples[index..<end]), pts: Double(index) / 16_000))
        index = end
        if paced { try await Task.sleep(until: start + .milliseconds(index / 16), clock: clock) }
    }
    await transcriber.finish()
    let (stats, lines) = await reader.value
    let factor = stats.speedFactor.map { String(format: "%.1f", $0) } ?? "n/a"
    emit("audio \(String(format: "%.1f", Double(samples.count) / 16_000)) s, \(lines) phrases recognised, \(stats.skippedPhrases) skipped")
    emit("recognition ran \(factor)x faster than speech; total wall time \(String(format: "%.1f", seconds(clock.now - start))) s")
}

extension Double {
    /// m:ss
    var clockText: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
let homeArgument = { (index: Int) -> URL in
    arguments.count > index ? URL(fileURLWithPath: arguments[index]) : defaultCodexHome()
}

do {
    switch command {
    case "codex-probe": try await probe()
    case "codex-login": try await login(home: homeArgument(1))
    case "codex-analyze" where arguments.count >= 2:
        try await analyzeWithAppServer(transcript: readTranscript(arguments[1]), home: homeArgument(2))
    case "exec-analyze" where arguments.count >= 2:
        try await analyzeWithExec(transcript: readTranscript(arguments[1]), home: homeArgument(2))
    case "asr" where arguments.count >= 3:
        try await runAsr(audioPath: arguments[1], engine: arguments[2], language: arguments.count > 3 ? arguments[3] : nil)
    case "transcribe" where arguments.count >= 2:
        try await runTranscribe(folder: arguments[1])
    case "live" where arguments.count >= 2:
        try await runLive(audioPath: arguments[1], paced: !arguments.contains("--fast"))
    case "diarize" where arguments.count >= 2:
        try await runDiarization(audioPath: arguments[1], csvPath: arguments.count > 2 ? arguments[2] : nil)
    default: fail(usage)
    }
} catch {
    fail(error.localizedDescription)
}
