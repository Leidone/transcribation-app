import Foundation
import Localization

/// The kind of meeting a summary is written for. Every template keeps the same JSON schema, so the stored result
/// and the interface stay the same; only what the model pays attention to changes.
public enum AnalysisTemplate: String, Codable, CaseIterable, Sendable, Identifiable {
    case general
    case standup
    case interview
    case sales
    case oneOnOne = "one-on-one"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: tr("Обычная встреча", "General meeting")
        case .standup: tr("Планёрка", "Stand-up")
        case .interview: tr("Собеседование", "Job interview")
        case .sales: tr("Встреча с клиентом", "Client call")
        case .oneOnOne: tr("Один на один", "One-on-one")
        }
    }

    public var systemImage: String {
        switch self {
        case .general: "text.bubble"
        case .standup: "sunrise"
        case .interview: "person.text.rectangle"
        case .sales: "briefcase"
        case .oneOnOne: "person.2"
        }
    }

    /// Extra guidance appended to the instructions. Short and in English, like the standard prompt, to keep the
    /// token cost low; `nil` for the general template, which sends the prompt unchanged.
    public var focus: String? {
        switch self {
        case .general:
            nil
        case .standup:
            "Meeting type: daily stand-up. summary: per person, what was done, what is planned and any blockers. tasks: stated next steps and blockers someone took on."
        case .interview:
            "Meeting type: job interview. summary: the candidate's experience, strengths and open concerns as discussed, neutral tone. decisions: agreed next steps of the hiring process. tasks: follow-ups either side promised."
        case .sales:
            "Meeting type: client or sales call. summary: the client's needs, objections, budget and timeline as stated. decisions: what was agreed with the client. tasks: follow-ups promised to the client."
        case .oneOnOne:
            "Meeting type: one-on-one. summary: topics raised, feedback given and concerns, neutral tone. decisions: agreements. tasks: commitments of either person."
        }
    }

    /// The prompt with this template's focus added after the person's own instructions.
    public func applied(to prompt: AnalysisPrompt) -> AnalysisPrompt {
        guard let focus else { return prompt }
        var adapted = prompt
        adapted.instructions = prompt.instructions.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + focus
        return adapted
    }
}
