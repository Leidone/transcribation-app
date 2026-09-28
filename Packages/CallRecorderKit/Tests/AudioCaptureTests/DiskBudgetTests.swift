import Foundation
import Testing
@testable import AudioCapture

struct DiskBudgetTests {
    private let gigabyte: Int64 = 1_000_000_000

    @Test("plenty of space is fine and says how long a recording can run")
    func plentyOfSpace() {
        let budget = DiskBudget(availableBytes: 50 * gigabyte)

        #expect(budget.level == .fine)
        #expect(budget.minutesLeft > 1_700 && budget.minutesLeft < 1_750)
    }

    @Test("under 3 GB is low: a long call may not fit")
    func lowSpace() {
        let budget = DiskBudget(availableBytes: 2 * gigabyte)

        #expect(budget.level == .low)
        #expect(budget.minutesLeft == 69)
    }

    @Test("under 300 MB is critical: nothing more is recorded")
    func criticalSpace() {
        #expect(DiskBudget(availableBytes: 299_000_000).level == .critical)
        #expect(DiskBudget(availableBytes: 301_000_000).level == .low)
        #expect(DiskBudget(availableBytes: 0).minutesLeft == 0)
    }

    @Test("the free space of a real folder can be read")
    func readsFreeSpace() throws {
        let available = try #require(DiskBudget.availableBytes(at: FileManager.default.temporaryDirectory))
        #expect(available > 0)
    }
}
