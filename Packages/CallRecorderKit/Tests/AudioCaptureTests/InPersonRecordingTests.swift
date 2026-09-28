import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

struct InPersonRecordingTests {
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    /// What the recorder leaves after an in-person meeting: the microphone only, and its metadata.
    @discardableResult
    private func writeMeeting(in root: URL, id: UUID = UUID()) throws -> URL {
        let folder = root.appending(path: "20260928-100000-\(SourceApp.inPerson.bundleID)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try CaptureFixtures.writeTone(folder.appending(path: "mic.caf"), seconds: 2, sampleRate: 24_000, channels: 1)
        try InPersonRecording.save(id: id, startedAt: startedAt, audioFile: "mic.caf", in: folder)
        return folder
    }

    @Test("an in-person meeting is listed under its own name, with the microphone as its source")
    func listedAsInPerson() throws {
        // Arrange
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try writeMeeting(in: root, id: id)

        // Act
        let listed = try #require(RecordingLibrary.load(from: root).first)

        // Assert
        #expect(listed.id == id)
        #expect(listed.title == "Живая встреча")
        #expect(listed.appName == "Микрофон")
        #expect(listed.appBundleID == SourceApp.inPerson.bundleID)
        #expect(listed.startedAt == startedAt)
        guard case .single(let audio) = listed.audio else {
            Issue.record("an in-person meeting has one stream")
            return
        }
        #expect(audio.lastPathComponent == "mic.caf")
    }

    @Test("an in-person meeting is compressed like a call, and stays the same length")
    func compressed() throws {
        // Arrange
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try writeMeeting(in: root)
        let frames = try CaptureFixtures.frames(of: folder.appending(path: "mic.caf"))

        // Act
        let outcome = try RecordingCompression.compress(folder: folder)

        // Assert
        guard case .compressed = outcome else {
            Issue.record("expected compression, got \(outcome)")
            return
        }
        #expect(try CaptureFixtures.frames(of: folder.appending(path: "mic.m4a")) == frames)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "mic.caf").path))
        let listed = try #require(RecordingLibrary.load(from: root).first)
        guard case .single(let audio) = listed.audio else {
            Issue.record("still one stream")
            return
        }
        #expect(audio.lastPathComponent == "mic.m4a")
        let again = try RecordingCompression.compress(folder: folder)
        #expect(again == .alreadyCompressed)
    }

    @Test("an in-person meeting cut off by a crash comes back as an in-person meeting")
    func recoveredAsInPerson() throws {
        // Arrange
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "20260928-100000-\(SourceApp.inPerson.bundleID)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try CaptureFixtures.writeTone(folder.appending(path: "mic.caf"), seconds: 1, sampleRate: 24_000, channels: 1)
        let partial = PartialSession(id: UUID(), startedAt: startedAt, app: .inPerson, method: .screenCaptureKit)
            .noting(.mic, startedAt: 10)
        try partial.write(in: folder)

        // Act
        let restored = RecordingRecovery.recoverInterrupted(in: root)

        // Assert
        #expect(restored == [partial.id])
        let listed = try #require(RecordingLibrary.load(from: root).first)
        #expect(listed.title == "Живая встреча")
        #expect(listed.appBundleID == SourceApp.inPerson.bundleID)
    }
}
