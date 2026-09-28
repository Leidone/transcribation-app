import Foundation
import Testing
@testable import AudioCapture

struct PauseClockTests {
    @Test("time on pause is not recording time")
    func pausedTimeIsLeftOut() {
        // Arrange: recording from 100, paused 130…190
        var clock = PauseClock()
        clock.pause(at: 130)
        clock.resume(at: 190)

        // Act, Assert
        #expect(clock.recordedTime(from: 100, to: 200) == 40)
        #expect(!clock.isPaused)
    }

    @Test("while paused the recorded time stands still")
    func standsStillWhilePaused() {
        var clock = PauseClock()
        clock.pause(at: 130)

        #expect(clock.isPaused)
        #expect(clock.recordedTime(from: 100, to: 150) == 30)
        #expect(clock.recordedTime(from: 100, to: 500) == 30)
    }

    @Test("several pauses add up; pausing twice or resuming unpaused changes nothing")
    func severalPauses() {
        var clock = PauseClock()
        clock.pause(at: 10)
        clock.pause(at: 12)
        clock.resume(at: 20)
        clock.resume(at: 25)
        clock.pause(at: 30)
        clock.resume(at: 35)

        #expect(clock.pausedTotal(at: 40) == 15)
        #expect(clock.recordedTime(from: 0, to: 40) == 25)
    }

    @Test("a chunk stamped inside a pause is dropped, one outside is kept")
    func chunksInsidePausesAreDropped() {
        var clock = PauseClock()
        clock.pause(at: 10)
        clock.resume(at: 20)
        clock.pause(at: 30)

        #expect(!clock.drops(at: 9.9))
        #expect(clock.drops(at: 15))
        #expect(!clock.drops(at: 25))
        #expect(clock.drops(at: 31))
    }

    @Test("silence cannot outlast the time since the last resume, so a long pause does not end the call")
    func silenceIsCappedByResume() {
        var clock = PauseClock()
        clock.pause(at: 100)
        clock.resume(at: 1_000)

        #expect(clock.capSilence(900, at: 1_010) == 10)
        #expect(clock.capSilence(5, at: 1_010) == 5)
        #expect(PauseClock().capSilence(900, at: 1_010) == 900)
    }
}
