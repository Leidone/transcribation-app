import Foundation
import Testing
@testable import CodexClient

struct CompactTranscriptTests {
    private func line(_ time: Double, _ speaker: String, _ text: String) -> CompactLine {
        CompactLine(time: time, speaker: speaker, text: text)
    }

    @Test("neighbouring lines of one speaker become a single turn")
    func mergesSameSpeaker() {
        let text = CompactTranscript.make([
            line(0, "Анна", "Привет."), line(3, "Анна", "Начинаем."), line(20, "Борис", "Да."),
        ])

        #expect(text == "0:00 Анна: Привет. Начинаем.\n0:20 Борис: Да.")
    }

    @Test("a long pause starts a new turn even for the same speaker")
    func pauseSplits() {
        let text = CompactTranscript.make([line(0, "Анна", "Раз."), line(30, "Анна", "Два.")])

        #expect(text == "0:00 Анна: Раз.\n0:30 Анна: Два.")
    }

    @Test("empty lines are dropped and whitespace is collapsed")
    func cleaning() {
        let text = CompactTranscript.make([line(0, "Я", "  много   пробелов \n тут "), line(5, "Я", "   ")])

        #expect(text == "0:00 Я: много пробелов тут")
    }

    @Test("minutes keep counting past an hour")
    func longClock() {
        #expect(CompactTranscript.make([line(3903, "Я", "Конец.")]) == "65:03 Я: Конец.")
        #expect(CompactTranscript.make([line(65, "Я", "Минута.")]) == "1:05 Я: Минута.")
    }

    @Test("the compact form is shorter than the bracketed original for the same call")
    func shorterThanOriginal() {
        let lines = (0..<20).map { line(Double($0) * 2, "Собеседник 1", "Слово номер \($0).") }
        let original = lines.map { "[00:\(String(format: "%02d", Int($0.time)))] \($0.speaker): \($0.text)" }.joined(separator: "\n")

        let compact = CompactTranscript.make(lines)

        #expect(TokenEstimate.of(compact) < TokenEstimate.of(original) / 2)
    }

    @Test("Russian costs more tokens than English for the same length, and longer text costs more")
    func estimate() {
        #expect(TokenEstimate.of(String(repeating: "я", count: 100)) > TokenEstimate.of(String(repeating: "a", count: 100)))
        #expect(TokenEstimate.of("короткий") < TokenEstimate.of("короткий текст подлиннее"))
        #expect(TokenEstimate.of("") == 0)
    }
}
