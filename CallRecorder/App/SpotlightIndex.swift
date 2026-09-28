import CallLibrary
import CoreSpotlight
import UniformTypeIdentifiers
import os

private let spotlightLog = Logger(subsystem: "app.callrecorder.dev", category: "spotlight")

/// Keeps Spotlight's index of the recordings in step with the library: new and changed recordings are indexed,
/// deleted ones removed. The index belongs to macOS and stays on this Mac.
@MainActor
final class SpotlightIndex {
    /// What was last sent for each recording in this run, so an unchanged recording is not sent again.
    private var sent: [String: SpotlightEntry] = [:]
    private var pending: Task<Void, Never>?

    /// Builds the entries off the main actor (long transcripts make them large), then sends what changed.
    func update(with recordings: [RecordingItem]) {
        pending?.cancel()
        pending = Task {
            let entries = await Task.detached(priority: .utility) { SpotlightEntry.entries(for: recordings) }.value
            guard !Task.isCancelled else { return }
            send(entries)
        }
    }

    private func send(_ entries: [SpotlightEntry]) {
        let changed = entries.filter { sent[$0.id] != $0 }
        let current = Set(entries.map(\.id))
        let gone = sent.keys.filter { !current.contains($0) }

        if !changed.isEmpty {
            CSSearchableIndex.default().indexSearchableItems(changed.map(Self.item)) { error in
                if let error { spotlightLog.error("indexing failed: \(error.localizedDescription, privacy: .public)") }
            }
            for entry in changed { sent[entry.id] = entry }
        }
        if !gone.isEmpty {
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: gone) { error in
                if let error { spotlightLog.error("removal failed: \(error.localizedDescription, privacy: .public)") }
            }
            for id in gone { sent[id] = nil }
        }
    }

    /// Empties the index, when the person turns Spotlight search off.
    func removeAll() {
        pending?.cancel()
        sent = [:]
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [SpotlightEntry.domain]) { error in
            if let error { spotlightLog.error("clearing failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// The recording a Spotlight hit stands for.
    static func recordingID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }
        return UUID(uuidString: identifier)
    }

    private static func item(_ entry: SpotlightEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = entry.title
        attributes.contentDescription = entry.summary
        attributes.textContent = entry.text
        attributes.contentCreationDate = entry.date
        attributes.duration = NSNumber(value: entry.duration)
        attributes.keywords = entry.people
        return CSSearchableItem(uniqueIdentifier: entry.id, domainIdentifier: SpotlightEntry.domain, attributeSet: attributes)
    }
}
