import Foundation
import os

/// How much recording still fits on the disk. A capture is written lossless while it runs (about 1.7 GB an hour),
/// so a long call on a nearly full Mac can run out of space before it ends.
public struct DiskBudget: Equatable, Sendable {
    public enum Level: Equatable, Sendable {
        case fine
        /// A long call may not fit: worth a warning.
        case low
        /// Nothing more should be recorded: the system itself starts failing around here.
        case critical
    }

    /// What the app's capture writes per second: the call app at 48 kHz stereo and the microphone at 24 kHz
    /// mono, both as 32-bit float.
    public static let losslessBytesPerSecond: Double = 48_000 * 2 * 4 + 24_000 * 4
    static let lowThreshold: Int64 = 3_000_000_000
    static let criticalThreshold: Int64 = 300_000_000

    public let availableBytes: Int64

    public init(availableBytes: Int64) {
        self.availableBytes = availableBytes
    }

    public var level: Level {
        if availableBytes < Self.criticalThreshold { return .critical }
        if availableBytes < Self.lowThreshold { return .low }
        return .fine
    }

    /// Whole minutes of recording that still fit.
    public var minutesLeft: Int {
        Int(Double(max(0, availableBytes)) / Self.losslessBytesPerSecond / 60)
    }

    /// Space available for the user's own files on the volume holding `url` (what Finder shows as available);
    /// `nil` if the system cannot say.
    public static func availableBytes(at url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            Logger.capture.error("cannot read free disk space: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
