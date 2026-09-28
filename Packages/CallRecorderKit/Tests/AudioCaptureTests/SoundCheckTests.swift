import Foundation
import Testing
@testable import AudioCapture

struct SoundCheckTests {
    @Test("nothing is said in the first seconds: people may still be joining")
    func quietAtFirst() {
        let problems = SoundCheck.problems(elapsed: 20, othersSilentFor: 20, meSilentFor: 20)

        #expect(problems.isEmpty)
    }

    @Test("not a sound from the call app for 30 s means the wrong app may be recorded")
    func othersNeverHeard() {
        let problems = SoundCheck.problems(elapsed: 31, othersSilentFor: 31, meSilentFor: 2)

        #expect(problems == [.othersNotHeard])
    }

    @Test("a silent microphone is reported only after a minute, since listening at first is normal")
    func microphoneNeverHeard() {
        #expect(SoundCheck.problems(elapsed: 45, othersSilentFor: 1, meSilentFor: 45).isEmpty)
        #expect(SoundCheck.problems(elapsed: 61, othersSilentFor: 1, meSilentFor: 61) == [.meNotHeard])
    }

    @Test("a side heard once is fine for the rest of the call, however quiet it goes")
    func heardOnceIsEnough() {
        let problems = SoundCheck.problems(elapsed: 600, othersSilentFor: 590, meSilentFor: 400)

        #expect(problems.isEmpty)
    }

    @Test("both problems can show at once")
    func bothSilent() {
        let problems = SoundCheck.problems(elapsed: 90, othersSilentFor: 90, meSilentFor: 90)

        #expect(problems == [.othersNotHeard, .meNotHeard])
    }

    @Test("a microphone giving only exact zeros is muted, and is reported within seconds instead of a minute")
    func mutedMicrophone() {
        #expect(SoundCheck.problems(elapsed: 5, othersSilentFor: 1, meSilentFor: 5, meIsMuted: true).isEmpty)
        #expect(SoundCheck.problems(elapsed: 9, othersSilentFor: 1, meSilentFor: 9, meIsMuted: true) == [.meMuted])
        #expect(SoundCheck.problems(elapsed: 90, othersSilentFor: 1, meSilentFor: 90, meIsMuted: true) == [.meMuted])
    }
}

