import Foundation
import Testing
@testable import CallLibrary

struct AppLockTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("with the lock on, the window starts locked; with it off, never")
    func startsLocked() {
        #expect(AppLockPolicy(isEnabled: true, timeout: 300).isLockedAtLaunch)
        #expect(!AppLockPolicy(isEnabled: false, timeout: 300).isLockedAtLaunch)
    }

    @Test("away longer than the timeout locks again; a short look elsewhere does not")
    func timeout() {
        let policy = AppLockPolicy(isEnabled: true, timeout: 300)

        #expect(!policy.locksAgain(leftAt: start, backAt: start + 120))
        #expect(policy.locksAgain(leftAt: start, backAt: start + 301))
        #expect(!AppLockPolicy(isEnabled: false, timeout: 300).locksAgain(leftAt: start, backAt: start + 3_600))
    }

    @Test("a timeout of zero locks on every return")
    func zeroTimeout() {
        #expect(AppLockPolicy(isEnabled: true, timeout: 0).locksAgain(leftAt: start, backAt: start + 1))
    }
}
