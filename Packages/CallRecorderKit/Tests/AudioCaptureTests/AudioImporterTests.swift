import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

struct AudioImporterTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "importer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeAudio(_ url: URL, seconds: Double) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @Test("an imported file becomes a recording in a folder of its own and the original stays")
    func importsAndLoads() throws {
        // Arrange
        let root = try makeDirectory()
        let source = try makeDirectory().appending(path: "Планёрка 21.09.wav")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAudio(source, seconds: 2)

        // Act
        let folder = try AudioImporter.importFile(at: source, into: root)
        let loaded = RecordingLibrary.load(from: root)

        // Assert
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(folder.lastPathComponent.contains("-import-Планёрка-21-09"))
        let recording = try #require(loaded.first)
        #expect(loaded.count == 1)
        #expect(recording.title == "Планёрка 21.09")
        #expect(recording.appName == nil)
        #expect(abs(recording.duration - 2) < 0.05)
        guard case .single(let audio) = recording.audio else {
            Issue.record("an import must be a single-file recording")
            return
        }
        #expect(audio.lastPathComponent == "audio.wav")
    }

    @Test("importing the same file twice gives two separate recordings")
    func twiceGivesTwoFolders() throws {
        let root = try makeDirectory()
        let source = try makeDirectory().appending(path: "call.wav")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAudio(source, seconds: 1)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try AudioImporter.importFile(at: source, into: root, now: now)
        let second = try AudioImporter.importFile(at: source, into: root, now: now)

        #expect(first != second)
        #expect(Set(RecordingLibrary.load(from: root).map(\.id)).count == 2)
    }

    @Test("a format outside the supported list is rejected before anything is copied")
    func unsupportedFormat() throws {
        let root = try makeDirectory()
        let source = try makeDirectory().appending(path: "voice.ogg")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("x".utf8).write(to: source)

        #expect(throws: ImportError.unsupportedFormat("ogg")) { try AudioImporter.importFile(at: source, into: root) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("a file with an audio extension but no audio is rejected and leaves no folder behind")
    func unreadableAudio() throws {
        let root = try makeDirectory()
        let source = try makeDirectory().appending(path: "broken.mp3")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not audio".utf8).write(to: source)

        #expect(throws: ImportError.unreadable("broken.mp3")) { try AudioImporter.importFile(at: source, into: root) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("file names are made safe for folders in any script")
    func sanitizing() {
        #expect(AudioImporter.sanitized("Встреча: итоги / Q3!") == "Встреча-итоги-Q3")
        #expect(AudioImporter.sanitized("///") == "audio")
        #expect(AudioImporter.sanitized(String(repeating: "a", count: 100)).count == 40)
    }
}
