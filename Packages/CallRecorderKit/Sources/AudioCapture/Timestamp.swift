import Foundation

/// The `yyyyMMdd-HHmmss` prefix used to name a recording's folder, shared by every way a recording can be
/// created (capture on macOS, import on any platform) so folders always sort chronologically.
public enum RecordingTimestamp {
    public static func folderName(_ date: Date) -> String {
        date.formatted(.verbatim(
            "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            locale: .init(identifier: "en_US_POSIX"), timeZone: .current, calendar: .current
        ))
    }
}
