import Foundation
import Testing
@testable import AudioCapture

struct RecordingLifecycleTests {
    @Test("a second start while the first is still starting is rejected")
    func secondStartWhileStartingIsRejected() throws {
        // Arrange
        var lifecycle = RecordingLifecycle()
        try lifecycle.beginStart()

        // Act / Assert
        #expect(throws: CaptureError.alreadyRecording) { try lifecycle.beginStart() }
    }

    @Test("start is rejected while recording and allowed again after stopping")
    func startAfterStop() throws {
        var lifecycle = RecordingLifecycle()
        try lifecycle.beginStart()
        lifecycle.markRecording()
        #expect(throws: CaptureError.alreadyRecording) { try lifecycle.beginStart() }

        try lifecycle.beginStop()
        lifecycle.markStopped()

        #expect(throws: Never.self) { try lifecycle.beginStart() }
    }

    @Test("a failed start returns to idle so the user can retry")
    func failedStartCanBeRetried() throws {
        var lifecycle = RecordingLifecycle()
        try lifecycle.beginStart()

        lifecycle.markStopped()

        #expect(lifecycle.phase == .idle)
        #expect(throws: Never.self) { try lifecycle.beginStart() }
    }

    @Test("stopping is only possible while recording")
    func stopRequiresRecording() throws {
        var lifecycle = RecordingLifecycle()
        #expect(throws: CaptureError.notRecording) { try lifecycle.beginStop() }

        try lifecycle.beginStart()
        #expect(throws: CaptureError.notRecording) { try lifecycle.beginStop() }
    }
}
