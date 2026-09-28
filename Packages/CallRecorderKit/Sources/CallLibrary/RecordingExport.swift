import Foundation
import Localization

/// A recording as a document to share: Markdown for notes apps and messengers, HTML as the source of the PDF.
/// Speaker names are the ones the person gave; nothing is sent anywhere by building these.
public enum RecordingExport {
    public struct Options: Equatable, Sendable {
        public var includesTranscript: Bool

        public init(includesTranscript: Bool = true) {
            self.includesTranscript = includesTranscript
        }
    }

    /// Dates follow the interface language, so a Russian document never reads "28 September".
    static var dateStyle: Date.FormatStyle {
        Date.FormatStyle().day().month(.wide).year().hour().minute().locale(Language.current.locale)
    }

    public static func subtitle(of recording: RecordingItem) -> String {
        "\(recording.startedAt.formatted(dateStyle)) · \(recording.duration.clockString) · \(recording.appName)"
    }

    /// A file name without characters that file systems or messengers dislike.
    public static func fileName(of recording: RecordingItem, extension pathExtension: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.whitespacesAndNewlines)
        let cleaned = recording.title.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: " ")
        return (cleaned.isEmpty ? tr("Запись", "Recording") : String(cleaned.prefix(80))) + "." + pathExtension
    }

    // MARK: Markdown

    public static func markdown(of recording: RecordingItem, options: Options = Options()) -> String {
        var parts = ["# \(recording.title)", "_\(subtitle(of: recording))_"]
        if let analysis = recording.analysis {
            parts.append(summaryMarkdown(of: analysis, displayName: recording.displayName))
        }
        if options.includesTranscript, !recording.transcript.isEmpty {
            let lines = recording.transcript.map {
                "**\($0.time.clockString) \(recording.displayName($0.speaker)):** \($0.text)"
            }
            parts.append("## \(tr("Расшифровка", "Transcript"))\n\n" + lines.joined(separator: "\n\n"))
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// Only the result — summary, decisions and tasks — for pasting into a chat.
    public static func summaryMarkdown(of analysis: AnalysisResult, displayName: (String) -> String = { $0 }) -> String {
        var parts = ["## \(tr("Итоги", "Summary"))\n\n\(analysis.summary)"]
        if !analysis.decisions.isEmpty {
            parts.append("## \(tr("Решения", "Decisions"))\n\n" + analysis.decisions.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !analysis.tasks.isEmpty {
            let lines = analysis.tasks.map { "- [\($0.isDone ? "x" : " ")] " + describe($0, displayName: displayName) }
            parts.append("## \(tr("Задачи", "Tasks"))\n\n" + lines.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    /// "Title — owner, срок: due", with whatever of owner and deadline is known.
    public static func describe(_ task: TaskItem, displayName: (String) -> String = { $0 }) -> String {
        var details: [String] = []
        if let owner = task.owner { details.append(displayName(owner)) }
        if let due = task.due { details.append(tr("срок: ", "due: ") + due) }
        return task.title + (details.isEmpty ? "" : " — " + details.joined(separator: ", "))
    }

    // MARK: HTML

    public static func html(of recording: RecordingItem, options: Options = Options()) -> String {
        var body = "<h1>\(escape(recording.title))</h1><p class=\"meta\">\(escape(subtitle(of: recording)))</p>"
        if let analysis = recording.analysis {
            body += "<h2>\(tr("Итоги", "Summary"))</h2><p>\(escape(analysis.summary))</p>"
            if !analysis.decisions.isEmpty {
                body += "<h2>\(tr("Решения", "Decisions"))</h2><ul>"
                    + analysis.decisions.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
            }
            if !analysis.tasks.isEmpty {
                body += "<h2>\(tr("Задачи", "Tasks"))</h2><ul>" + analysis.tasks.map {
                    "<li>\($0.isDone ? "☑" : "☐") \(escape(describe($0, displayName: recording.displayName)))</li>"
                }.joined() + "</ul>"
            }
        }
        if options.includesTranscript, !recording.transcript.isEmpty {
            body += "<h2>\(tr("Расшифровка", "Transcript"))</h2>" + recording.transcript.map {
                "<p><span class=\"time\">\($0.time.clockString)</span> <b>\(escape(recording.displayName($0.speaker)))</b>: \(escape($0.text))</p>"
            }.joined()
        }
        return """
        <!DOCTYPE html><html lang="\(Language.current.rawValue)"><head><meta charset="utf-8"><style>
        body { font: 12pt -apple-system, "Helvetica Neue", sans-serif; color: #1d1d1f; line-height: 1.45; }
        h1 { font-size: 22pt; margin: 0 0 4pt; } h2 { font-size: 15pt; margin: 18pt 0 6pt; }
        .meta, .time { color: #6e6e73; } .time { font-variant-numeric: tabular-nums; }
        </style></head><body>\(body)</body></html>
        """
    }

    /// Text is written by other people and by the model, so every piece is escaped before it goes into HTML.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
