#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import os

/// Records the audio of one running app and the microphone as two separate lossless streams — or, for a meeting
/// in a room (`SourceApp.inPerson`), the microphone alone.
public actor ScreenCaptureRecorder {
    private struct ActiveRecording {
        let stream: SCStream
        let handler: StreamHandler
        let appWriter: AudioFileWriter
        let micWriter: AudioFileWriter
        let consumers: [Task<Void, Never>]
        let directory: URL
        let source: SourceApp
        let startedAt: Date
        /// On the clock of the chunks' PTS (host time), for measuring silence from the start.
        let startedAtHostTime: Double
    }

    private var active: ActiveRecording?
    private var lifecycle = RecordingLifecycle()
    /// The marker kept next to the recording until it stops, so a crash does not lose the stream alignment.
    private var partial: (session: PartialSession, folder: URL)?
    /// Pauses of the running recording; sound stamped inside one is not written.
    private var pauses = PauseClock()

    public init() {}

    public var isRecording: Bool { lifecycle.phase == .recording }

    /// Starts recording `app` and the microphone. `live`, when given, receives both streams as 16 kHz mono while
    /// they are recorded, for the transcription during the call; the files are written the same either way.
    public func start(
        app: SourceApp, outputDirectory: URL, live: (@Sendable (LiveAudio) -> Void)? = nil
    ) async throws {
        try lifecycle.beginStart()
        do {
            try await begin(app: app, outputDirectory: outputDirectory, live: live)
            lifecycle.markRecording()
        } catch {
            lifecycle.markStopped()
            removeMarker()
            throw error
        }
    }

    private func begin(app: SourceApp, outputDirectory: URL, live: (@Sendable (LiveAudio) -> Void)?) async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.screenRecordingDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        let filter: SCContentFilter
        if app.isInPerson {
            // No app's sound is captured (see the configuration); the filter only has to name a display.
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        } else {
            guard let runningApp = content.applications.first(where: { $0.bundleIdentifier == app.bundleID }) else {
                throw CaptureError.sourceUnavailable(bundleID: app.bundleID)
            }
            filter = SCContentFilter(display: display, including: [runningApp], exceptingWindows: [])
        }

        let startedAt = Date()
        let directory = outputDirectory.appending(
            path: "\(RecordingTimestamp.folderName(startedAt))-\(app.bundleID)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = PartialSession(id: UUID(), startedAt: startedAt, app: app, method: .screenCaptureKit)
        try marker.write(in: directory)
        partial = (marker, directory)
        pauses = PauseClock()
        let startedAtHostTime = Self.hostTime()

        let appWriter = AudioFileWriter(url: directory.appending(path: "app.caf"))
        let micWriter = AudioFileWriter(url: directory.appending(path: "mic.caf"))
        let (appChunks, appContinuation) = AsyncStream<PCMChunk>.makeStream()
        let (micChunks, micContinuation) = AsyncStream<PCMChunk>.makeStream()
        let handler = StreamHandler(appChunks: appContinuation, micChunks: micContinuation)

        let stream = SCStream(
            filter: filter, configuration: Self.audioOnlyConfiguration(capturesApps: !app.isInPerson), delegate: handler
        )
        let queue = DispatchQueue(label: "app.callrecorder.capture", qos: .userInitiated)
        // In a room no app's sound is captured, so there is nothing to listen to on that output.
        if !app.isInPerson { try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: queue) }
        try stream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: queue)
        try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: queue)

        let consumers = [
            Task { await self.consume(appChunks, into: appWriter, noting: .app, live: live) },
            Task { await self.consume(micChunks, into: micWriter, noting: .mic, live: live) },
        ]
        do {
            try await stream.startCapture()
        } catch {
            appContinuation.finish()
            micContinuation.finish()
            removeMarker()
            throw error
        }
        active = ActiveRecording(
            stream: stream, handler: handler, appWriter: appWriter, micWriter: micWriter,
            consumers: consumers, directory: directory, source: app, startedAt: startedAt,
            startedAtHostTime: startedAtHostTime
        )
        Logger.capture.info("recording started app=\(app.bundleID, privacy: .public)")
    }

    /// Writes each chunk and notes when the stream's first one arrived, so an interrupted recording can still be
    /// aligned. With `live`, the chunk also goes on, resampled, to the transcription during the call.
    private func consume(
        _ chunks: AsyncStream<PCMChunk>, into writer: AudioFileWriter, noting stream: PartialSession.Stream,
        live: (@Sendable (LiveAudio) -> Void)?
    ) async {
        var noted = false
        let resampler = live == nil ? nil : MonoResampler()
        for await chunk in chunks {
            guard !pauses.drops(at: chunk.pts) else { continue }
            await writer.append(chunk)
            if let live, let resampler {
                let samples = resampler.convert(chunk.buffer)
                if !samples.isEmpty {
                    live(LiveAudio(stream: stream == .app ? .app : .mic, samples: samples, pts: chunk.pts))
                }
            }
            guard !noted else { continue }
            noted = true
            noteStart(of: stream, at: chunk.pts)
        }
    }

    private func noteStart(of stream: PartialSession.Stream, at pts: Double) {
        guard let partial else { return }
        let updated = partial.session.noting(stream, startedAt: pts)
        self.partial = (updated, partial.folder)
        do {
            try updated.write(in: partial.folder)
        } catch {
            Logger.capture.error("cannot update the recording marker: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeMarker() {
        guard let partial else { return }
        self.partial = nil
        do {
            try FileManager.default.removeItem(at: partial.folder.appending(path: PartialSession.fileName))
        } catch {
            Logger.capture.error("cannot remove the recording marker: \(error.localizedDescription, privacy: .public)")
        }
    }

    public var isPaused: Bool { pauses.isPaused }

    /// Stops writing sound until `resume()`; the recording stays open. Returns `false` when nothing is recorded.
    @discardableResult
    public func pause() -> Bool {
        guard active != nil else { return false }
        pauses.pause(at: Self.hostTime())
        Logger.capture.info("recording paused")
        return true
    }

    @discardableResult
    public func resume() -> Bool {
        guard active != nil else { return false }
        pauses.resume(at: Self.hostTime())
        Logger.capture.info("recording resumed")
        return true
    }

    /// Seconds since the others and since the person last made a sound (since the start, if they have not);
    /// `nil` when nothing is being recorded.
    public func silence() async -> (others: TimeInterval, me: TimeInterval)? {
        guard let recording = active else { return nil }
        let now = Self.hostTime()
        let elapsed = max(0, now - recording.startedAtHostTime)
        let othersSound = await recording.appWriter.lastSoundEnd ?? recording.startedAtHostTime
        let mySound = await recording.micWriter.lastSoundEnd ?? recording.startedAtHostTime
        // Clamped, so a stream on an unexpected clock can never make a call look quieter than it has been long.
        let others = min(elapsed, max(0, now - othersSound))
        let me = min(elapsed, max(0, now - mySound))
        return (pauses.capSilence(others, at: now), pauses.capSilence(me, at: now))
    }

    /// The microphone has sent sound, but every sample was exactly zero: it is muted somewhere.
    public func microphoneIsMuted() async -> Bool {
        guard let recording = active else { return false }
        let written = await recording.micWriter.framesWritten
        let hasSignal = await recording.micWriter.hasSignal
        return written > 0 && !hasSignal
    }

    /// Notes the current moment as important and writes it next to the recording at once, so a crash does not lose
    /// it. Returns the moment in seconds from the start of the app stream (the transcript's clock), or `nil` when
    /// nothing is being recorded or the mark could not be saved.
    public func markImportant() -> TimeInterval? {
        guard let recording = active else { return nil }
        // The transcript's clock starts with the app stream, or with the microphone in a room. Before that stream
        // sent its first sound, the start of the recording is the best guess of its zero.
        let first = recording.source.isInPerson ? partial?.session.micFirstPTS : partial?.session.appFirstPTS
        let origin = first ?? recording.startedAtHostTime
        // Recorded time only: the files hold no sound from the pauses.
        let moment = pauses.recordedTime(from: origin, to: Self.hostTime())
        do {
            let marks = try ImportantMarksStore.load(from: recording.directory).adding(moment)
            try ImportantMarksStore.save(marks, in: recording.directory)
            Logger.capture.info("important moment marked at \(moment, privacy: .public)")
            return moment
        } catch {
            Logger.capture.error("cannot save a mark: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The clock ScreenCaptureKit stamps its buffers with.
    private static func hostTime() -> Double {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }

    /// Stops capture, closes the files and writes what describes them (`session.json`, or `import.json` for a
    /// meeting in a room). Returns the recording's id.
    public func stop() async throws -> UUID {
        try lifecycle.beginStop()
        defer { lifecycle.markStopped() }
        guard let recording = active else { throw CaptureError.notRecording }
        active = nil
        let id = partial?.session.id ?? UUID()
        // Removed however the stop ends: after session.json on success, and on failure the folder is left as
        // plain audio, as before.
        defer { removeMarker() }
        do {
            try await recording.stream.stopCapture()
        } catch {
            // The system may already have stopped the stream (revoked permission, display change). The audio
            // captured so far is still on disk and must be finalised, so this is logged, not fatal.
            Logger.capture.error("stopCapture failed: \(error.localizedDescription, privacy: .public)")
        }
        recording.handler.finish()
        for consumer in recording.consumers { await consumer.value }

        let appSummary = await recording.appWriter.finish()
        let micSummary = await recording.micWriter.finish()
        if recording.source.isInPerson {
            guard micSummary != nil else { throw CaptureError.noAudioReceived(stream: "microphone") }
            try InPersonRecording.save(id: id, startedAt: recording.startedAt, audioFile: "mic.caf", in: recording.directory)
            Logger.capture.info("in-person recording saved")
            return id
        }
        guard let appSummary else { throw CaptureError.noAudioReceived(stream: "app") }
        guard let micSummary else { throw CaptureError.noAudioReceived(stream: "microphone") }

        let session = RecordingSession(
            id: id,
            startedAt: recording.startedAt,
            app: recording.source,
            method: .screenCaptureKit,
            streams: Streams(
                app: Self.streamInfo(file: "app.caf", from: appSummary),
                mic: Self.streamInfo(file: "mic.caf", from: micSummary)
            )
        )
        try session.encoded().write(to: recording.directory.appending(path: "session.json"))
        Logger.capture.info("recording saved offset=\(session.syncOffsetSeconds, privacy: .public)")
        return id
    }

    private static func streamInfo(file: String, from summary: AudioFileWriter.Summary) -> StreamInfo {
        StreamInfo(
            file: file, sampleRate: summary.sampleRate, channels: summary.channels,
            firstPTS: summary.firstPTS, droppedBuffers: summary.droppedBuffers
        )
    }

    /// Audio only: the mandatory video output is kept as small and rare as possible.
    private static func audioOnlyConfiguration(capturesApps: Bool) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = capturesApps
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        return configuration
    }

}

/// Receives ScreenCaptureKit callbacks on the capture queue and forwards audio in arrival order.
private final class StreamHandler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let appChunks: AsyncStream<PCMChunk>.Continuation
    private let micChunks: AsyncStream<PCMChunk>.Continuation

    init(appChunks: AsyncStream<PCMChunk>.Continuation, micChunks: AsyncStream<PCMChunk>.Continuation) {
        self.appChunks = appChunks
        self.micChunks = micChunks
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            if let chunk = sampleBuffer.makePCMChunk() { appChunks.yield(chunk) }
        case .microphone:
            if let chunk = sampleBuffer.makePCMChunk() { micChunks.yield(chunk) }
        default:
            break // the 2×2 video frames are not needed
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Logger.capture.error("stream stopped: \(error.localizedDescription, privacy: .public)")
        finish()
    }

    func finish() {
        appChunks.finish()
        micChunks.finish()
    }
}
#endif
