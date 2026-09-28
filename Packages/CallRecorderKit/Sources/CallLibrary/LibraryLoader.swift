import AudioCapture
import CodexClient
import Foundation
import Transcription
import os

private let libraryLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.callrecorder", category: "library")

/// Reads every recording in the library folder together with its transcript, summary and speaker names.
public enum LibraryLoader {
    /// Reads files and audio headers, so call it off the main actor. A recording whose side file cannot be read
    /// is still listed, without that part; the problem is logged.
    public static func load(from directory: URL) -> [RecordingItem] {
        RecordingLibrary.load(from: directory).map(item)
    }

    static func item(for stored: StoredRecording) -> RecordingItem {
        RecordingItem(
            stored: stored,
            transcript: read("transcript") { try TranscriptStore.load(from: stored.directory) } ?? nil,
            analysis: read("analysis") { try AnalysisStore.load(from: stored.directory) } ?? nil,
            speakerNames: read("speaker names") { try SpeakerNamesStore.load(from: stored.directory) } ?? .empty,
            meeting: read("meeting") { try MeetingInfoStore.load(from: stored.directory) } ?? nil,
            marks: read("marks") { try ImportantMarksStore.load(from: stored.directory) } ?? .empty,
            tags: read("tags") { try TagStore.load(from: stored.directory) } ?? []
        )
    }

    private static func read<Value>(_ what: String, _ load: () throws -> Value) -> Value? {
        do {
            return try load()
        } catch {
            libraryLog.error("unreadable \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
