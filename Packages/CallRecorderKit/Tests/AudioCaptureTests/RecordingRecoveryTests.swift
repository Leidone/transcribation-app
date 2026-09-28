import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

struct RecordingRecoveryTests {
    private let app = SourceApp(bundleID: "ru.yandex.desktop.telemost", name: "Телемост")

    /// What a crash leaves: the audio written so far and the marker the recorder keeps while it records.
    @discardableResult
    private func writeInterrupted(
        in root: URL, appFirstPTS: Double?, micFirstPTS: Double?, streams: Set<String> = ["app.caf", "mic.caf"]
    ) throws -> (URL, PartialSession) {
        let folder = root.appending(path: "20260928-101500-\(app.bundleID)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if streams.contains("app.caf") {
            try CaptureFixtures.writeTone(folder.appending(path: "app.caf"), seconds: 2, sampleRate: 48_000, channels: 2)
        }
        if streams.contains("mic.caf") {
            try CaptureFixtures.writeTone(folder.appending(path: "mic.caf"), seconds: 1.5, sampleRate: 24_000, channels: 1)
        }
        var partial = PartialSession(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 1_800_000_000), app: app, method: .screenCaptureKit
        )
        if let appFirstPTS { partial = partial.noting(.app, startedAt: appFirstPTS) }
        if let micFirstPTS { partial = partial.noting(.mic, startedAt: micFirstPTS) }
        try partial.write(in: folder)
        return (folder, partial)
    }

    @Test("a capture cut off by a crash gets its session back, aligned by the start times it noted")
    func restoresInterruptedCapture() throws {
        // Arrange
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, partial) = try writeInterrupted(in: root, appFirstPTS: 50, micFirstPTS: 50.4)

        // Act
        let restored = RecordingRecovery.recoverInterrupted(in: root)

        // Assert
        #expect(restored == [partial.id])
        let session = try RecordingSession.decode(from: Data(contentsOf: folder.appending(path: "session.json")))
        #expect(session.id == partial.id)
        #expect(session.app == app)
        #expect(abs(session.syncOffsetSeconds - 0.4) < 0.000_1)
        #expect(session.streams.app.sampleRate == 48_000 && session.streams.app.channels == 2)
        #expect(session.streams.mic.sampleRate == 24_000 && session.streams.mic.channels == 1)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: PartialSession.fileName).path))

        let listed = try #require(RecordingLibrary.load(from: root).first)
        #expect(listed.id == partial.id)
        #expect(abs(listed.duration - 2) < 0.01)
    }

    @Test("without noted start times the two streams are aligned at their beginnings")
    func alignsAtZeroWithoutStartTimes() throws {
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, _) = try writeInterrupted(in: root, appFirstPTS: 50, micFirstPTS: nil)

        RecordingRecovery.recoverInterrupted(in: root)

        let session = try RecordingSession.decode(from: Data(contentsOf: folder.appending(path: "session.json")))
        #expect(session.syncOffsetSeconds == 0)
    }

    @Test("with only one stream left, the recording is listed on its own, named after the app")
    func oneSurvivingStream() throws {
        // Arrange
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, partial) = try writeInterrupted(in: root, appFirstPTS: 50, micFirstPTS: nil, streams: ["app.caf"])

        // Act
        let restored = RecordingRecovery.recoverInterrupted(in: root)

        // Assert
        #expect(restored == [partial.id])
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "session.json").path))
        let listed = try #require(RecordingLibrary.load(from: root).first)
        #expect(listed.id == partial.id)
        #expect(listed.title == "Телемост — прерванная запись")
        #expect(listed.startedAt == partial.startedAt)
        guard case .single(let audio) = listed.audio else {
            Issue.record("one stream must be listed as single audio")
            return
        }
        #expect(audio.lastPathComponent == "app.caf")
    }

    @Test("a folder that is still being recorded is not listed")
    func recordingInProgressIsHidden() throws {
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeInterrupted(in: root, appFirstPTS: 50, micFirstPTS: 50)

        #expect(RecordingLibrary.load(from: root).isEmpty)
    }

    @Test("a marker left next to a finished session is just removed")
    func staleMarkerIsRemoved() throws {
        // Arrange
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, session) = try CaptureFixtures.writeCapture(in: root)
        try PartialSession(id: session.id, startedAt: session.startedAt, app: session.app, method: .screenCaptureKit)
            .write(in: folder)
        let sessionData = try Data(contentsOf: folder.appending(path: "session.json"))

        // Act
        let restored = RecordingRecovery.recoverInterrupted(in: root)

        // Assert
        #expect(restored.isEmpty)
        #expect(try Data(contentsOf: folder.appending(path: "session.json")) == sessionData)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: PartialSession.fileName).path))
        #expect(RecordingLibrary.load(from: root).map(\.id) == [session.id])
    }

    @Test("finished captures and imports are not touched")
    func otherFoldersUntouched() throws {
        let root = try CaptureFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (folder, _) = try CaptureFixtures.writeCapture(in: root)
        let before = try Data(contentsOf: folder.appending(path: "session.json"))

        let restored = RecordingRecovery.recoverInterrupted(in: root)

        #expect(restored.isEmpty)
        #expect(try Data(contentsOf: folder.appending(path: "session.json")) == before)
    }
}
