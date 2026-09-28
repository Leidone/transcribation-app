#if os(iOS)
import Foundation

/// Where the host app and the Broadcast Upload Extension both write and read recordings on iOS. The two run in
/// different sandbox containers, so `URL.applicationSupportDirectory` (what macOS uses) is not shared between
/// them — an App Group container is the only location both can see.
public enum AppGroupStorage {
    public static let identifier = "group.app.callrecorder.dev"

    public static var recordingsDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appending(path: "Recordings", directoryHint: .isDirectory)
    }
}
#endif
