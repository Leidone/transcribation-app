#if os(macOS)
import AppKit

public enum RunningApplications {
    /// Regular (Dock-visible) apps that can be picked as a recording source. Needs no privacy permission.
    @MainActor
    public static func list(excludingBundleID ownBundleID: String? = Bundle.main.bundleIdentifier) -> [SourceApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application -> SourceApp? in
                guard let bundleID = application.bundleIdentifier,
                      bundleID != ownBundleID,
                      let name = application.localizedName
                else { return nil }
                return SourceApp(bundleID: bundleID, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
#endif
