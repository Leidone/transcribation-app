import AudioCapture
import Foundation
import Testing
@testable import Transcription

private let rate = 16_000

private func silence(_ seconds: Double) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * Double(rate)))
}

private func tone(_ seconds: Double, amplitude: Float = 0.1) -> [Float] {
    (0..<Int(seconds * Double(rate))).map { amplitude * sin(2 * .pi * 300 * Float($0) / Float(rate)) }
}

@Test func speechBetweenPausesBecomesOnePhraseWithTheStartOfTheFirstWord() throws {
    var chunker = PhraseChunker()
    let phrases = chunker.feed(silence(1) + tone(1.5) + silence(1))
    let phrase = try #require(phrases.first)
    #expect(phrases.count == 1)
    // A fifth of a second before the first loud frame is kept.
    #expect(abs(phrase.startSeconds - 0.82) < 0.01)
    #expect(phrase.seconds > 1.5 && phrase.seconds < 2.4)
    let remainder = chunker.flush()
    #expect(remainder == nil)
}

/// Reproducible hiss: a fixed-seed generator, about −40 dBFS.
private func noise(_ seconds: Double) -> [Float] {
    var state: UInt32 = 12_345
    return (0..<Int(seconds * Double(rate))).map { _ in
        state = state &* 1_664_525 &+ 1_013_904_223
        return (Float(state >> 8) / Float(1 << 24) - 0.5) * 0.035
    }
}

@Test func aSteadilyNoisyMicrophoneStopsCountingAsSpeech() {
    var chunker = PhraseChunker()
    // Half a minute of hiss: at first it sounds like speech, then the chunker learns it is the background.
    #expect(chunker.feed(noise(30)).count <= 2)
    #expect(chunker.feed(noise(10)).isEmpty)
    // Real speech over the same hiss is still found.
    #expect(chunker.feed(tone(1) + noise(1.5)).count == 1)
}

@Test func aClickIsNotAPhrase() {
    var chunker = PhraseChunker()
    #expect(chunker.feed(silence(1) + tone(0.1) + silence(1)).isEmpty)
}

@Test func aLongMonologueIsCutEveryTwelveSeconds() throws {
    var chunker = PhraseChunker()
    let phrases = chunker.feed(tone(15))
    #expect(phrases.count == 1)
    #expect(abs((phrases.first?.seconds ?? 0) - 12) < 0.05)
    let flushed = chunker.flush()
    let rest = try #require(flushed)
    #expect(abs(rest.startSeconds - 12) < 0.05)
    #expect(abs(rest.seconds - 3) < 0.05)
}

@Test func piecesOfAnyLengthGiveTheSamePhrases() {
    var whole = PhraseChunker()
    var pieces = PhraseChunker()
    let audio = silence(0.5) + tone(1) + silence(1) + tone(0.8) + silence(1)
    let expected = whole.feed(audio)
    var found: [Phrase] = []
    var index = 0
    while index < audio.count {
        let end = min(audio.count, index + 441)
        found += pieces.feed(Array(audio[index..<end]))
        index = end
    }
    #expect(found == expected)
    #expect(expected.count == 2)
}

@Test func linesComeWithTheirVoiceAndTimeFromTheStartOfTheRecording() async throws {
    let transcriber = LiveTranscriber { samples in "фраза \(samples.count > 0)" }
    await transcriber.feed(LiveAudio(stream: .app, samples: silence(0.5), pts: 99.5))
    await transcriber.feed(LiveAudio(stream: .mic, samples: silence(1) + tone(1) + silence(1), pts: 100))

    var updates = transcriber.updates.makeAsyncIterator()
    let first = await updates.next()
    guard case .line(let line)? = first else {
        Issue.record("expected a line, got \(String(describing: first))")
        return
    }
    #expect(line.isMe)
    #expect(line.text == "фраза true")
    #expect(abs(line.time - 1.32) < 0.02)
    guard case .stats(let stats)? = await updates.next() else {
        Issue.record("expected statistics")
        return
    }
    #expect(stats.audioSeconds > 1)
    await transcriber.stop()
}

@Test func whenRecognitionFallsBehindTheOldestPhrasesAreSkipped() async {
    let transcriber = LiveTranscriber { _ in "x" }
    var audio: [Float] = []
    for _ in 0..<10 { audio += tone(0.5) + silence(0.8) }
    // All ten phrases end inside one piece, before recognition can start: four of them do not fit.
    await transcriber.feed(LiveAudio(stream: .app, samples: audio, pts: 0))

    var last = LiveStats()
    var statsSeen = 0
    for await update in transcriber.updates {
        guard case .stats(let stats) = update else { continue }
        last = stats
        statsSeen += 1
        if statsSeen == LiveTranscriber.maximumBacklog { break }
    }
    #expect(last.skippedPhrases == 4)
    await transcriber.stop()
}

@Test func finishingRecognisesThePhraseStillBeingSaid() async {
    let transcriber = LiveTranscriber { _ in "последняя фраза" }
    // The call ends mid-phrase: no pause follows the speech.
    await transcriber.feed(LiveAudio(stream: .mic, samples: silence(0.5) + tone(1), pts: 10))
    await transcriber.finish()
    var lines: [LiveLine] = []
    for await update in transcriber.updates {
        if case .line(let line) = update { lines.append(line) }
    }
    #expect(lines.map(\.text) == ["последняя фраза"])
    #expect(lines.first?.isMe == true)
}
