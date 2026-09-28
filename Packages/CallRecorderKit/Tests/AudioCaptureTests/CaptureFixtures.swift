import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

/// Folders shaped like the app's own captures, for the compression and recovery tests.
enum CaptureFixtures {
    static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "captures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A lossless stream with a tone in it, the way `AudioFileWriter` leaves it (32-bit float CAF).
    static func writeTone(_ url: URL, seconds: Double, sampleRate: Double, channels: AVAudioChannelCount) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) { samples[frame] = sinf(Float(frame) * 0.03) * 0.4 }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    /// A finished capture: `app.caf` (48 kHz stereo), `mic.caf` (24 kHz mono) and `session.json`.
    @discardableResult
    static func writeCapture(in root: URL, folder: String = "call", seconds: Double = 2) throws -> (URL, RecordingSession) {
        let directory = root.appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeTone(directory.appending(path: "app.caf"), seconds: seconds, sampleRate: 48_000, channels: 2)
        try writeTone(directory.appending(path: "mic.caf"), seconds: seconds, sampleRate: 24_000, channels: 1)
        let session = RecordingSession(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            app: SourceApp(bundleID: "us.zoom.xos", name: "zoom.us"),
            method: .screenCaptureKit,
            streams: Streams(
                app: StreamInfo(file: "app.caf", sampleRate: 48_000, channels: 2, firstPTS: 100, droppedBuffers: 0),
                mic: StreamInfo(file: "mic.caf", sampleRate: 24_000, channels: 1, firstPTS: 100.25, droppedBuffers: 0)
            )
        )
        try session.encoded().write(to: directory.appending(path: "session.json"))
        return (directory, session)
    }

    static func frames(of url: URL) throws -> AVAudioFramePosition {
        try AVAudioFile(forReading: url).length
    }

    static func size(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
