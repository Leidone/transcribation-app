import CodexClient
import Foundation
import Localization

/// Which meetings a conversation is about.
public enum ChatScope: Hashable, Sendable {
    /// Every recording in the library.
    case library
    case recording(UUID)
}

/// A place in a recording an answer rests on, ready to open.
public struct ChatSource: Identifiable, Equatable, Sendable {
    public let recordingID: UUID
    public let title: String
    public let time: TimeInterval?
    public let quote: String?

    public var id: String { "\(recordingID)-\(time ?? -1)" }

    public init(recordingID: UUID, title: String, time: TimeInterval?, quote: String?) {
        self.recordingID = recordingID
        self.title = title
        self.time = time
        self.quote = quote
    }
}

/// One question of a conversation and, once it came, its answer or what went wrong.
public struct ChatTurn: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let question: String
    public var answer: String?
    public var sources: [ChatSource]
    public var error: String?

    public init(id: UUID = UUID(), question: String, answer: String? = nil, sources: [ChatSource] = [], error: String? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
        self.sources = sources
        self.error = error
    }

    public var isWaiting: Bool { answer == nil && error == nil }
}

/// The meetings a question is asked about, in the form the model reads, and how its references map back to them.
public struct MeetingContext: Equatable, Sendable {
    /// Blocks that start with "### M1 · title · date".
    public let text: String
    /// "M1" → the recording it stands for.
    public let references: [String: UUID]
    /// Meetings that did not fit at all.
    public let omitted: Int

    /// About 40 thousand tokens of Russian text: enough for several long calls, well inside every model's window.
    public static let defaultBudget = 100_000

    /// One meeting with everything known about it.
    /// With `previous`, the last meeting of the same series comes along (its summary, decisions and tasks), so
    /// "what changed since last time?" can be answered.
    public static func single(_ recording: RecordingItem, previous: RecordingItem? = nil) -> MeetingContext {
        let reference = "M1"
        var text = block(recording, reference: reference, includesTranscript: true)
        var references = [reference: recording.id]
        if let previous {
            text += "\n\n" + "Previous meeting of the same series:\n"
                + block(previous, reference: "M2", includesTranscript: false)
            references["M2"] = previous.id
        }
        return MeetingContext(text: text, references: references, omitted: 0)
    }

    /// The library for one question: the meetings most related to it first, each with its transcript while there
    /// is room, then only with its summary, until `budget` characters are used. A question that names a period
    /// ("this week", "yesterday") looks at that period's meetings only.
    public static func library(
        _ recordings: [RecordingItem], question: String, budget: Int = defaultBudget,
        now: Date = Date(), calendar: Calendar = .current
    ) -> MeetingContext {
        let period = QuestionPeriod.interval(in: question, now: now, calendar: calendar)
        let usable = recordings.filter { recording in
            (!recording.transcript.isEmpty || recording.analysis != nil)
                && (period.map { $0.contains(recording.startedAt) } ?? true)
        }
        let words = keywords(of: question)
        let ranked = usable
            .map { (recording: $0, score: relevance(of: $0, to: words)) }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.recording.startedAt > rhs.recording.startedAt
            }
            .map(\.recording)

        var blocks: [String] = []
        var references: [String: UUID] = [:]
        var used = 0
        var omitted = 0
        for recording in ranked {
            let reference = "M\(references.count + 1)"
            let full = block(recording, reference: reference, includesTranscript: true)
            let chosen: String
            if used + full.count <= budget {
                chosen = full
            } else {
                let brief = block(recording, reference: reference, includesTranscript: false)
                guard used + brief.count <= budget, recording.analysis != nil else {
                    omitted += 1
                    continue
                }
                chosen = brief
            }
            blocks.append(chosen)
            references[reference] = recording.id
            used += chosen.count
        }
        return MeetingContext(text: blocks.joined(separator: "\n\n"), references: references, omitted: omitted)
    }

    /// The answer's sources as places to open: unknown meetings are dropped, times kept inside the recording, and
    /// the same place is listed once.
    public func sources(of answer: MeetingAnswer, in recordings: [RecordingItem]) -> [ChatSource] {
        var seen: Set<String> = []
        return answer.sources.compactMap { source in
            let reference = source.meeting.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let id = references[reference], let recording = recordings.first(where: { $0.id == id }) else {
                return nil
            }
            let time = source.timestampSeconds.map { min(max(0, $0), max(0, recording.duration)) }
            let place = ChatSource(recordingID: id, title: recording.title, time: time, quote: source.quote)
            return seen.insert(place.id).inserted ? place : nil
        }
    }

    // MARK: Building

    static func block(_ recording: RecordingItem, reference: String, includesTranscript: Bool) -> String {
        let date = recording.startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        var lines = ["### \(reference) · \(recording.title) · \(date) · \(recording.duration.clockString)"]
        if let attendees = recording.meeting?.attendees, !attendees.isEmpty {
            lines.append("Invited: " + attendees.joined(separator: ", "))
        }
        if let analysis = recording.analysis {
            lines.append("Summary: " + analysis.summary)
            if !analysis.decisions.isEmpty {
                lines.append("Decisions: " + analysis.decisions.joined(separator: "; "))
            }
            if !analysis.tasks.isEmpty {
                let tasks = analysis.tasks.map { task in
                    var text = task.title
                    if let owner = task.owner { text += " (\(recording.displayName(owner)))" }
                    if let due = task.due { text += ", due \(due)" }
                    if task.isDone { text += ", done" }
                    return text
                }
                lines.append("Tasks: " + tasks.joined(separator: "; "))
            }
        }
        if !recording.marks.isEmpty {
            lines.append("Marked important: " + recording.marks.map { CompactTranscript.clock($0) }.joined(separator: ", "))
        }
        if includesTranscript, !recording.transcript.isEmpty {
            lines.append("Transcript:\n" + recording.transcriptText)
        }
        return lines.joined(separator: "\n")
    }

    /// Words that are too common to tell meetings apart are left out.
    private static let stopWords: Set<String> = [
        "что", "как", "кто", "где", "когда", "про", "это", "был", "была", "были", "мне", "мой", "моя", "мои", "нас",
        "для", "или", "все", "всё", "его", "её", "они", "там", "так", "уже", "ещё", "еще", "какие", "какой", "какая",
        "the", "what", "who", "when", "where", "how", "about", "was", "were", "did", "does", "and", "for", "with",
    ]

    /// Lowercased word stems of the question: the first five letters, so "бюджета" finds "бюджет".
    static func keywords(of question: String) -> [String] {
        LibrarySearch.terms(of: question.lowercased())
            .filter { $0.count >= 3 && !stopWords.contains($0) }
            .map { String($0.prefix(5)) }
    }

    /// How strongly a meeting is about the question: words found at all count most, then how often.
    static func relevance(of recording: RecordingItem, to words: [String]) -> Int {
        guard !words.isEmpty else { return 0 }
        let text = LibrarySearch.searchableText(of: recording).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return words.reduce(0) { score, word in
            let stem = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let hits = text.components(separatedBy: stem).count - 1
            return score + (hits > 0 ? 100 + min(hits, 50) : 0)
        }
    }
}

extension ChatTurn {
    /// A readable reason when the AI could not be asked.
    public static func notConnectedMessage() -> String {
        tr("Сначала подключите ИИ: кнопка слева внизу.", "Connect an AI first: the button at the bottom left.")
    }
}
