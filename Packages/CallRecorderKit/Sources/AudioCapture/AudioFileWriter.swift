import AVFoundation
import Accelerate
import os

extension Logger {
    static let capture = Logger(subsystem: "app.callrecorder.dev", category: "capture")
}

/// Writes one audio stream to a lossless CAF file. The file is created from the first buffer's
/// format, so the recorded sample rate and channel count are the real ones, not assumed ones.
///
/// `public`: on iOS the Broadcast Upload Extension (a separate binary/target from the host app) writes
/// through this same type, so it must be visible outside this module.
public actor AudioFileWriter {
    public struct Summary: Equatable, Sendable {
        public let sampleRate: Double
        public let channels: Int
        public let firstPTS: Double
        public let droppedBuffers: Int
        public let framesWritten: Int64
    }

    private let url: URL
    private var file: AVAudioFile?
    private var firstPTS: Double?
    private var droppedBuffers = 0
    private(set) var framesWritten: Int64 = 0
    /// Where (on the same clock as the chunks' PTS) the stream last carried sound; `nil` until it has. Lets the
    /// app notice a call that went quiet long ago.
    public private(set) var lastSoundEnd: Double?
    /// Whether any sample so far was not exactly zero. A stream of exact zeros comes from a muted device.
    public private(set) var hasSignal = false
    /// About −50 dBFS: quieter than any speech, louder than a silent line's noise floor.
    private static let soundThreshold: Float = 0.003

    public init(url: URL) {
        self.url = url
    }

    /// Never throws: a buffer that cannot be written is counted as dropped and logged.
    public func append(_ chunk: PCMChunk) {
        let format = chunk.buffer.format
        do {
            let file = try openFile(matching: format)
            guard let writable = Self.buffer(chunk.buffer, in: file.processingFormat) else {
                droppedBuffers += 1
                Logger.capture.error("format changed mid-stream, buffer dropped")
                return
            }
            try file.write(from: writable)
            firstPTS = firstPTS ?? chunk.pts
            framesWritten += Int64(chunk.buffer.frameLength)
            if !hasSignal { hasSignal = Self.hasAnySignal(chunk.buffer) }
            if Self.carriesSound(chunk.buffer) {
                lastSoundEnd = chunk.pts + Double(chunk.buffer.frameLength) / format.sampleRate
            }
        } catch {
            droppedBuffers += 1
            Logger.capture.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Closes the file. `nil` if no audio was ever written.
    public func finish() -> Summary? {
        defer { file = nil }
        guard let file, let firstPTS else { return nil }
        return Summary(
            sampleRate: file.processingFormat.sampleRate,
            channels: Int(file.processingFormat.channelCount),
            firstPTS: firstPTS,
            droppedBuffers: droppedBuffers,
            framesWritten: framesWritten
        )
    }

    /// The buffer itself when its format equals the file's; a copy in the file's format when they differ only
    /// in metadata such as channel layout (`AVAudioFormat ==` is stricter than the sample data requires);
    /// `nil` when rate, channel count, sample type or interleaving really differ.
    private static func buffer(_ buffer: AVAudioPCMBuffer, in target: AVAudioFormat) -> AVAudioPCMBuffer? {
        let source = buffer.format
        if source == target { return buffer }
        guard source.sampleRate == target.sampleRate,
              source.channelCount == target.channelCount,
              source.commonFormat == target.commonFormat,
              source.isInterleaved == target.isInterleaved,
              let copy = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: buffer.frameLength)
        else { return nil }
        copy.frameLength = buffer.frameLength

        let sources = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinations = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(sources, destinations) {
            guard let sourceData = from.mData, let destinationData = to.mData else { continue }
            memcpy(destinationData, sourceData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }

    /// Whether any sample is above the sound threshold. Formats other than float and 16-bit are counted as sound,
    /// so an unknown format never makes a call look silent.
    /// Any sample that is not exactly zero (float data; other formats are taken as having a signal).
    static func hasAnySignal(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let floats = buffer.floatChannelData else { return true }
        let channels = Int(buffer.format.channelCount)
        let pointers = buffer.format.isInterleaved ? 1 : channels
        let count = Int(buffer.frameLength) * (buffer.format.isInterleaved ? channels : 1)
        return (0..<pointers).contains { channel in
            var peak: Float = 0
            vDSP_maxmgv(floats[channel], 1, &peak, vDSP_Length(count))
            return peak > 0
        }
    }

    private static func carriesSound(_ buffer: AVAudioPCMBuffer) -> Bool {
        let channels = Int(buffer.format.channelCount)
        // Interleaved samples all sit behind the first pointer; otherwise each channel has its own.
        let pointers = buffer.format.isInterleaved ? 1 : channels
        let count = Int(buffer.frameLength) * (buffer.format.isInterleaved ? channels : 1)
        if let floats = buffer.floatChannelData {
            return (0..<pointers).contains { channel in
                var peak: Float = 0
                vDSP_maxmgv(floats[channel], 1, &peak, vDSP_Length(count))
                return peak > soundThreshold
            }
        }
        if let shorts = buffer.int16ChannelData {
            let threshold = Int16(soundThreshold * Float(Int16.max))
            return (0..<pointers).contains { channel in
                UnsafeBufferPointer(start: shorts[channel], count: count).contains { abs(Int32($0)) > threshold }
            }
        }
        return true
    }

    private func openFile(matching format: AVAudioFormat) throws -> AVAudioFile {
        if let file { return file }
        let created = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        file = created
        return created
    }
}
