import AVFoundation
import Foundation
import Localization
import os

/// Kept next to a capture while it is being recorded (`session.partial.json`). `session.json` is written only when
/// the recording stops, so without this a crash or a power cut would leave the audio (which survives: CAF stays
/// readable up to the last written buffer) without the app's name or the alignment of the two streams.
public struct PartialSession: Codable, Equatable, Sendable {
    public enum Stream: Sendable {
        case app
        case mic
    }

    public static let fileName = "session.partial.json"

    public let id: UUID
    public let startedAt: Date
    public let app: SourceApp
    public let method: CaptureMethod
    /// When each stream's first sample arrived, as in `StreamInfo.firstPTS`; noted as soon as it is known.
    public let appFirstPTS: Double?
    public let micFirstPTS: Double?

    public init(id: UUID, startedAt: Date, app: SourceApp, method: CaptureMethod) {
        self.init(id: id, startedAt: startedAt, app: app, method: method, appFirstPTS: nil, micFirstPTS: nil)
    }

    private init(
        id: UUID, startedAt: Date, app: SourceApp, method: CaptureMethod, appFirstPTS: Double?, micFirstPTS: Double?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.app = app
        self.method = method
        self.appFirstPTS = appFirstPTS
        self.micFirstPTS = micFirstPTS
    }

    public func noting(_ stream: Stream, startedAt pts: Double) -> PartialSession {
        PartialSession(
            id: id, startedAt: startedAt, app: app, method: method,
            appFirstPTS: stream == .app ? pts : appFirstPTS,
            micFirstPTS: stream == .mic ? pts : micFirstPTS
        )
    }

    public func write(in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(self).write(to: folder.appending(path: Self.fileName), options: .atomic)
    }

    static func read(in folder: URL) throws -> PartialSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PartialSession.self, from: Data(contentsOf: folder.appending(path: fileName)))
    }

    static func isPresent(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: fileName).path)
    }
}

/// Finishes the captures a crash or a power cut left behind, so they show up in the library like any other.
public enum RecordingRecovery {
    /// Call it once at launch, before anything is recorded: every folder still marked as being recorded is then
    /// known to be abandoned. Returns the ids of the recordings brought back.
    @discardableResult
    public static func recoverInterrupted(in root: URL) -> [UUID] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.filter(PartialSession.isPresent).compactMap(recover)
    }

    private static func recover(folder: URL) -> UUID? {
        let marker = folder.appending(path: PartialSession.fileName)
        defer {
            do {
                try FileManager.default.removeItem(at: marker)
            } catch {
                Logger.capture.error("cannot remove a recording marker: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Stopped normally, but the app went away before it could remove the marker.
        guard !FileManager.default.fileExists(atPath: folder.appending(path: RecordingLibrary.sessionFileName).path) else {
            return nil
        }
        do {
            let partial = try PartialSession.read(in: folder)
            let result = try restore(partial, in: folder)
            if result != nil { Logger.capture.notice("recovered an interrupted recording") }
            return result
        } catch {
            Logger.capture.error("cannot recover a recording: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func restore(_ partial: PartialSession, in folder: URL) throws -> UUID? {
        // Without both start times the streams cannot be aligned exactly; starting them together is closest.
        let bothKnown = partial.appFirstPTS != nil && partial.micFirstPTS != nil
        let app = stream("app.caf", in: folder, firstPTS: bothKnown ? partial.appFirstPTS : 0)
        let mic = stream("mic.caf", in: folder, firstPTS: bothKnown ? partial.micFirstPTS : 0)

        switch (app, mic) {
        case let (app?, mic?):
            let session = RecordingSession(
                id: partial.id, startedAt: partial.startedAt, app: partial.app, method: partial.method,
                streams: Streams(app: app, mic: mic)
            )
            try session.encoded().write(to: folder.appending(path: RecordingLibrary.sessionFileName), options: .atomic)
            return partial.id
        case let (only?, nil), let (nil, only?):
            try writeSingleStream(only.file, of: partial, in: folder)
            return partial.id
        case (nil, nil):
            Logger.capture.error("an interrupted recording has no readable audio")
            return nil
        }
    }

    /// One stream survived: listed like an import, under the call app's name.
    private static func writeSingleStream(_ file: String, of partial: PartialSession, in folder: URL) throws {
        if partial.app.isInPerson {
            try InPersonRecording.save(id: partial.id, startedAt: partial.startedAt, audioFile: file, in: folder)
            return
        }
        let name = partial.app.name.replacingOccurrences(of: "/", with: "-")
        let metadata = ImportMetadata(
            id: partial.id, originalName: tr("\(name) — прерванная запись.caf", "\(name) — interrupted recording.caf"), recordedAt: partial.startedAt, audioFile: file
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(metadata).write(to: folder.appending(path: RecordingLibrary.importFileName), options: .atomic)
    }

    private static func stream(_ file: String, in folder: URL, firstPTS: Double?) -> StreamInfo? {
        guard let audio = try? AVAudioFile(forReading: folder.appending(path: file)), audio.length > 0 else { return nil }
        return StreamInfo(
            file: file, sampleRate: audio.processingFormat.sampleRate,
            channels: Int(audio.processingFormat.channelCount), firstPTS: firstPTS ?? 0, droppedBuffers: 0
        )
    }
}
