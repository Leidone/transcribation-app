import Foundation
import Localization

/// The names a person gave to the voices of one recording ("Собеседник 1" → "Анна"). The transcript itself keeps
/// the original labels, so a name can be changed or taken back at any time.
public struct SpeakerNames: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let empty = SpeakerNames(names: [:])

    public let version: Int
    public let names: [String: String]

    public init(names: [String: String], version: Int = currentVersion) {
        self.version = version
        self.names = names
    }

    /// The chosen name, or the label itself when none was given (in the interface language).
    public func displayName(for label: String) -> String {
        names[label] ?? Self.defaultName(for: label)
    }

    /// How a voice nobody named is shown. The transcript stores Russian labels ("Я", "Собеседник 2", "Спикер 1");
    /// an English interface shows them as "Me", "Speaker 2", "Speaker 1".
    public static func defaultName(for label: String, in language: Language = .current) -> String {
        guard language == .english else { return label }
        if label == "Я" { return "Me" }
        for prefix in ["Собеседник ", "Спикер "] where label.hasPrefix(prefix) {
            return "Speaker " + label.dropFirst(prefix.count)
        }
        return label
    }

    /// A copy with `label` renamed. Surrounding spaces are ignored; an empty name, or the label itself, takes the
    /// rename back.
    public func renaming(_ label: String, to newName: String) -> SpeakerNames {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = names
        if trimmed.isEmpty || trimmed == label || trimmed == Self.defaultName(for: label) {
            updated[label] = nil
        } else {
            updated[label] = trimmed
        }
        return SpeakerNames(names: updated, version: version)
    }
}

/// Reads and writes `speakers.json` next to a recording's audio.
public enum SpeakerNamesStore {
    public static let fileName = "speakers.json"

    public static func save(_ names: SpeakerNames, in directory: URL) throws {
        let file = directory.appending(path: fileName)
        guard !names.names.isEmpty else {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(names).write(to: file, options: .atomic)
    }

    /// No file means no names were given; a file that exists but cannot be read throws.
    public static func load(from directory: URL) throws -> SpeakerNames {
        let file = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return .empty }
        return try JSONDecoder().decode(SpeakerNames.self, from: Data(contentsOf: file))
    }
}
