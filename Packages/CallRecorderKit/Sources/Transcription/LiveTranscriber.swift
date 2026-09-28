import AudioCapture
import Foundation
import os

/// One phrase recognised during the call.
public struct LiveLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Said into the person's own microphone; otherwise by the other participants.
    public let isMe: Bool
    /// Seconds from the start of the recording.
    public let time: TimeInterval
    public let text: String

    public init(id: UUID = UUID(), isMe: Bool, time: TimeInterval, text: String) {
        self.id = id
        self.isMe = isMe
        self.time = time
        self.text = text
    }
}

private let liveLog = Logger(subsystem: "app.callrecorder.dev", category: "live")

/// How the transcription during the call keeps up: the seconds of speech recognised, the seconds it took, and the
/// phrases skipped because the Mac fell behind.
public struct LiveStats: Equatable, Sendable {
    public var audioSeconds: Double = 0
    public var processingSeconds: Double = 0
    public var skippedPhrases = 0

    public init() {}

    /// How many times faster than speech the recognition runs; `nil` until something was recognised.
    public var speedFactor: Double? {
        processingSeconds > 0 ? audioSeconds / processingSeconds : nil
    }
}

public enum LiveUpdate: Equatable, Sendable {
    case line(LiveLine)
    case stats(LiveStats)
}

/// Transcribes the call while it goes on, roughly: each stream is cut into phrases at pauses and every phrase is
/// recognised on its own, the person's microphone apart from the others. Nothing is written to disk; the full
/// transcript with the voices told apart is still made after the call.
public actor LiveTranscriber {
    public typealias Recogniser = @Sendable ([Float]) async throws -> String

    /// Phrases waiting beyond this are dropped, oldest first: better a gap than a transcript minutes behind.
    static let maximumBacklog = 6

    public nonisolated let updates: AsyncStream<LiveUpdate>
    private let continuation: AsyncStream<LiveUpdate>.Continuation
    private let recognise: Recogniser

    private var chunkers: [Bool: PhraseChunker] = [true: PhraseChunker(), false: PhraseChunker()]
    /// The capture time of each stream's first sample.
    private var origins: [Bool: Double] = [:]
    private var backlog: [(isMe: Bool, time: TimeInterval, phrase: Phrase)] = []
    private var isWorking = false
    private var isStopped = false
    private var stats = LiveStats()

    public init(recognise: @escaping Recogniser) {
        self.recognise = recognise
        (updates, continuation) = AsyncStream<LiveUpdate>.makeStream(bufferingPolicy: .bufferingNewest(200))
    }

    /// Takes the next piece of a stream; finished phrases are recognised in the background, in order.
    public func feed(_ audio: LiveAudio) {
        guard !isStopped else { return }
        let isMe = audio.stream == .mic
        let origin = origins[isMe] ?? audio.pts
        origins[isMe] = origin
        let phrases = chunkers[isMe, default: PhraseChunker()].feed(audio.samples)
        for phrase in phrases { enqueue(phrase, isMe: isMe, origin: origin) }
    }

    /// Recognises what is still waiting, the phrase being said included, then ends the updates.
    public func finish() async {
        for isMe in [true, false] {
            if let origin = origins[isMe], let phrase = chunkers[isMe]?.flush() {
                enqueue(phrase, isMe: isMe, origin: origin)
            }
        }
        while isWorking {
            try? await Task.sleep(for: .milliseconds(50))
        }
        isStopped = true
        continuation.finish()
    }

    /// Stops at once: what is waiting is dropped, the updates end.
    public func stop() {
        isStopped = true
        backlog = []
        continuation.finish()
    }

    private func enqueue(_ phrase: Phrase, isMe: Bool, origin: Double) {
        // Both streams are measured from the earlier of their first samples: the start of the recording.
        let zero = origins.values.min() ?? origin
        backlog.append((isMe, max(0, origin + phrase.startSeconds - zero), phrase))
        while backlog.count > Self.maximumBacklog {
            backlog.removeFirst()
            stats.skippedPhrases += 1
        }
        guard !isWorking else { return }
        isWorking = true
        Task { await work() }
    }

    private func work() async {
        let clock = ContinuousClock()
        while !isStopped, !backlog.isEmpty {
            let next = backlog.removeFirst()
            let started = clock.now
            let text: String
            do {
                text = try await recognise(next.phrase.samples).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                // One phrase is lost, not the call: logged so a failing recogniser can be told from silence.
                liveLog.error("phrase not recognised: \(error.localizedDescription, privacy: .public)")
                text = ""
            }
            let elapsed = clock.now - started
            guard !isStopped else { break }
            stats.audioSeconds += next.phrase.seconds
            stats.processingSeconds += Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if !text.isEmpty {
                continuation.yield(.line(LiveLine(isMe: next.isMe, time: next.time, text: text)))
            }
            continuation.yield(.stats(stats))
        }
        isWorking = false
    }
}
