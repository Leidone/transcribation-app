import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

struct RecordingCompressionTests {
    @Test("both streams become AAC of the same length, and session.json points at them")
    func compressesBothStreams() throws {
        // Arrange
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, original) = try CaptureFixtures.writeCapture(in: root, seconds: 3)
        let appFrames = try CaptureFixtures.frames(of: folder.appending(path: "app.caf"))
        let micFrames = try CaptureFixtures.frames(of: folder.appending(path: "mic.caf"))

        // Act
        let outcome = try RecordingCompression.compress(folder: folder)

        // Assert
        guard case .compressed(let saved) = outcome else {
            Issue.record("expected the capture to be compressed, got \(outcome)")
            return
        }
        #expect(saved > 0)
        let session = try RecordingSession.decode(from: Data(contentsOf: folder.appending(path: "session.json")))
        #expect(session.streams.app.file == "app.m4a")
        #expect(session.streams.mic.file == "mic.m4a")
        #expect(session.id == original.id)
        #expect(session.syncOffsetSeconds == original.syncOffsetSeconds, "the stream alignment must survive")
        #expect(try CaptureFixtures.frames(of: folder.appending(path: "app.m4a")) == appFrames)
        #expect(try CaptureFixtures.frames(of: folder.appending(path: "mic.m4a")) == micFrames)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "app.caf").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "mic.caf").path))
    }

    @Test("the compressed capture is listed with its new files and the same length")
    func libraryReadsCompressedCapture() throws {
        // Arrange
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, _) = try CaptureFixtures.writeCapture(in: root, seconds: 2)
        let before = try #require(RecordingLibrary.load(from: root).first)

        // Act
        _ = try RecordingCompression.compress(folder: folder)
        let after = try #require(RecordingLibrary.load(from: root).first)

        // Assert
        #expect(after.id == before.id)
        #expect(abs(after.duration - before.duration) < 0.001)
        guard case .separated(let app, let mic, _) = after.audio else {
            Issue.record("a compressed capture must keep its two streams")
            return
        }
        #expect(app.lastPathComponent == "app.m4a")
        #expect(mic.lastPathComponent == "mic.m4a")
    }

    @Test("running it again on a compressed capture changes nothing")
    func secondRunIsANoOp() throws {
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, _) = try CaptureFixtures.writeCapture(in: root)
        _ = try RecordingCompression.compress(folder: folder)
        let sizeAfterFirst = try CaptureFixtures.size(of: folder.appending(path: "app.m4a"))

        let outcome = try RecordingCompression.compress(folder: folder)

        #expect(outcome == .alreadyCompressed)
        #expect(try CaptureFixtures.size(of: folder.appending(path: "app.m4a")) == sizeAfterFirst)
    }

    @Test("lossless files left behind by an interrupted run are cleaned up")
    func removesLeftoversOfAnInterruptedRun() throws {
        // Arrange: compressed, then the old stream put back as if the deletion never happened
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, _) = try CaptureFixtures.writeCapture(in: root)
        _ = try RecordingCompression.compress(folder: folder)
        try CaptureFixtures.writeTone(folder.appending(path: "app.caf"), seconds: 1, sampleRate: 48_000, channels: 2)

        // Act
        let outcome = try RecordingCompression.compress(folder: folder)

        // Assert
        #expect(outcome == .alreadyCompressed)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "app.caf").path))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "app.m4a").path))
    }

    @Test("imports and audio put there by hand are left as they are")
    func leavesOtherFoldersAlone() throws {
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "loose")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appending(path: "notes.caf")
        try CaptureFixtures.writeTone(audio, seconds: 1, sampleRate: 48_000, channels: 1)

        let outcome = try RecordingCompression.compress(folder: folder)

        #expect(outcome == .notApplicable)
        #expect(FileManager.default.fileExists(atPath: audio.path))
    }

    @Test("an hour of lossless capture is estimated at about 1.7 GB, and AAC at about 20 times less")
    func sizeEstimates() {
        #expect(abs(DiskBudget.losslessBytesPerSecond * 3_600 / 1e9 - 1.73) < 0.01)
        #expect(DiskBudget.losslessBytesPerSecond / RecordingCompression.bytesPerSecond >= 20)
    }
}
