@preconcurrency import AVFoundation
import os

/// A piece of a running recording for the transcription during the call: 16 kHz mono samples of one stream.
public struct LiveAudio: Sendable {
    public enum Stream: Sendable {
        /// The other participants (the recorded app).
        case app
        /// The person's own microphone.
        case mic
    }

    public static let sampleRate = 16_000.0

    public let stream: Stream
    public let samples: [Float]
    /// When the first sample was captured, on the clock of the capture's timestamps (host time, seconds).
    public let pts: Double

    public init(stream: Stream, samples: [Float], pts: Double) {
        self.stream = stream
        self.samples = samples
        self.pts = pts
    }
}

/// Turns buffers of any PCM format into 16 kHz mono Float32 for speech recognition. The converter keeps its state
/// from one buffer to the next, so the resampled stream has no seams at buffer boundaries.
final class MonoResampler {
    private static let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: LiveAudio.sampleRate, channels: 1, interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        if converter == nil || sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: Self.target)
            converter?.downmix = true
            sourceFormat = buffer.format
        }
        guard let converter, buffer.frameLength > 0 else { return [] }
        let ratio = Self.target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.target, frameCapacity: capacity) else { return [] }

        // The buffer is handed over once; "no data now" (not "end of stream") keeps the converter's state for the
        // next buffer.
        let handedOver = OSAllocatedUnfairLock(initialState: false)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            let alreadyGiven = handedOver.withLock { given -> Bool in
                defer { given = true }
                return given
            }
            if alreadyGiven {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = output.floatChannelData else {
            Logger.capture.error("live resampling failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return []
        }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }
}
