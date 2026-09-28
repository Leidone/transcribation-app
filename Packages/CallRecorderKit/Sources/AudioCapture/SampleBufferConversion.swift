import AVFoundation
import CoreMedia

/// One decoded audio buffer plus the presentation timestamp (seconds) of its first frame.
///
/// `AVAudioPCMBuffer` is not `Sendable`; the buffer is created per callback and handed off once,
/// never mutated or shared afterwards, so crossing an isolation boundary is safe.
public struct PCMChunk: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    public let pts: Double
}

extension CMSampleBuffer {
    /// Copies the samples into an `AVAudioPCMBuffer` in the buffer's own format; `nil` if the data is not PCM.
    ///
    /// `public`: the iOS Broadcast Upload Extension (`RPBroadcastSampleHandler.processSampleBuffer`) hands it
    /// `CMSampleBuffer`s the same way `SCStreamOutput` does on macOS, and needs this conversion too.
    public func makePCMChunk() -> PCMChunk? {
        guard CMSampleBufferIsValid(self),
              let description = formatDescription,
              var streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let format = AVAudioFormat(streamDescription: &streamDescription)
        else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return PCMChunk(buffer: buffer, pts: CMSampleBufferGetPresentationTimeStamp(self).seconds)
    }
}
