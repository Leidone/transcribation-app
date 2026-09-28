import Foundation

/// One task of a stored analysis. It has a permanent id so the "done" mark survives a reload.
public struct StoredTask: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let owner: String?
    public let due: String?
    public let quote: String?
    public let timestampSeconds: Double?
    public let isDone: Bool

    public init(
        id: UUID, title: String, owner: String?, due: String?, quote: String?, timestampSeconds: Double?, isDone: Bool
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.due = due
        self.quote = quote
        self.timestampSeconds = timestampSeconds
        self.isDone = isDone
    }

    func togglingDone() -> StoredTask {
        StoredTask(
            id: id, title: title, owner: owner, due: due, quote: quote, timestampSeconds: timestampSeconds,
            isDone: !isDone
        )
    }
}

/// The summary, decisions and tasks of one recording, as kept on disk.
public struct StoredAnalysis: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    /// Stored with whole-second precision (ISO 8601).
    public let createdAt: Date
    public let summary: String
    public let decisions: [String]
    public let tasks: [StoredTask]
    /// `AnalysisTemplate.rawValue` the summary was written with; absent in files from before templates existed,
    /// which were all written with the general one. Kept as a string so an unknown future value still loads.
    public let template: String?

    public init(
        version: Int = currentVersion, createdAt: Date, summary: String, decisions: [String], tasks: [StoredTask],
        template: String? = nil
    ) {
        self.version = version
        self.createdAt = createdAt
        self.summary = summary
        self.decisions = decisions
        self.tasks = tasks
        self.template = template
    }

    /// Turns a fresh answer into a stored one; every task gets its own id and starts as not done.
    public init(
        analysis: CallAnalysis, createdAt: Date, template: AnalysisTemplate? = nil, makeID: () -> UUID = UUID.init
    ) {
        self.init(
            createdAt: createdAt,
            summary: analysis.summary,
            decisions: analysis.decisions,
            tasks: analysis.tasks.map {
                StoredTask(
                    id: makeID(), title: $0.title, owner: $0.owner, due: $0.due, quote: $0.quote,
                    timestampSeconds: $0.timestampSeconds, isDone: false
                )
            },
            template: template?.rawValue
        )
    }

    /// A copy with one task's done mark flipped; an unknown id changes nothing.
    public func togglingTask(_ taskID: UUID) -> StoredAnalysis {
        StoredAnalysis(
            version: version, createdAt: createdAt, summary: summary, decisions: decisions,
            tasks: tasks.map { $0.id == taskID ? $0.togglingDone() : $0 }, template: template
        )
    }
}

/// Reads and writes `analysis.json` next to a recording's audio.
public enum AnalysisStore {
    public static let fileName = "analysis.json"

    public static func save(_ analysis: StoredAnalysis, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(analysis).write(to: directory.appending(path: fileName), options: .atomic)
    }

    /// `nil` when the recording has not been analysed yet; a file that exists but cannot be read throws.
    public static func load(from directory: URL) throws -> StoredAnalysis? {
        let file = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredAnalysis.self, from: Data(contentsOf: file))
    }
}
