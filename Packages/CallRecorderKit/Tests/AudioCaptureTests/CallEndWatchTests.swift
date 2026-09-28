import Foundation
import Testing
@testable import AudioCapture

struct CallEndWatchTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(
        running: Bool = true, microphone: Bool?, othersSilent: TimeInterval = 0, meSilent: TimeInterval = 0
    ) -> CallEndWatch.Reading {
        CallEndWatch.Reading(
            appIsRunning: running, appUsesMicrophone: microphone, othersSilentFor: othersSilent, meSilentFor: meSilent
        )
    }

    @Test("the call app letting go of the microphone, with the others quiet for 30 s, ends the call")
    func microphoneReleased() {
        // Arrange
        var watch = CallEndWatch()
        #expect(watch.ending(after: reading(microphone: true), at: start) == nil)

        // Act
        let justReleased = watch.ending(after: reading(microphone: false, othersSilent: 5), at: start + 5)
        let stillEarly = watch.ending(after: reading(microphone: false, othersSilent: 29), at: start + 29)
        let ended = watch.ending(after: reading(microphone: false, othersSilent: 36), at: start + 36)

        // Assert
        #expect(justReleased == nil)
        #expect(stillEarly == nil)
        #expect(ended == .callFinished)
    }

    @Test("while the others are still talking a released microphone ends nothing (muted, not hung up)")
    func mutedButOthersTalking() {
        var watch = CallEndWatch()
        _ = watch.ending(after: reading(microphone: true), at: start)

        let verdict = watch.ending(after: reading(microphone: false, othersSilent: 2), at: start + 120)

        #expect(verdict == nil)
    }

    @Test("taking the microphone back starts the count again")
    func microphoneTakenBack() {
        var watch = CallEndWatch()
        _ = watch.ending(after: reading(microphone: true), at: start)
        _ = watch.ending(after: reading(microphone: false, othersSilent: 20), at: start + 20)
        _ = watch.ending(after: reading(microphone: true, othersSilent: 25), at: start + 25)

        let verdict = watch.ending(after: reading(microphone: false, othersSilent: 40), at: start + 45)

        #expect(verdict == nil, "only 20 s since the microphone was released again")
    }

    @Test("an app never seen on the microphone is judged by silence only")
    func neverSeenOnMicrophone() {
        var watch = CallEndWatch()

        let released = watch.ending(after: reading(microphone: false, othersSilent: 600), at: start + 600)
        let unknown = watch.ending(after: reading(microphone: nil, othersSilent: 700, meSilent: 700), at: start + 700)
        let silent = watch.ending(after: reading(microphone: nil, othersSilent: 900, meSilent: 900), at: start + 900)

        #expect(released == nil)
        #expect(unknown == nil)
        #expect(silent == .longSilence)
    }

    @Test("15 minutes of silence on both sides ends the recording even if the app keeps the microphone")
    func longSilence() {
        var watch = CallEndWatch()

        let verdict = watch.ending(after: reading(microphone: true, othersSilent: 900, meSilent: 900), at: start + 900)

        #expect(verdict == .longSilence)
    }

    @Test("the call app quitting ends the call at once")
    func appQuit() {
        var watch = CallEndWatch()

        #expect(watch.ending(after: reading(running: false, microphone: nil), at: start) == .appQuit)
    }
}
