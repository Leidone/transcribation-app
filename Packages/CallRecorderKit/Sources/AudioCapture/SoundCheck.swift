import Foundation

/// Notices early in a recording that one side has not made a sound at all — most often the wrong app was chosen,
/// or the microphone is muted in the system — while there is still time to fix it. A side heard even once is never
/// reported again: quiet stretches later in a call are normal.
public enum SoundCheck {
    public enum Problem: Hashable, Sendable {
        /// Not a sound from the recorded app.
        case othersNotHeard
        /// Not a sound from the microphone.
        case meNotHeard
        /// The microphone gives exact digital zeros: it is muted (a headset button, the call app, the system).
        /// Even a silent room is never exactly zero, so this is certain much sooner than plain quiet.
        case meMuted
    }

    /// A muted microphone is certain after a few seconds of zeros.
    public static let mutedGrace: TimeInterval = 8

    /// People may still be joining; after this long, silence from the call app is suspicious.
    public static let othersGrace: TimeInterval = 30
    /// Listening quietly at the start is normal, so the microphone gets longer.
    public static let meGrace: TimeInterval = 60
    /// A side silent for (almost) the whole recording has never been heard.
    private static let tolerance: TimeInterval = 1

    /// What to warn about now, from how long the recording has run and how long each side has been silent (the
    /// silence is counted from the start while a side has never been heard).
    public static func problems(
        elapsed: TimeInterval, othersSilentFor: TimeInterval, meSilentFor: TimeInterval, meIsMuted: Bool = false
    ) -> Set<Problem> {
        var problems: Set<Problem> = []
        if elapsed >= othersGrace, othersSilentFor >= elapsed - tolerance { problems.insert(.othersNotHeard) }
        if meIsMuted {
            if elapsed >= mutedGrace { problems.insert(.meMuted) }
        } else if elapsed >= meGrace, meSilentFor >= elapsed - tolerance {
            problems.insert(.meNotHeard)
        }
        return problems
    }
}
