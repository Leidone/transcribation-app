import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

struct RecordingLibraryTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeAudio(_ url: URL, seconds: Double) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @discardableResult
    private func writeRecording(
        in root: URL, folder: String, startedAt: TimeInterval, appSeconds: Double, micSeconds: Double
    ) throws -> RecordingSession {
        let directory = root.appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeAudio(directory.appending(path: "app.caf"), seconds: appSeconds)
        try writeAudio(directory.appending(path: "mic.caf"), seconds: micSeconds)
        let stream = { (file: String) in
            StreamInfo(file: file, sampleRate: 48_000, channels: 2, firstPTS: 1, droppedBuffers: 0)
        }
        let session = RecordingSession(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: startedAt),
            app: SourceApp(bundleID: "us.zoom.xos", name: "zoom.us"),
            method: .screenCaptureKit,
            streams: Streams(app: stream("app.caf"), mic: stream("mic.caf"))
        )
        try session.encoded().write(to: directory.appending(path: "session.json"))
        return session
    }

    @Test("loads recordings newest first and measures the longest stream")
    func loadsNewestFirst() throws {
        // Arrange
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = try writeRecording(in: root, folder: "a", startedAt: 1_800_000_000, appSeconds: 2, micSeconds: 1)
        let newer = try writeRecording(in: root, folder: "b", startedAt: 1_800_003_600, appSeconds: 1, micSeconds: 3)

        // Act
        let loaded = RecordingLibrary.load(from: root)

        // Assert
        #expect(loaded.map(\.id) == [newer.id, older.id])
        #expect(abs(loaded[0].duration - 3) < 0.01)
        #expect(abs(loaded[1].duration - 2) < 0.01)
    }

    @Test("skips folders without a sidecar and folders with a corrupt one")
    func skipsUnreadableFolders() throws {
        // Arrange
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let good = try writeRecording(in: root, folder: "good", startedAt: 1_800_000_000, appSeconds: 1, micSeconds: 1)
        try FileManager.default.createDirectory(at: root.appending(path: "empty"), withIntermediateDirectories: true)
        let broken = root.appending(path: "broken")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: broken.appending(path: "session.json"))

        // Act
        let loaded = RecordingLibrary.load(from: root)

        // Assert
        #expect(loaded.map(\.id) == [good.id])
    }

    @Test("a missing root is an empty library")
    func missingRoot() {
        let root = FileManager.default.temporaryDirectory.appending(path: "does-not-exist-\(UUID().uuidString)")

        #expect(RecordingLibrary.load(from: root).isEmpty)
    }

    private func writeCompressedAudio(_ url: URL, seconds: Double) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
        ]
        try AVAudioFile(forWriting: url, settings: settings).write(from: buffer)
    }

    @Test("audio put into a folder by hand is listed, in several formats, with a stable id")
    func readsLooseAudioInSeveralFormats() throws {
        // Arrange
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for (folder, file) in [("a", "notes.wav"), ("b", "notes.aiff"), ("c", "notes.caf")] {
            let directory = root.appending(path: folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeAudio(directory.appending(path: file), seconds: 1.5)
        }
        let compressed = root.appending(path: "d")
        try FileManager.default.createDirectory(at: compressed, withIntermediateDirectories: true)
        try writeCompressedAudio(compressed.appending(path: "notes.m4a"), seconds: 1.5)

        // Act
        let first = RecordingLibrary.load(from: root)
        let second = RecordingLibrary.load(from: root)

        // Assert
        #expect(first.count == 4)
        #expect(first.allSatisfy { abs($0.duration - 1.5) < 0.1 })
        #expect(first.allSatisfy { $0.title == "notes" && $0.appName == nil })
        #expect(Set(first.map(\.id)) == Set(second.map(\.id)), "ids must not change between loads")
    }

    @Test("a folder with no audio or only unsupported files is not a recording")
    func ignoresFoldersWithoutAudio() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = root.appending(path: "notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("text".utf8).write(to: notes.appending(path: "readme.txt"))
        try Data("x".utf8).write(to: notes.appending(path: "voice.ogg"))
        try Data("stray".utf8).write(to: root.appending(path: "stray-file.wav"))

        #expect(RecordingLibrary.load(from: root).isEmpty)
    }

    @Test("a captured recording keeps its two streams and the stream offset")
    func capturedRecordingIsSeparated() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRecording(in: root, folder: "call", startedAt: 1_800_000_000, appSeconds: 1, micSeconds: 1)

        let recording = try #require(RecordingLibrary.load(from: root).first)

        guard case .separated(let app, let mic, _) = recording.audio else {
            Issue.record("a capture must keep separate streams")
            return
        }
        #expect(app.lastPathComponent == "app.caf")
        #expect(mic.lastPathComponent == "mic.caf")
        #expect(recording.appName == "zoom.us")
    }

    @Test("a recording whose audio files are gone is skipped")
    func missingAudio() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRecording(in: root, folder: "x", startedAt: 1_800_000_000, appSeconds: 1, micSeconds: 1)
        try FileManager.default.removeItem(at: root.appending(path: "x/app.caf"))
        try FileManager.default.removeItem(at: root.appending(path: "x/mic.caf"))

        #expect(RecordingLibrary.load(from: root).isEmpty)
    }
}
