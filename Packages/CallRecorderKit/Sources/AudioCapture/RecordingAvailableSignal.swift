#if os(iOS)
import Foundation

/// A cross-process "something changed, refresh now" nudge from the Broadcast Upload Extension to the host app.
/// Darwin notifications carry no payload and are not guaranteed to reach a fully suspended app, so this is a
/// convenience only — the reliable path is the host app re-scanning `AppGroupStorage.recordingsDirectory`
/// every time it returns to the foreground (it does that regardless of whether this fires).
public enum RecordingAvailableSignal {
    private static let name = "app.callrecorder.dev.recordingAvailable"

    public static func post() {
        let name = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true)
    }

    /// Calls `handler` (on an unspecified queue) whenever `post()` fires anywhere in the app group, until the
    /// returned token is deallocated or `stop(observing:)` is called with it.
    public static func observe(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        let token = Observer(handler: handler)
        let observer = Unmanaged.passUnretained(token).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name as CFString, nil, .deliverImmediately
        )
        return token
    }

    public static func stop(observing token: AnyObject) {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(token).toOpaque(),
            CFNotificationName(name as CFString), nil
        )
    }

    private final class Observer {
        let handler: @Sendable () -> Void
        init(handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }
}
#endif
