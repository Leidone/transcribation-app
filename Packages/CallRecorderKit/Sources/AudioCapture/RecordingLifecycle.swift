import Foundation

/// Phases of one recorder. The recorder is an actor, but its `start` suspends at `await`, so a second call can
/// arrive mid-start; `starting` is set synchronously before the first suspension to reject that call.
struct RecordingLifecycle: Equatable {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case stopping
    }

    private(set) var phase: Phase = .idle

    mutating func beginStart() throws(CaptureError) {
        guard phase == .idle else { throw .alreadyRecording }
        phase = .starting
    }

    mutating func markRecording() {
        phase = .recording
    }

    mutating func beginStop() throws(CaptureError) {
        guard phase == .recording else { throw .notRecording }
        phase = .stopping
    }

    /// Back to idle: after a stop, or after a start that failed.
    mutating func markStopped() {
        phase = .idle
    }
}
