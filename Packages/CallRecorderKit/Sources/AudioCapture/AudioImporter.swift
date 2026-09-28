import AVFoundation
import Foundation
import Localization

public enum ImportError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            tr(
                "Формат «.\(ext)» не поддерживается. Подойдут WAV, MP3, M4A, AAC, FLAC, AIFF и CAF.",
                "The “.\(ext)” format is not supported. WAV, MP3, M4A, AAC, FLAC, AIFF and CAF work."
            )
        case .unreadable(let name):
            tr(
                "Не удалось прочитать аудио из файла «\(name)». Возможно, файл повреждён.",
                "Could not read audio from “\(name)”. The file may be damaged."
            )
        }
    }
}

/// Brings an existing audio file into the library: it is copied into a folder of its own, next to the app's
/// captures, so the original stays where it was.
public enum AudioImporter {
    /// Returns the new recording folder (`<time>-import-<name>/audio.<ext>` plus `import.json`).
    @discardableResult
    public static func importFile(at source: URL, into root: URL, now: Date = Date()) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard RecordingLibrary.audioExtensions.contains(ext) else { throw ImportError.unsupportedFormat(ext) }
        do {
            _ = try AVAudioFile(forReading: source)
        } catch {
            throw ImportError.unreadable(source.lastPathComponent)
        }

        let base = "\(RecordingTimestamp.folderName(now))-import-\(sanitized(source.deletingPathExtension().lastPathComponent))"
        let folder = uniqueFolder(in: root, base: base)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let audioName = "audio.\(ext)"
            try FileManager.default.copyItem(at: source, to: folder.appending(path: audioName))
            let metadata = ImportMetadata(
                id: UUID(), originalName: source.lastPathComponent, recordedAt: recordedAt(of: source, fallback: now),
                audioFile: audioName
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(metadata).write(to: folder.appending(path: RecordingLibrary.importFileName))
        } catch {
            try? FileManager.default.removeItem(at: folder) // do not leave a half-imported folder behind
            throw error
        }
        return folder
    }

    private static func uniqueFolder(in root: URL, base: String) -> URL {
        var candidate = root.appending(path: base, directoryHint: .isDirectory)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appending(path: "\(base)-\(counter)", directoryHint: .isDirectory)
            counter += 1
        }
        return candidate
    }

    /// Letters and digits of any script stay, everything else becomes a single dash; at most 40 characters.
    static func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        var result = ""
        for scalar in name.unicodeScalars {
            let character: Character = allowed.contains(scalar) ? Character(scalar) : "-"
            if character == "-", result.last == "-" { continue }
            result.append(character)
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40)
        return trimmed.isEmpty ? "audio" : String(trimmed)
    }

    /// The source file's creation date; a missing date only affects ordering, so a failed lookup uses `fallback`.
    private static func recordedAt(of source: URL, fallback: Date) -> Date {
        (try? source.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? fallback
    }
}
