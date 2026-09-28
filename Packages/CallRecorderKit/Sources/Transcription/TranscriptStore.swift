import Foundation

/// A finished transcript of one recording. Times are seconds on the app stream's clock.
public struct StoredTranscript: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let engine: String
    /// Stored with whole-second precision (ISO 8601).
    public let createdAt: Date
    public let utterances: [Utterance]
    /// When the person last corrected a line by hand; absent while the text is exactly as recognised.
    public let editedAt: Date?
    /// Wall-clock time the recognition took on this device; absent in files written before it was measured.
    public let processingSeconds: Double?

    public init(
        engine: String, createdAt: Date, utterances: [Utterance], version: Int = currentVersion,
        editedAt: Date? = nil, processingSeconds: Double? = nil
    ) {
        self.version = version
        self.engine = engine
        self.createdAt = createdAt
        self.utterances = utterances
        self.editedAt = editedAt
        self.processingSeconds = processingSeconds
    }

    /// A copy with the text of utterance `index` replaced and the edit time set; an index out of range changes
    /// nothing. Timing, speaker and the measured processing time stay as they were.
    public func replacingText(at index: Int, with text: String, editedAt date: Date) -> StoredTranscript {
        guard utterances.indices.contains(index) else { return self }
        let updated = utterances.enumerated().map { position, utterance in
            position == index
                ? Utterance(start: utterance.start, end: utterance.end, speaker: utterance.speaker, text: text)
                : utterance
        }
        return StoredTranscript(
            engine: engine, createdAt: createdAt, utterances: updated, version: version,
            editedAt: date, processingSeconds: processingSeconds
        )
    }

    /// A copy that records how long the recognition took.
    public func measured(processingSeconds seconds: Double) -> StoredTranscript {
        StoredTranscript(
            engine: engine, createdAt: createdAt, utterances: utterances, version: version,
            editedAt: editedAt, processingSeconds: seconds
        )
    }
}

/// Reads and writes `transcript.json` next to a recording's audio.
public enum TranscriptStore {
    public static let fileName = "transcript.json"

    public static func save(_ transcript: StoredTranscript, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(transcript).write(to: directory.appending(path: fileName), options: .atomic)
    }

    /// `nil` when the recording has not been transcribed yet; a file that exists but cannot be read throws.
    public static func load(from directory: URL) throws -> StoredTranscript? {
        let file = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredTranscript.self, from: Data(contentsOf: file))
    }
}
