import Foundation

/// What a build says about automatic updates: where the update feed is published and the key updates must be signed
/// with. Both are needed; a feed that is not HTTPS is refused, so an update can never be swapped on the way.
public struct UpdateConfiguration: Equatable, Sendable {
    public let feedURL: URL?
    public let publicKey: String

    public init(infoDictionary: [String: Any]) {
        let feed = (infoDictionary["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        feedURL = URL(string: feed).flatMap { $0.scheme == "https" && $0.host() != nil ? $0 : nil }
        publicKey = (infoDictionary["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    public var isComplete: Bool {
        feedURL != nil && !publicKey.isEmpty
    }
}
