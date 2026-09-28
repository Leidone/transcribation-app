import Foundation

/// Where in a recording a search term was found, with a short piece of the surrounding text to show.
public struct SearchHit: Equatable, Sendable, Identifiable {
    public enum Place: Equatable, Sendable {
        case title
        case summary
        case decision
        case task
        /// A transcript line, with the moment it was said so the player can jump there.
        case transcript(lineID: Int, time: TimeInterval)
    }

    public let place: Place
    public let snippet: String

    public var id: String { "\(place)-\(snippet)" }
}

/// Full-text search over the library, on this device only. Case, `ё`/`е` and accents do not matter; every word of
/// the query must occur somewhere in the recording (title, speaker names, summary, decisions, tasks or transcript).
public enum LibrarySearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private static let snippetRadius = 40

    /// The words of a query; an empty list means "show everything".
    public static func terms(of query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
    }

    public static func filter(_ recordings: [RecordingItem], query: String) -> [RecordingItem] {
        let words = terms(of: query)
        guard !words.isEmpty else { return recordings }
        return recordings.filter { matches($0, terms: words) }
    }

    public static func matches(_ recording: RecordingItem, terms words: [String]) -> Bool {
        let fields = searchableText(of: recording)
        return words.allSatisfy { word in fields.contains { $0.range(of: word, options: options) != nil } }
    }

    /// The places a query was found in one recording, title first and transcript last, at most `limit` of them.
    public static func hits(in recording: RecordingItem, query: String, limit: Int = 3) -> [SearchHit] {
        let words = terms(of: query)
        guard !words.isEmpty else { return [] }

        var candidates: [(SearchHit.Place, String)] = [(.title, recording.title)]
        if let analysis = recording.analysis {
            candidates.append((.summary, analysis.summary))
            candidates += analysis.decisions.map { (.decision, $0) }
            candidates += analysis.tasks.map { (.task, $0.title) }
        }
        candidates += recording.transcript.map {
            (.transcript(lineID: $0.id, time: $0.time), "\(recording.displayName($0.speaker)): \($0.text)")
        }

        var found: [SearchHit] = []
        for (place, text) in candidates {
            guard let range = words.lazy.compactMap({ text.range(of: $0, options: options) }).first else { continue }
            found.append(SearchHit(place: place, snippet: snippet(of: text, around: range)))
            if found.count == limit { break }
        }
        return found
    }

    static func searchableText(of recording: RecordingItem) -> [String] {
        var fields = [recording.title, recording.appName] + recording.tags
        fields += recording.speakerNames.names.values
        if let analysis = recording.analysis {
            fields.append(analysis.summary)
            fields += analysis.decisions
            fields += analysis.tasks.flatMap { [$0.title, $0.owner, $0.due].compactMap { $0 } }
        }
        fields += recording.transcript.map(\.text)
        return fields
    }

    /// Up to `snippetRadius` characters either side of the match, cut at word boundaries, with "…" where text was
    /// left out.
    static func snippet(of text: String, around range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -snippetRadius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: snippetRadius, limitedBy: text.endIndex) ?? text.endIndex

        // Cut the partial words at the edges, but never into the match itself.
        var from = start
        if start != text.startIndex, let space = text[start..<range.lowerBound].firstIndex(of: " ") {
            from = text.index(after: space)
        }
        var to = end
        if end != text.endIndex, let space = text[range.upperBound..<end].lastIndex(of: " ") {
            to = space
        }
        let trimmed = text[from..<to].trimmingCharacters(in: .whitespacesAndNewlines)
        return (start == text.startIndex ? "" : "…") + trimmed + (end == text.endIndex ? "" : "…")
    }
}
