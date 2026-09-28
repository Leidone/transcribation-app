import Foundation

/// A phrase cut out of a running stream: 16 kHz mono samples and where they started, in samples from the start of
/// the stream.
public struct Phrase: Equatable, Sendable {
    public let startSample: Int
    public let samples: [Float]

    public var startSeconds: Double { Double(startSample) / PhraseChunker.sampleRate }
    public var seconds: Double { Double(samples.count) / PhraseChunker.sampleRate }
}

/// Cuts a live 16 kHz stream into phrases at pauses, so each can be recognised as soon as it is said. It listens to
/// loudness only: a frame well above the stream's own background counts as speech. Too-short bursts (a click, a
/// cough) are dropped; a monologue without pauses is cut every `maximumPhrase` seconds.
public struct PhraseChunker: Sendable {
    public static let sampleRate = 16_000.0
    /// 20 ms.
    static let frame = 320
    /// This much quiet after speech ends a phrase.
    static let pauseFrames = 30
    /// Kept before the first loud frame, so the first sound of a word is not cut.
    static let leadFrames = 10
    /// Speech shorter than this is not a phrase.
    static let minimumSpeechFrames = 12
    /// Longer speech is cut here even without a pause.
    static let maximumPhraseFrames = 600
    /// Nothing quieter is ever speech, however silent the line.
    static let absoluteFloor: Float = 0.004

    private var leftover: [Float] = []
    private var lead: [[Float]] = []
    private var current: [Float] = []
    private var currentStart = 0
    private var speechFrames = 0
    private var quietFrames = 0
    private var isInPhrase = false
    /// Samples taken in so far; the position of the next frame.
    private var position = 0
    /// The loudness of the background, following it slowly.
    private var background: Float = 0.002

    public init() {}

    /// Takes the next samples and returns the phrases that ended in them.
    public mutating func feed(_ samples: [Float]) -> [Phrase] {
        leftover += samples
        var finished: [Phrase] = []
        var offset = 0
        while leftover.count - offset >= Self.frame {
            let frame = Array(leftover[offset..<(offset + Self.frame)])
            offset += Self.frame
            if let phrase = take(frame) { finished.append(phrase) }
        }
        leftover.removeFirst(offset)
        return finished
    }

    /// The phrase still being said, when the stream ends.
    public mutating func flush() -> Phrase? {
        defer { reset() }
        guard isInPhrase, speechFrames >= Self.minimumSpeechFrames else { return nil }
        return Phrase(startSample: currentStart, samples: current)
    }

    private mutating func take(_ frame: [Float]) -> Phrase? {
        defer { position += frame.count }
        let level = Self.loudness(of: frame)
        let isSpeech = level > max(Self.absoluteFloor, background * 3)
        // Quiet frames set the background quickly. Loud ones move it too, but only over about a minute: a
        // steadily noisy microphone stops counting as speech, while real speech, which always has pauses, never
        // lifts it much.
        background = isSpeech ? background * 0.9997 + level * 0.0003 : background * 0.98 + level * 0.02

        guard isInPhrase else {
            lead.append(frame)
            if lead.count > Self.leadFrames { lead.removeFirst() }
            if isSpeech {
                isInPhrase = true
                current = lead.flatMap { $0 }
                currentStart = position + frame.count - current.count
                speechFrames = 1
                quietFrames = 0
                lead = []
            }
            return nil
        }

        current += frame
        if isSpeech {
            speechFrames += 1
            quietFrames = 0
        } else {
            quietFrames += 1
        }
        let frames = current.count / Self.frame
        guard quietFrames >= Self.pauseFrames || frames >= Self.maximumPhraseFrames else { return nil }

        let phrase = speechFrames >= Self.minimumSpeechFrames ? Phrase(startSample: currentStart, samples: current) : nil
        let continues = quietFrames < Self.pauseFrames
        reset()
        if continues {
            // Cut in the middle of speech: the next phrase starts right here.
            isInPhrase = true
            currentStart = position + frame.count
            speechFrames = 0
        }
        return phrase
    }

    private mutating func reset() {
        current = []
        lead = []
        speechFrames = 0
        quietFrames = 0
        isInPhrase = false
    }

    static func loudness(of frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0 }
        let energy = frame.reduce(Float(0)) { $0 + $1 * $1 }
        return (energy / Float(frame.count)).squareRoot()
    }
}
