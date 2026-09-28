import Foundation

/// Decides, from readings taken every few seconds during a recording, that the call is over, so a forgotten
/// recording does not run on for hours. It errs on the side of recording on: a person who muted themselves is
/// still in the call as long as the others can be heard.
public struct CallEndWatch: Equatable, Sendable {
    public enum Ending: Equatable, Sendable {
        /// The call app was closed.
        case appQuit
        /// The call app let go of the microphone and the others went quiet: the call was hung up.
        case callFinished
        /// Nobody has said anything for a long time.
        case longSilence
    }

    public struct Reading: Equatable, Sendable {
        public let appIsRunning: Bool
        /// Whether the call app is using a microphone; `nil` when the system cannot tell for this app.
        public let appUsesMicrophone: Bool?
        public let othersSilentFor: TimeInterval
        public let meSilentFor: TimeInterval

        public init(appIsRunning: Bool, appUsesMicrophone: Bool?, othersSilentFor: TimeInterval, meSilentFor: TimeInterval) {
            self.appIsRunning = appIsRunning
            self.appUsesMicrophone = appUsesMicrophone
            self.othersSilentFor = othersSilentFor
            self.meSilentFor = meSilentFor
        }
    }

    /// How long the microphone must stay released, with the others quiet, before the call counts as finished.
    public static let hangUpGrace: TimeInterval = 30
    /// Silence on both sides this long ends the recording whatever the app does.
    public static let silenceLimit: TimeInterval = 15 * 60

    /// The app was seen on the microphone during this recording, so letting go of it means something.
    private var hasSeenMicrophone = false
    private var releasedAt: Date?

    public init() {}

    /// Feeds one reading; returns how the call ended, or `nil` while it goes on.
    public mutating func ending(after reading: Reading, at now: Date) -> Ending? {
        guard reading.appIsRunning else { return .appQuit }

        switch reading.appUsesMicrophone {
        case true?:
            hasSeenMicrophone = true
            releasedAt = nil
        case false? where hasSeenMicrophone:
            releasedAt = releasedAt ?? now
        default:
            break
        }

        if let releasedAt, now.timeIntervalSince(releasedAt) >= Self.hangUpGrace,
           reading.othersSilentFor >= Self.hangUpGrace {
            return .callFinished
        }
        if reading.othersSilentFor >= Self.silenceLimit, reading.meSilentFor >= Self.silenceLimit {
            return .longSilence
        }
        return nil
    }
}
