import AudioCapture
import AVFoundation
import Foundation
import Localization
import Observation

/// Builds what the player plays. The app's own captures are two files — the other participants and the
/// microphone — so they are mixed on the fly, with the microphone moved onto the app stream's clock the same way
/// the transcript is. Times in the player therefore match the times printed next to transcript lines.
public enum PlaybackComposition {
    public static func asset(for audio: RecordingAudio) async throws -> AVAsset {
        switch audio {
        case .single(let url):
            return AVURLAsset(url: url)
        case .separated(let app, let mic, let offset):
            let composition = AVMutableComposition()
            try await insert(AVURLAsset(url: app), into: composition, skipping: 0, at: 0)
            // A positive offset: the microphone started later, so it plays later. A negative one: it started
            // earlier, so its first seconds come before the app stream's zero and are left out.
            try await insert(AVURLAsset(url: mic), into: composition, skipping: max(0, -offset), at: max(0, offset))
            return composition
        }
    }

    private static func insert(
        _ source: AVURLAsset, into composition: AVMutableComposition, skipping lead: Double, at start: Double
    ) async throws {
        guard let track = try await source.loadTracks(withMediaType: .audio).first,
              let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return }
        let length = try await source.load(.duration)
        let skip = CMTime(seconds: lead, preferredTimescale: 600)
        guard length > skip else { return }
        try target.insertTimeRange(
            CMTimeRange(start: skip, end: length), of: track, at: CMTime(seconds: start, preferredTimescale: 600)
        )
    }
}

/// Plays one recording and reports where it is, so the transcript can follow along and a click on a line or a
/// task can jump to the moment it was said.
@Observable
@MainActor
public final class PlaybackController {
    public static let rates: [Float] = [1, 1.25, 1.5, 2]

    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying = false
    public private(set) var isReady = false
    public private(set) var errorMessage: String?
    public private(set) var rate: Float = 1

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var loadedAudio: RecordingAudio?

    public init() {}

    /// Prepares `audio`; a second call with the same audio keeps the position, and so does the same recording
    /// with its audio swapped for compressed files (it may be playing while that happens).
    public func load(_ audio: RecordingAudio?, duration knownDuration: TimeInterval) async {
        guard audio != loadedAudio else { return }
        let resume = audio != nil && audio?.folder == loadedAudio?.folder ? (time: currentTime, playing: isPlaying) : nil
        stop()
        loadedAudio = audio
        duration = knownDuration
        isReady = false
        errorMessage = nil
        guard let audio else { return }
        do {
            let asset = try await PlaybackComposition.asset(for: audio)
            guard loadedAudio == audio else { return } // another recording was opened meanwhile
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            observeTime()
            isReady = true
            if let resume { seek(to: resume.time, startsPlaying: resume.playing) }
        } catch {
            errorMessage = tr("Не удалось открыть аудио: ", "Could not open the audio: ") + error.localizedDescription
        }
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func play() {
        guard isReady else { return }
        if currentTime >= duration - 0.25 { seek(to: 0) }
        player.playImmediately(atRate: rate)
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    /// Jumps to `time` (clamped to the recording) and keeps playing if it was playing; `startsPlaying` starts it.
    public func seek(to time: TimeInterval, startsPlaying: Bool = false) {
        guard isReady else { return }
        let target = min(max(0, time), duration)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if startsPlaying { play() }
    }

    public func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    public func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying { player.rate = newRate }
    }

    public func stop() {
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
        currentTime = 0
        isReady = false
    }

    private func observeTime() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if self.isPlaying, self.player.rate == 0, self.currentTime >= self.duration - 0.25 {
                    self.isPlaying = false
                }
            }
        }
    }
}
