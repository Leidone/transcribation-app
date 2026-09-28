import Foundation
import Localization

extension SourceApp {
    /// Not an app: a meeting in a room, recorded from the microphone alone.
    public static let inPersonBundleID = "app.callrecorder.in-person"

    /// What the source picker offers next to the running apps.
    public static var inPerson: SourceApp {
        SourceApp(bundleID: inPersonBundleID, name: tr("Живая встреча (микрофон)", "In-person meeting (microphone)"))
    }

    public var isInPerson: Bool { bundleID == Self.inPersonBundleID }
}

/// A meeting in a room: one stream, the microphone, where every voice is someone to tell apart. It is kept like an
/// import (`import.json` next to the audio) and marked as the app's own, so it is named and compressed as such.
public enum InPersonRecording {
    static let source = "inPerson"

    public static func save(id: UUID, startedAt: Date, audioFile: String, in folder: URL) throws {
        let metadata = ImportMetadata(
            id: id, originalName: audioFile, recordedAt: startedAt, audioFile: audioFile, source: source
        )
        try write(metadata, in: folder)
    }

    /// The metadata of an in-person meeting; `nil` for anything else, imports included.
    static func metadata(in folder: URL) -> ImportMetadata? {
        let file = folder.appending(path: RecordingLibrary.importFileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode(ImportMetadata.self, from: data), metadata.source == source else {
            return nil
        }
        return metadata
    }

    static func write(_ metadata: ImportMetadata, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(metadata).write(to: folder.appending(path: RecordingLibrary.importFileName), options: .atomic)
    }
}
