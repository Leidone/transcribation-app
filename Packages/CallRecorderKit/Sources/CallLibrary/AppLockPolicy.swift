import Foundation

/// When the window asks for Touch ID (or the Mac's password): at launch, and after the person was away from the
/// app longer than the timeout. Recording is never affected — only what the window and the menu bar show.
public struct AppLockPolicy: Equatable, Sendable {
    public let isEnabled: Bool
    /// Seconds away before the lock comes back; 0 locks on every return.
    public let timeout: TimeInterval

    public static let timeouts: [TimeInterval] = [0, 60, 300, 900, 3_600]

    public init(isEnabled: Bool, timeout: TimeInterval) {
        self.isEnabled = isEnabled
        self.timeout = timeout
    }

    public var isLockedAtLaunch: Bool { isEnabled }

    public func locksAgain(leftAt: Date, backAt: Date) -> Bool {
        isEnabled && backAt.timeIntervalSince(leftAt) >= timeout
    }
}
