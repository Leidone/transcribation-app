import AudioCapture
import Foundation
import Transcription

/// The transcription during the call, when the person turned it on: phrases appear on the recording screen a few
/// seconds after they are said. The full transcript is still made after the call.
extension AppModel {
    /// How many phrases the recording screen keeps; older ones scroll away.
    private static let keptLiveLines = 300

    /// A sink for the recorder, or `nil` when the transcription during the call is off. Starts the transcriber.
    func startLiveTranscription() -> (@Sendable (LiveAudio) -> Void)? {
        stopLiveTranscription()
        liveLines = []
        liveStats = LiveStats()
        guard preferences.transcribesLive else { return nil }

        let pipeline = pipeline
        let transcriber = LiveTranscriber { samples in try await pipeline.recognisePhrase(samples) }
        let (audio, audioSink) = AsyncStream<LiveAudio>.makeStream(bufferingPolicy: .bufferingNewest(3_000))
        liveTasks = [
            // One reader keeps the pieces in order; the transcriber only cuts them, recognition runs on its own.
            Task.detached { for await piece in audio { await transcriber.feed(piece) } },
            Task { [weak self] in
                for await update in transcriber.updates {
                    guard let self else { return }
                    switch update {
                    case .line(let line):
                        self.liveLines = Array((self.liveLines + [line]).suffix(Self.keptLiveLines))
                    case .stats(let stats):
                        self.liveStats = stats
                    }
                }
            },
        ]
        liveTranscriber = transcriber
        liveAudioSink = audioSink
        return { piece in audioSink.yield(piece) }
    }

    func stopLiveTranscription() {
        liveAudioSink?.finish()
        liveAudioSink = nil
        for task in liveTasks { task.cancel() }
        liveTasks = []
        if let transcriber = liveTranscriber {
            Task { await transcriber.stop() }
        }
        liveTranscriber = nil
    }
}
