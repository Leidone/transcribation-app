import AVFoundation
import CryptoKit
import Foundation
import Localization
import os

public enum RecordingAudio: Equatable, Sendable {
    /// The app's own capture: the other participants and the microphone as two streams.
    case separated(app: URL, mic: URL, micOffsetSeconds: Double)
    /// One file with everyone mixed, as imported or dropped into a folder.
    case single(URL)

    /// The recording's folder: the same before and after its audio is compressed.
    public var folder: URL {
        switch self {
        case .separated(let app, _, _): app.deletingLastPathComponent().standardizedFileURL
        case .single(let url): url.deletingLastPathComponent().standardizedFileURL
        }
    }
}

/// A recording found on disk, with its length measured from the audio file(s).
public struct StoredRecording: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// `nil` for the app's own captures; the original file name for imports and dropped-in folders.
    public let title: String?
    public let appName: String?
    public let appBundleID: String?
    public let startedAt: Date
    public let directory: URL
    public let duration: TimeInterval
    public let audio: RecordingAudio
}

/// Written next to an imported file (`import.json`).
struct ImportMetadata: Codable, Equatable {
    let id: UUID
    let originalName: String
    /// When the audio was recorded (the source file's creation date), as ISO 8601.
    let recordedAt: Date
    let audioFile: String
    /// `"inPerson"` for the app's own in-person meetings; absent for imports.
    var source: String?

    /// The same recording with its audio in another file (after compression).
    func replacingAudioFile(_ file: String) -> ImportMetadata {
        ImportMetadata(id: id, originalName: originalName, recordedAt: recordedAt, audioFile: file, source: source)
    }
}

/// Reads recordings back from disk, so the library survives app restarts and picks up what appears in the folder.
public enum RecordingLibrary {
    /// Audio formats the library lists; all of them are readable by AVFoundation, which the transcription uses.
    public static let audioExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "aifc", "caf", "m4a", "mp3", "flac", "aac", "mp4", "m4b",
    ]
    static let sessionFileName = "session.json"
    static let importFileName = "import.json"

    /// Every recording folder directly below `root`, newest first: the app's captures (`session.json`) and any
    /// folder holding an audio file (imports, or files put there by hand). A missing root is an empty library;
    /// folders that cannot be read are skipped and logged.
    public static func load(from root: URL) -> [StoredRecording] {
        let folders: [URL]
        do {
            folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch {
            if FileManager.default.fileExists(atPath: root.path) {
                Logger.capture.error("cannot list recordings: \(error.localizedDescription, privacy: .public)")
            }
            return []
        }
        return folders
            .compactMap(read)
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: Folders

    private static func read(folder: URL) -> StoredRecording? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        if FileManager.default.fileExists(atPath: folder.appending(path: sessionFileName).path) {
            return readCaptured(folder: folder)
        }
        // Being recorded right now (or, until `RecordingRecovery` runs, cut off by a crash): not a recording yet.
        if PartialSession.isPresent(in: folder) { return nil }
        return readLoose(folder: folder)
    }

    private static func readCaptured(folder: URL) -> StoredRecording? {
        do {
            let session = try RecordingSession.decode(from: Data(contentsOf: folder.appending(path: sessionFileName)))
            let app = folder.appending(path: session.streams.app.file)
            let mic = folder.appending(path: session.streams.mic.file)
            guard let longest = [app, mic].compactMap(seconds(of:)).max() else {
                Logger.capture.error("skipped a recording without readable audio")
                return nil
            }
            return StoredRecording(
                id: session.id, title: nil, appName: session.app.name, appBundleID: session.app.bundleID,
                startedAt: session.startedAt, directory: folder, duration: longest,
                audio: .separated(app: app, mic: mic, micOffsetSeconds: session.syncOffsetSeconds)
            )
        } catch {
            Logger.capture.error("skipped an unreadable recording: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// A folder without `session.json`: an import made by the app (`import.json`) or audio put there by hand.
    private static func readLoose(folder: URL) -> StoredRecording? {
        let metadata = readImportMetadata(in: folder)
        let audioURL: URL
        if let metadata {
            audioURL = folder.appending(path: metadata.audioFile)
        } else if let first = audioFiles(in: folder).first {
            audioURL = first
        } else {
            return nil
        }
        guard let duration = seconds(of: audioURL) else {
            Logger.capture.error("skipped an audio file that cannot be read")
            return nil
        }

        let originalName = metadata?.originalName ?? audioURL.lastPathComponent
        if let metadata, metadata.source == InPersonRecording.source {
            return StoredRecording(
                id: metadata.id, title: tr("Живая встреча", "In-person meeting"),
                appName: tr("Микрофон", "Microphone"), appBundleID: SourceApp.inPersonBundleID,
                startedAt: metadata.recordedAt, directory: folder, duration: duration, audio: .single(audioURL)
            )
        }
        return StoredRecording(
            id: metadata?.id ?? stableID(for: folder.lastPathComponent),
            title: URL(fileURLWithPath: originalName).deletingPathExtension().lastPathComponent,
            appName: nil, appBundleID: nil,
            startedAt: metadata?.recordedAt ?? fileDate(of: audioURL),
            directory: folder, duration: duration, audio: .single(audioURL)
        )
    }

    private static func audioFiles(in folder: URL) -> [URL] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        } catch {
            Logger.capture.error("cannot list a recording folder: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return files
            .filter { !$0.lastPathComponent.hasPrefix(".") && audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func readImportMetadata(in folder: URL) -> ImportMetadata? {
        let file = folder.appending(path: importFileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ImportMetadata.self, from: Data(contentsOf: file))
        } catch {
            Logger.capture.error("unreadable import.json, treating the folder as plain audio")
            return nil
        }
    }

    // MARK: Helpers

    private static func seconds(of audioFile: URL) -> TimeInterval? {
        do {
            let file = try AVAudioFile(forReading: audioFile)
            return Double(file.length) / file.processingFormat.sampleRate
        } catch {
            Logger.capture.error("cannot read audio length: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The same folder always gets the same id, so a selection survives a reload.
    private static func stableID(for name: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        return UUID(uuid: bytes.withUnsafeBytes { $0.load(as: uuid_t.self) })
    }

    /// Creation date, else modification date, else now. A missing date only affects ordering, so a failed
    /// lookup falls back silently.
    private static func fileDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? Date()
    }
}
