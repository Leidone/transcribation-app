import Foundation

/// What each voice of one recording sounds like, as the diarizer's speaker embedding, keyed by the transcript label
/// ("Собеседник 1"). It lets a name given to a voice once be recognised in later recordings. The embeddings are
/// numbers derived from the audio, never the audio itself, and stay on this device.
public struct Voiceprints: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let empty = Voiceprints(voices: [:])

    public let version: Int
    public let voices: [String: [Float]]

    public init(voices: [String: [Float]], version: Int = currentVersion) {
        self.version = version
        self.voices = voices
    }
}

/// Reads and writes `voices.json` next to a recording's audio.
public enum VoiceprintStore {
    public static let fileName = "voices.json"

    public static func save(_ prints: Voiceprints, in directory: URL) throws {
        let file = directory.appending(path: fileName)
        guard !prints.voices.isEmpty else {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        try JSONEncoder().encode(prints).write(to: file, options: .atomic)
    }

    /// No file (recordings transcribed before voiceprints existed) reads as no voices.
    public static func load(from directory: URL) throws -> Voiceprints {
        let file = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return .empty }
        return try JSONDecoder().decode(Voiceprints.self, from: Data(contentsOf: file))
    }
}

/// A finished transcription: the transcript and the voiceprints of the voices told apart in it.
public struct TranscriptionResult: Sendable {
    public let transcript: StoredTranscript
    public let voiceprints: Voiceprints

    public init(transcript: StoredTranscript, voiceprints: Voiceprints) {
        self.transcript = transcript
        self.voiceprints = voiceprints
    }
}
