import FluidAudio
import Foundation

public struct PipelineInput: Sendable {
    public let appAudio: URL
    public let micAudio: URL
    /// `RecordingSession.syncOffsetSeconds`: how much later the microphone stream starts than the app stream.
    public let micOffsetSeconds: Double

    public init(appAudio: URL, micAudio: URL, micOffsetSeconds: Double) {
        self.appAudio = appAudio
        self.micAudio = micAudio
        self.micOffsetSeconds = micOffsetSeconds
    }
}

public enum PipelineStage: Sendable, Equatable {
    case loadingModels
    case recognizingOthers
    case identifyingSpeakers
    case recognizingMe
    case finishing
}

/// Recording → transcript, fully on this Mac. The microphone stream is always "Я"; the other participants come
/// from the app stream, where a diarizer tells their voices apart.
public actor TranscriptionPipeline {
    public static let engineName = "parakeet-tdt-v3 + fluidaudio-offline"
    public static let myName = "Я"

    private static let sampleRate = 16_000.0
    /// The recogniser needs about a second of audio; shorter phrases are padded with silence.
    private static let minimumSamples = 16_000

    private var recogniser: AsrManager?
    private var speechDetector: VadManager?

    public init() {}

    public func transcribe(
        input: PipelineInput,
        progress: @Sendable (PipelineStage) -> Void = { _ in }
    ) async throws -> TranscriptionResult {
        let clock = ContinuousClock()
        let started = clock.now
        progress(.loadingModels)
        let recogniser = try await loadRecogniser()
        let detector = try await loadSpeechDetector()

        progress(.recognizingOthers)
        let appSamples = try AudioConverter().resampleAudioFile(path: input.appAudio.path)
        let othersText = try await recognise(appSamples, recogniser: recogniser, detector: detector)

        progress(.identifyingSpeakers)
        let voices = try await diarize(appSamples)
        let others = SpeakerAssignment.labelling(othersText, turns: voices.turns)

        progress(.recognizingMe)
        let micSamples = try AudioConverter().resampleAudioFile(path: input.micAudio.path)
        let mine = try await recognise(micSamples, recogniser: recogniser, detector: detector).map {
            Utterance(start: $0.start, end: $0.end, speaker: Self.myName, text: $0.text)
        }

        progress(.finishing)
        let merged = TranscriptMerge.merge(me: mine, others: others.utterances, micOffsetSeconds: input.micOffsetSeconds)
        return result(merged, voices: voices.embeddings, labels: others.labels, since: started, clock: clock)
    }

    /// One mixed audio file (an import, or a recording made elsewhere): every voice is told apart by the diarizer
    /// and named "Спикер 1, 2, …"; nobody is "Я" because there is no separate microphone stream.
    public func transcribeSingle(
        audio: URL,
        progress: @Sendable (PipelineStage) -> Void = { _ in }
    ) async throws -> TranscriptionResult {
        let clock = ContinuousClock()
        let started = clock.now
        progress(.loadingModels)
        let recogniser = try await loadRecogniser()
        let detector = try await loadSpeechDetector()

        progress(.recognizingOthers)
        let samples = try AudioConverter().resampleAudioFile(path: audio.path)
        let text = try await recognise(samples, recogniser: recogniser, detector: detector)

        progress(.identifyingSpeakers)
        let voices = try await diarize(samples)

        progress(.finishing)
        let labelled = SpeakerAssignment.labelling(text, turns: voices.turns, namePrefix: "Спикер")
        return result(labelled.utterances, voices: voices.embeddings, labels: labelled.labels, since: started, clock: clock)
    }

    /// Recognises one short phrase (16 kHz mono) for the transcription during a call, with the same model as the
    /// full transcript; the model is loaded on first use.
    public func recognisePhrase(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let recogniser = try await loadRecogniser()
        var chunk = samples
        if chunk.count < Self.minimumSamples {
            chunk += [Float](repeating: 0, count: Self.minimumSamples - chunk.count)
        }
        var state = TdtDecoderState.make(decoderLayers: await recogniser.decoderLayerCount)
        return try await recogniser.transcribe(chunk, decoderState: &state).text
    }

    /// Downloads (once) and loads every model, so the first real transcription does not wait for them. The
    /// handler gets the download progress of the recogniser, the largest of the models, from 0 to 1.
    public func prepareModels(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        _ = try await loadRecogniser(progress: progress)
        _ = try await loadSpeechDetector()
        try await OfflineDiarizerManager(config: OfflineDiarizerConfig()).prepareModels()
    }

    private func result(
        _ utterances: [Utterance], voices: [String: [Float]], labels: [String: String],
        since started: ContinuousClock.Instant, clock: ContinuousClock
    ) -> TranscriptionResult {
        let elapsed = clock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let named = Dictionary(labels.compactMap { id, label in voices[id].map { (label, $0) } }, uniquingKeysWith: { first, _ in first })
        return TranscriptionResult(
            transcript: StoredTranscript(
                engine: Self.engineName, createdAt: Date(), utterances: utterances, processingSeconds: seconds
            ),
            voiceprints: Voiceprints(voices: named)
        )
    }

    // MARK: Steps

    private func recognise(_ samples: [Float], recogniser: AsrManager, detector: VadManager) async throws -> [TimedText] {
        var segmentation = VadSegmentationConfig.default
        segmentation.minSpeechDuration = 0.25
        segmentation.minSilenceDuration = 0.7
        segmentation.maxSpeechDuration = 25
        let segments = try await detector.segmentSpeech(samples, config: segmentation)

        var phrases: [TimedText] = []
        for segment in segments {
            let first = max(0, Int(segment.startTime * Self.sampleRate))
            let last = min(samples.count, Int(segment.endTime * Self.sampleRate))
            guard last > first else { continue }

            var chunk = Array(samples[first..<last])
            if chunk.count < Self.minimumSamples {
                chunk += [Float](repeating: 0, count: Self.minimumSamples - chunk.count)
            }
            var state = TdtDecoderState.make(decoderLayers: await recogniser.decoderLayerCount)
            let result = try await recogniser.transcribe(chunk, decoderState: &state)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                phrases.append(TimedText(start: segment.startTime, end: segment.endTime, text: text))
            }
        }
        return phrases
    }

    /// Who spoke when, and one average embedding per diarizer speaker id.
    private func diarize(_ samples: [Float]) async throws -> (turns: [SpeakerTurn], embeddings: [String: [Float]]) {
        let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
        try await manager.prepareModels()
        let result = try await manager.process(audio: samples)
        let turns = result.segments.map {
            SpeakerTurn(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), speakerID: $0.speakerId)
        }
        return (turns, result.speakerDatabase ?? [:])
    }

    private func loadRecogniser(progress: (@Sendable (Double) -> Void)? = nil) async throws -> AsrManager {
        if let recogniser { return recogniser }
        var handler: ProgressHandler?
        if let progress {
            handler = { @Sendable (download: DownloadProgress) in progress(download.fractionCompleted) }
        }
        let models = try await AsrModels.downloadAndLoad(version: .v3, progressHandler: handler)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        recogniser = manager
        return manager
    }

    private func loadSpeechDetector() async throws -> VadManager {
        if let speechDetector { return speechDetector }
        let detector = try await VadManager(config: VadConfig(defaultThreshold: 0.75))
        speechDetector = detector
        return detector
    }
}
