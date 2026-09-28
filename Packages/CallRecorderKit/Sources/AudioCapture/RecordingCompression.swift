import AVFoundation
import Foundation
import Localization
import os

/// Turns a finished capture's two lossless streams into AAC once it has been transcribed. For speech the result
/// sounds the same, is about twenty times smaller, and keeps the exact length and timing, so the times printed
/// next to transcript lines still point at the right moment.
public enum RecordingCompression {
    public enum Outcome: Equatable, Sendable {
        /// Bytes freed on disk.
        case compressed(savedBytes: Int64)
        case alreadyCompressed
        /// Not one of the app's captures (an import, or audio put there by hand): left as it is.
        case notApplicable
    }

    public enum CompressionError: LocalizedError {
        case lengthChanged(file: String)
        case noBuffer

        public var errorDescription: String? {
            switch self {
            case .lengthChanged(let file):
                tr("Сжатый файл \(file) получился другой длины — оставили исходный.",
                   "The compressed \(file) came out a different length — the original is kept.")
            case .noBuffer: tr("Не удалось выделить память для сжатия звука.", "Could not get memory to compress the audio.")
            }
        }
    }

    /// 64 kbit/s for each channel: plenty for speech.
    static let bitRatePerChannel = 64_000
    /// What a compressed capture takes per second: the app's two channels and the microphone's one.
    public static let bytesPerSecond = Double(bitRatePerChannel * 3) / 8
    static let compressedExtension = "m4a"
    private static let losslessExtensions: Set<String> = ["caf", "wav", "wave", "aif", "aiff"]
    /// The encoder may round the length to its own frame size; anything longer than this is a broken file.
    private static let allowedLengthDifference: TimeInterval = 0.05

    /// Compresses the capture in `folder`. Safe to run again at any point: the lossless files are removed only
    /// after `session.json` names the new ones, and leftovers of an interrupted run are cleaned up.
    public static func compress(folder: URL) throws -> Outcome {
        let sessionURL = folder.appending(path: RecordingLibrary.sessionFileName)
        guard FileManager.default.fileExists(atPath: sessionURL.path) else { return try compressInPerson(folder: folder) }
        let session = try RecordingSession.decode(from: Data(contentsOf: sessionURL))
        let streams = [session.streams.app, session.streams.mic]

        guard streams.contains(where: { isLossless($0.file) }) else {
            removeLeftovers(in: folder, keeping: Set(streams.map(\.file)))
            return .alreadyCompressed
        }

        let app = try compressStream(session.streams.app.file, in: folder)
        let mic = try compressStream(session.streams.mic.file, in: folder)
        try session.replacingStreamFiles(app: app.file, mic: mic.file).encoded().write(to: sessionURL, options: .atomic)
        // Only now that session.json names the new files may the old ones go.
        for replaced in [app.replaced, mic.replaced].compactMap({ $0 }) {
            try FileManager.default.removeItem(at: replaced)
        }
        let saved = app.savedBytes + mic.savedBytes
        Logger.capture.notice("compressed a recording, saved \(saved, privacy: .public) bytes")
        return .compressed(savedBytes: saved)
    }

    /// An in-person meeting has one stream, named in `import.json`; imports and loose audio are not the app's own
    /// files and are left as they are.
    private static func compressInPerson(folder: URL) throws -> Outcome {
        guard let metadata = InPersonRecording.metadata(in: folder) else { return .notApplicable }
        guard isLossless(metadata.audioFile) else {
            removeLeftovers(in: folder, keeping: [metadata.audioFile])
            return .alreadyCompressed
        }
        let stream = try compressStream(metadata.audioFile, in: folder)
        try InPersonRecording.write(metadata.replacingAudioFile(stream.file), in: folder)
        if let replaced = stream.replaced { try FileManager.default.removeItem(at: replaced) }
        return .compressed(savedBytes: stream.savedBytes)
    }

    private struct StreamResult {
        let file: String
        /// The lossless file to delete once the session points at `file`.
        let replaced: URL?
        let savedBytes: Int64
    }

    private static func compressStream(_ file: String, in folder: URL) throws -> StreamResult {
        guard isLossless(file) else { return StreamResult(file: file, replaced: nil, savedBytes: 0) }
        let source = folder.appending(path: file)
        let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let target = folder.appending(path: "\(name).\(compressedExtension)")
        let temporary = folder.appending(path: "\(name).encoding.\(compressedExtension)")
        try? FileManager.default.removeItem(at: temporary)

        do {
            try encode(source, to: temporary)
            try verifyLength(of: temporary, matches: source, name: file)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: temporary, to: target)
        return StreamResult(
            file: target.lastPathComponent, replaced: source,
            savedBytes: max(0, fileSize(source) - fileSize(target))
        )
    }

    private static func encode(_ source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let channels = Int(input.fileFormat.channelCount)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: input.fileFormat.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRatePerChannel * channels,
        ]
        let output = try AVAudioFile(
            forWriting: destination, settings: settings,
            commonFormat: input.processingFormat.commonFormat, interleaved: input.processingFormat.isInterleaved
        )
        // Closed here where the system allows it; on iOS 17 it closes when `output` goes away as this returns.
        defer { if #available(iOS 18, *) { output.close() } }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 32_768) else {
            throw CompressionError.noBuffer
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
    }

    private static func verifyLength(of encoded: URL, matches source: URL, name: String) throws {
        let original = try AVAudioFile(forReading: source)
        let compressed = try AVAudioFile(forReading: encoded)
        let difference = abs(Double(compressed.length - original.length)) / original.processingFormat.sampleRate
        guard difference <= allowedLengthDifference else { throw CompressionError.lengthChanged(file: name) }
    }

    /// Lossless copies of the streams that `session.json` no longer names, and half-written encodes.
    private static func removeLeftovers(in folder: URL, keeping current: Set<String>) {
        let candidates = ["app.caf", "mic.caf", "app.encoding.m4a", "mic.encoding.m4a"]
        for name in candidates where !current.contains(name) {
            let url = folder.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Logger.capture.error("cannot remove a leftover stream: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func isLossless(_ file: String) -> Bool {
        losslessExtensions.contains(URL(fileURLWithPath: file).pathExtension.lowercased())
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return Int64(size ?? 0)
    }
}
