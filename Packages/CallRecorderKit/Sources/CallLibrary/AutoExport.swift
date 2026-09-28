import Foundation

/// Keeps a Markdown note of every summarised meeting in a folder the person chose — an Obsidian vault, iCloud
/// Drive, anything that reads files. A meeting always writes the same note, so summarising it again updates it.
public enum AutoExport {
    /// "2026-09-28 10-30 Weekly.md": sorted by time in any file list, and two meetings of the same title differ.
    public static func fileName(of recording: RecordingItem) -> String {
        datePrefix(recording.startedAt) + " " + RecordingExport.fileName(of: recording, extension: "md")
    }

    /// The meeting's start as written in the file name, in the Mac's time zone.
    public static func datePrefix(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: date)
    }

    /// Writes the note and returns where it went.
    @discardableResult
    public static func write(_ recording: RecordingItem, to folder: URL, includesTranscript: Bool) throws -> URL {
        let file = folder.appending(path: fileName(of: recording))
        let text = RecordingExport.markdown(of: recording, options: .init(includesTranscript: includesTranscript))
        try Data(text.utf8).write(to: file, options: .atomic)
        return file
    }
}
