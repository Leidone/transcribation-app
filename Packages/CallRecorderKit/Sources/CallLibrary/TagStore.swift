import Foundation

/// The person's own labels for a recording — a project, a client — kept in `tags.json` next to it. Search finds
/// them, and a click on one shows every recording with it.
public enum TagStore {
    public static let fileName = "tags.json"

    public static func save(_ tags: [String], in directory: URL) throws {
        let file = directory.appending(path: fileName)
        guard !tags.isEmpty else {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        try JSONEncoder().encode(tags).write(to: file, options: .atomic)
    }

    /// No file means no tags.
    public static func load(from directory: URL) throws -> [String] {
        let file = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: file))
    }

    /// The tags with `tag` added at the end: trimmed, and not again if it is there in another case.
    public static func adding(_ tag: String, to tags: [String]) -> [String] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(where: { $0.lowercased() == trimmed.lowercased() }) else { return tags }
        return tags + [trimmed]
    }

    /// Every tag in use, once each, the most used first (then alphabetically), for suggestions.
    public static func allTags(in recordings: [RecordingItem]) -> [String] {
        let counts = recordings.flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.keys.sorted { lhs, rhs in
            counts[lhs] != counts[rhs] ? (counts[lhs] ?? 0) > (counts[rhs] ?? 0) : lhs < rhs
        }
    }
}
