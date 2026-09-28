import Foundation

/// The person's own words: how the recogniser tends to hear a name or a term, and how it is written. Recognition
/// itself cannot be told about them, so they fix the transcript afterwards — whole words only, whatever the case.
public struct Vocabulary: Codable, Equatable, Sendable {
    public struct Rule: Codable, Hashable, Identifiable, Sendable {
        /// Only for the list on screen, so a row keeps its identity while it is edited; not stored, not compared.
        public let id = UUID()
        public var heard: String
        public var written: String

        private enum CodingKeys: String, CodingKey {
            case heard, written
        }

        public init(heard: String, written: String) {
            self.heard = heard
            self.written = written
        }

        public static func == (lhs: Rule, rhs: Rule) -> Bool {
            lhs.heard == rhs.heard && lhs.written == rhs.written
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(heard)
            hasher.combine(written)
        }
    }

    public var rules: [Rule]

    public static let empty = Vocabulary(rules: [])

    public init(rules: [Rule]) {
        self.rules = rules
    }

    /// The text with every heard phrase written as it should be. All rules are matched in one pass, the longest
    /// first, so a replacement is never replaced again by a shorter rule.
    public func apply(to text: String) -> String {
        let usable = rules
            .map { Rule(heard: $0.heard.trimmingCharacters(in: .whitespaces), written: $0.written) }
            .filter { !$0.heard.isEmpty }
            .sorted { $0.heard.count > $1.heard.count }
        guard !usable.isEmpty else { return text }
        let alternatives = usable.map { NSRegularExpression.escapedPattern(for: $0.heard) }.joined(separator: "|")
        // Not inside a longer word: no letter or digit right before or after the phrase.
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        let written = Dictionary(usable.map { ($0.heard.lowercased(), $0.written) }, uniquingKeysWith: { first, _ in first })
        var result = text
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let replacement = written[result[range].lowercased()]
            else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
