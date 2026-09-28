import Foundation

/// The pauses of one recording, on the host clock the audio is stamped with. Sound that arrives during a pause is
/// not written, so the files — and the transcript's times — hold recorded time only; marks and silence are counted
/// the same way.
public struct PauseClock: Equatable, Sendable {
    private var finished: [ClosedRange<Double>] = []
    private var pausedSince: Double?

    public init() {}

    public var isPaused: Bool { pausedSince != nil }

    /// Starts a pause; nothing happens while one is already going.
    public mutating func pause(at time: Double) {
        guard pausedSince == nil else { return }
        pausedSince = time
    }

    /// Ends the pause going on; nothing happens when there is none.
    public mutating func resume(at time: Double) {
        guard let start = pausedSince else { return }
        finished.append(start...max(start, time))
        pausedSince = nil
    }

    /// All the time spent on pause up to `now`.
    public func pausedTotal(at now: Double) -> Double {
        let done = finished.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        return done + (pausedSince.map { max(0, now - $0) } ?? 0)
    }

    /// Time actually recorded between `start` and `now`.
    public func recordedTime(from start: Double, to now: Double) -> Double {
        max(0, now - start - pausedTotal(at: now))
    }

    /// Whether audio stamped `time` falls inside a pause and is to be left out.
    public func drops(at time: Double) -> Bool {
        if let pausedSince, time >= pausedSince { return true }
        return finished.contains { $0.contains(time) }
    }

    /// Silence counts from the last resume at most: waiting on pause is not the call going quiet.
    public func capSilence(_ silence: Double, at now: Double) -> Double {
        guard let lastResume = finished.last?.upperBound else { return silence }
        return min(silence, max(0, now - lastResume))
    }
}
