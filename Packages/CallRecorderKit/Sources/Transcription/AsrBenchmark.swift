import Darwin
import FluidAudio
import Foundation
import WhisperKit

public struct AsrRun: Codable, Sendable {
    public let engine: String
    public let audioSeconds: Double
    public let loadSeconds: Double
    public let processingSeconds: Double
    /// Audio seconds transcribed per wall-clock second (higher is faster).
    public let rtfx: Double
    public let peakRSSMB: Double
    public let thermalState: String
    public let text: String
}

public enum AsrBenchmark {
    public static let sampleRate = 16_000.0
    /// WhisperKit picks the matching model variant from this name; override with the argument.
    public static let defaultWhisperModel = "large-v3-v20240930_turbo_632MB"

    /// Decodes any audio file to 16 kHz mono float samples (the input both engines expect).
    public static func loadSamples(path: String) throws -> [Float] {
        try AudioConverter().resampleAudioFile(path: path)
    }

    public static func runParakeet(samples: [Float]) async throws -> AsrRun {
        let clock = ContinuousClock()
        let loadStart = clock.now
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        let loadSeconds = seconds(clock.now - loadStart)

        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let start = clock.now
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return makeRun(engine: "parakeet-tdt-v3", samples: samples, loadSeconds: loadSeconds,
                       processingSeconds: seconds(clock.now - start), text: result.text)
    }

    /// `language` nil lets Whisper auto-detect; pass "ru" or "en" to force it.
    public static func runWhisper(samples: [Float], language: String?, model: String = defaultWhisperModel) async throws -> AsrRun {
        let clock = ContinuousClock()
        let loadStart = clock.now
        let pipeline = try await WhisperKit(WhisperKitConfig(model: model))
        let loadSeconds = seconds(clock.now - loadStart)

        let options = DecodingOptions(task: .transcribe, language: language, detectLanguage: language == nil)
        let start = clock.now
        let results = await pipeline.transcribe(audioArrays: [samples], decodeOptions: options)
        let text = (results.first ?? nil)?.map(\.text).joined(separator: " ") ?? ""
        return makeRun(engine: "whisperkit-\(model)", samples: samples, loadSeconds: loadSeconds,
                       processingSeconds: seconds(clock.now - start), text: text)
    }

    private static func makeRun(engine: String, samples: [Float], loadSeconds: Double,
                                processingSeconds: Double, text: String) -> AsrRun {
        let audioSeconds = Double(samples.count) / sampleRate
        return AsrRun(
            engine: engine,
            audioSeconds: audioSeconds,
            loadSeconds: loadSeconds,
            processingSeconds: processingSeconds,
            rtfx: processingSeconds > 0 ? audioSeconds / processingSeconds : 0,
            peakRSSMB: ProcessMetrics.peakResidentMegabytes(),
            thermalState: ProcessMetrics.thermalStateName(),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

enum ProcessMetrics {
    /// Peak resident set size of this process (`ru_maxrss` is in bytes on macOS).
    static func peakResidentMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576
    }

    static func thermalStateName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
