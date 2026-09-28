import Foundation

public enum CaptureMethod: String, Codable, Sendable {
    case screenCaptureKit
    case coreAudioTap
    /// iOS: a ReplayKit broadcast, captured by `CallRecorderMobileBroadcast`. Unlike `screenCaptureKit`, this is
    /// the whole screen's system audio, not one chosen app — iOS has no per-app audio tap.
    case replayKit
}

public struct SourceApp: Codable, Equatable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct StreamInfo: Codable, Equatable, Sendable {
    public let file: String
    public let sampleRate: Double
    public let channels: Int
    /// Presentation timestamp (seconds) of the first sample; used to align the two streams.
    public let firstPTS: Double
    public let droppedBuffers: Int

    public init(file: String, sampleRate: Double, channels: Int, firstPTS: Double, droppedBuffers: Int) {
        self.file = file
        self.sampleRate = sampleRate
        self.channels = channels
        self.firstPTS = firstPTS
        self.droppedBuffers = droppedBuffers
    }

    func replacingDroppedBuffers(_ count: Int) -> StreamInfo {
        StreamInfo(file: file, sampleRate: sampleRate, channels: channels, firstPTS: firstPTS, droppedBuffers: count)
    }

    func replacingFile(_ newFile: String) -> StreamInfo {
        StreamInfo(file: newFile, sampleRate: sampleRate, channels: channels, firstPTS: firstPTS, droppedBuffers: droppedBuffers)
    }
}

public struct Streams: Codable, Equatable, Sendable {
    public let app: StreamInfo
    public let mic: StreamInfo

    public init(app: StreamInfo, mic: StreamInfo) {
        self.app = app
        self.mic = mic
    }
}

/// Metadata written next to the two audio files of one recording (`session.json`).
public struct RecordingSession: Codable, Equatable, Sendable {
    public let id: UUID
    /// Stored with whole-second precision (ISO 8601).
    public let startedAt: Date
    public let app: SourceApp
    public let method: CaptureMethod
    public let streams: Streams

    public init(id: UUID, startedAt: Date, app: SourceApp, method: CaptureMethod, streams: Streams) {
        self.id = id
        self.startedAt = startedAt
        self.app = app
        self.method = method
        self.streams = streams
    }

    /// Seconds by which the microphone stream starts after the app stream (negative if it starts earlier).
    public var syncOffsetSeconds: Double {
        streams.mic.firstPTS - streams.app.firstPTS
    }

    public func recordingDroppedBuffers(app appDropped: Int, mic micDropped: Int) -> RecordingSession {
        RecordingSession(
            id: id,
            startedAt: startedAt,
            app: app,
            method: method,
            streams: Streams(
                app: streams.app.replacingDroppedBuffers(appDropped),
                mic: streams.mic.replacingDroppedBuffers(micDropped)
            )
        )
    }

    /// The same recording with its audio in other files (after compression); timing and ids stay.
    func replacingStreamFiles(app appFile: String, mic micFile: String) -> RecordingSession {
        RecordingSession(
            id: id, startedAt: startedAt, app: app, method: method,
            streams: Streams(app: streams.app.replacingFile(appFile), mic: streams.mic.replacingFile(micFile))
        )
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> RecordingSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingSession.self, from: data)
    }
}
