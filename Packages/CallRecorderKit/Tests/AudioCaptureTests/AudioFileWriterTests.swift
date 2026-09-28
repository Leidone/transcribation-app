import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

struct AudioFileWriterTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "writer-\(UUID().uuidString).caf")
    }

    private func makeChunk(sampleRate: Double = 48_000, frames: AVAudioFrameCount = 4_800, pts: Double) throws -> PCMChunk {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) { samples[frame] = sinf(Float(frame) * 0.05) * 0.5 }
        }
        return PCMChunk(buffer: buffer, pts: pts)
    }

    @Test("writes appended buffers losslessly and reports the first PTS")
    func writesBuffersAndReportsSummary() async throws {
        // Arrange
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = AudioFileWriter(url: url)

        // Act
        await writer.append(try makeChunk(pts: 12.5))
        await writer.append(try makeChunk(pts: 12.6))
        let summary = try #require(await writer.finish())

        // Assert
        #expect(summary.firstPTS == 12.5)
        #expect(summary.framesWritten == 9_600)
        #expect(summary.sampleRate == 48_000)
        #expect(summary.channels == 2)
        #expect(summary.droppedBuffers == 0)
        let readBack = try AVAudioFile(forReading: url)
        #expect(readBack.length == 9_600)
    }

    @Test("a writer that never received audio reports nothing and creates no file")
    func emptyWriterHasNoSummary() async {
        let url = temporaryURL()
        let writer = AudioFileWriter(url: url)

        let summary = await writer.finish()

        #expect(summary == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a buffer that only differs in channel layout metadata is still written")
    func layoutOnlyDifferenceIsAccepted() async throws {
        // Arrange
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = AudioFileWriter(url: url)
        let first = try makeChunk(pts: 1)
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 2))
        let taggedFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, interleaved: false, channelLayout: layout
        )
        try #require(taggedFormat != first.buffer.format, "the scenario needs formats that are not ==")
        let tagged = try #require(AVAudioPCMBuffer(pcmFormat: taggedFormat, frameCapacity: 4_800))
        tagged.frameLength = 4_800

        // Act
        await writer.append(first)
        await writer.append(PCMChunk(buffer: tagged, pts: 2))
        let summary = try #require(await writer.finish())

        // Assert
        #expect(summary.droppedBuffers == 0)
        #expect(summary.framesWritten == 9_600)
    }

    private func makeSilentChunk(frames: AVAudioFrameCount = 4_800, pts: Double) throws -> PCMChunk {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames // freshly allocated samples are zero
        return PCMChunk(buffer: buffer, pts: pts)
    }

    @Test("remembers when the stream last carried sound, so a quiet call can be noticed")
    func tracksLastSound() async throws {
        // Arrange
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = AudioFileWriter(url: url)
        #expect(await writer.lastSoundEnd == nil)

        // Act: 0.1 s of tone at 10 s, then two silent chunks
        await writer.append(try makeChunk(pts: 10))
        let afterSound = await writer.lastSoundEnd
        await writer.append(try makeSilentChunk(pts: 10.1))
        await writer.append(try makeSilentChunk(pts: 10.2))

        // Assert
        #expect(afterSound.map { abs($0 - 10.1) < 0.000_1 } == true)
        #expect(await writer.lastSoundEnd == afterSound, "silence must not move the last sound")
    }

    @Test("a buffer in a different format is counted as dropped")
    func formatChangeIsDropped() async throws {
        // Arrange
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = AudioFileWriter(url: url)

        // Act
        await writer.append(try makeChunk(sampleRate: 48_000, pts: 1))
        await writer.append(try makeChunk(sampleRate: 44_100, pts: 2))
        let summary = try #require(await writer.finish())

        // Assert
        #expect(summary.droppedBuffers == 1)
        #expect(summary.framesWritten == 4_800)
    }
}
