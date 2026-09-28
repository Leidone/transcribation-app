import Foundation

/// Moments the person marked as important during a call (`marks.json`). Times are seconds on the app stream's
/// clock — the clock of the transcript — so a mark lands on the words said at that moment.
public struct ImportantMarks: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let empty = ImportantMarks(times: [])
    /// Presses this close together are one mark (a double press, or a key held down).
    public static let mergeWindow: TimeInterval = 3

    public let version: Int
    /// Sorted, never closer together than `mergeWindow`.
    public let times: [TimeInterval]

    public init(times: [TimeInterval], version: Int = currentVersion) {
        self.version = version
        self.times = times
    }

    /// A copy with `time` added; a press right next to an existing mark changes nothing.
    public func adding(_ time: TimeInterval) -> ImportantMarks {
        let moment = max(0, time)
        guard !times.contains(where: { abs($0 - moment) < Self.mergeWindow }) else { return self }
        return ImportantMarks(times: (times + [moment]).sorted(), version: version)
    }

    /// A copy without the marks within `mergeWindow` of `time`.
    public func removing(near time: TimeInterval) -> ImportantMarks {
        ImportantMarks(times: times.filter { abs($0 - time) >= Self.mergeWindow }, version: version)
    }
}

/// Reads and writes `marks.json` next to a recording's audio. It is written during the recording, at each press.
public enum ImportantMarksStore {
    public static let fileName = "marks.json"

    public static func save(_ marks: ImportantMarks, in directory: URL) throws {
        let file = directory.appending(path: fileName)
        guard !marks.times.isEmpty else {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(marks).write(to: file, options: .atomic)
    }

    /// No file means nothing was marked; a file that exists but cannot be read throws.
    public static func load(from directory: URL) throws -> ImportantMarks {
        let file = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return .empty }
        return try JSONDecoder().decode(ImportantMarks.self, from: Data(contentsOf: file))
    }
}
