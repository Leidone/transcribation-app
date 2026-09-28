import FluidAudio
import Foundation

public struct DiarizedSegment: Codable, Equatable, Sendable {
    public let speaker: String
    public let start: Double
    public let end: Double
}

public struct DiarizationRun: Codable, Sendable {
    public let engine: String
    public let audioSeconds: Double
    public let processingSeconds: Double
    public let speakerCount: Int
    public let segments: [DiarizedSegment]

    /// `start,end,speaker` rows, the format `Tools/eval/der.py` reads.
    public var csv: String {
        let rows = segments.map { String(format: "%.3f,%.3f,%@", $0.start, $0.end, $0.speaker) }
        return (["start,end,speaker"] + rows).joined(separator: "\n") + "\n"
    }
}

public enum DiarizationBenchmark {
    /// Diarizes the other participants' stream only; the microphone stream is always "me".
    public static func runFluidAudio(samples: [Float]) async throws -> DiarizationRun {
        let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
        try await manager.prepareModels()

        let clock = ContinuousClock()
        let start = clock.now
        let result = try await manager.process(audio: samples)
        let elapsed = clock.now - start

        let segments = result.segments.map {
            DiarizedSegment(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
        return DiarizationRun(
            engine: "fluidaudio-offline",
            audioSeconds: Double(samples.count) / AsrBenchmark.sampleRate,
            processingSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            speakerCount: Set(segments.map(\.speaker)).count,
            segments: segments
        )
    }
}
