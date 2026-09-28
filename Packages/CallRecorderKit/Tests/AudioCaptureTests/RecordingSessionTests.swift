import Foundation
import Testing
@testable import AudioCapture

struct RecordingSessionTests {
    private func makeStream(file: String, firstPTS: Double, droppedBuffers: Int = 0) -> StreamInfo {
        StreamInfo(file: file, sampleRate: 48_000, channels: 2, firstPTS: firstPTS, droppedBuffers: droppedBuffers)
    }

    private func makeSession(appPTS: Double = 10.000, micPTS: Double = 10.042) -> RecordingSession {
        RecordingSession(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            app: SourceApp(bundleID: "us.zoom.xos", name: "zoom.us"),
            method: .screenCaptureKit,
            streams: Streams(
                app: makeStream(file: "app.caf", firstPTS: appPTS),
                mic: makeStream(file: "mic.caf", firstPTS: micPTS)
            )
        )
    }

    @Test("sidecar round-trips without loss")
    func sidecarRoundTrip() throws {
        // Arrange
        let session = makeSession()

        // Act
        let decoded = try RecordingSession.decode(from: session.encoded())

        // Assert
        #expect(decoded == session)
    }

    @Test("sync offset is mic first PTS minus app first PTS")
    func syncOffset() {
        // Arrange
        let session = makeSession(appPTS: 10.000, micPTS: 10.042)

        // Act
        let offset = session.syncOffsetSeconds

        // Assert
        #expect(abs(offset - 0.042) < 1e-9)
    }

    @Test("decoding fails when the microphone stream is missing")
    func decodeMissingMicStream() throws {
        // Arrange
        let json = """
        {"id":"11111111-2222-3333-4444-555555555555","startedAt":"2027-01-15T08:00:00Z",
         "app":{"bundleID":"us.zoom.xos","name":"zoom.us"},"method":"screenCaptureKit",
         "streams":{"app":{"file":"app.caf","sampleRate":48000,"channels":2,"firstPTS":10,"droppedBuffers":0}}}
        """.data(using: .utf8)!

        // Act / Assert
        #expect(throws: DecodingError.self) {
            try RecordingSession.decode(from: json)
        }
    }

    @Test("updating dropped buffers returns a copy and leaves the original unchanged")
    func droppedBuffersAreImmutableUpdate() {
        // Arrange
        let original = makeSession()

        // Act
        let updated = original.recordingDroppedBuffers(app: 3, mic: 1)

        // Assert
        #expect(original.streams.app.droppedBuffers == 0)
        #expect(updated.streams.app.droppedBuffers == 3)
        #expect(updated.streams.mic.droppedBuffers == 1)
    }

    @Test("encoding is deterministic so sidecars diff cleanly")
    func encodingIsDeterministic() throws {
        // Arrange
        let session = makeSession()

        // Act
        let first = try session.encoded()
        let second = try session.encoded()

        // Assert
        #expect(first == second)
    }
}
